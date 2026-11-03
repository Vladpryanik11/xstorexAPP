import http from 'node:http';
import type { AddressInfo } from 'node:net';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { createContext } from '../src/app.js';
import { loadConfig } from '../src/config.js';
import type { Database, Db } from '../src/db/index.js';
import { admin, bearer, createTestEnv, json, type TestEnv } from './helpers.js';

interface SseEvent {
  id?: string;
  event?: string;
  data?: string;
}

/** Minimal SSE client over node:http for tests. */
function openStream(url: string, headers: Record<string, string>) {
  const events: SseEvent[] = [];
  const comments: string[] = [];
  let buffer = '';
  let waiters: (() => void)[] = [];
  let status = 0;
  let responseHeaders: http.IncomingHttpHeaders = {};
  const req = http.get(url, { headers }, (res) => {
    status = res.statusCode ?? 0;
    responseHeaders = res.headers;
    res.setEncoding('utf8');
    res.on('data', (chunk: string) => {
      buffer += chunk;
      let idx: number;
      while ((idx = buffer.indexOf('\n\n')) >= 0) {
        const block = buffer.slice(0, idx);
        buffer = buffer.slice(idx + 2);
        const ev: SseEvent = {};
        for (const line of block.split('\n')) {
          if (line.startsWith(':')) comments.push(line);
          else if (line.startsWith('id: ')) ev.id = line.slice(4);
          else if (line.startsWith('event: ')) ev.event = line.slice(7);
          else if (line.startsWith('data: ')) ev.data = line.slice(6);
        }
        if (ev.event) events.push(ev);
      }
      for (const w of waiters) w();
      waiters = [];
    });
  });
  req.on('error', () => undefined);
  async function waitFor(pred: () => boolean, timeoutMs = 5000) {
    const deadline = Date.now() + timeoutMs;
    while (!pred()) {
      if (Date.now() > deadline) throw new Error(`timeout; events so far: ${JSON.stringify(events)}`);
      await new Promise<void>((resolve) => {
        waiters.push(resolve);
        setTimeout(resolve, 50);
      });
    }
  }
  return {
    events,
    comments,
    waitFor,
    get status() {
      return status;
    },
    get headers() {
      return responseHeaders;
    },
    close: () => req.destroy(),
  };
}

describe('catalog changes', () => {
  let env: TestEnv;
  let auth: Record<string, string>;
  beforeAll(async () => {
    env = await createTestEnv({ catalogJournalLimit: 8 });
    auth = bearer(env.token);
  });
  afterAll(async () => {
    await env.close();
  });

  it('revision grows after an admin PATCH and the change carries the app', async () => {
    const start = json(await env.app.inject({ url: `/api/v1/catalog/changes?since=${env.seed.revision}`, headers: auth }));
    expect(start).toEqual({ revision: env.seed.revision, changes: [], has_more: false, reset: false });

    const patch = await env.app.inject({
      method: 'PATCH',
      url: '/admin/v1/apps/app_tunewisp',
      headers: admin(),
      payload: { subtitle: { en: 'Tuner, metronome, drone', ru: 'Тюнер, метроном, бурдон' }, badge: 'updated' },
    });
    expect(patch.statusCode).toBe(200);

    const res = await env.app.inject({
      url: `/api/v1/catalog/changes?since=${env.seed.revision}`,
      headers: { ...auth, 'accept-language': 'ru' },
    });
    expect(res.statusCode).toBe(200);
    expect(res.headers['x-catalog-revision']).toBe(String(env.seed.revision + 1));
    const body = json(res);
    expect(body.revision).toBe(env.seed.revision + 1);
    expect(body.reset).toBe(false);
    expect(body.changes).toEqual([
      {
        revision: env.seed.revision + 1,
        kind: 'app_upsert',
        app_id: 'app_tunewisp',
        app: expect.objectContaining({ id: 'app_tunewisp', subtitle: 'Тюнер, метроном, бурдон', badge: 'updated' }),
      },
    ]);
  });

  it('pages with has_more and reports removals', async () => {
    const base = json(await env.app.inject({ url: '/api/v1/catalog/changes?since=0&limit=1', headers: auth }));
    // since=0 is older than the pruned journal (limit 8) → reset
    expect(base.reset).toBe(true);
    expect(base.changes).toEqual([]);

    const rev = base.revision;
    await env.app.inject({ method: 'DELETE', url: '/admin/v1/apps/app_moonmoth', headers: admin() });
    await env.app.inject({ method: 'PATCH', url: '/admin/v1/apps/app_wordmoss', headers: admin(), payload: { rating: 4.2 } });
    const page1 = json(await env.app.inject({ url: `/api/v1/catalog/changes?since=${rev}&limit=1`, headers: auth }));
    expect(page1.has_more).toBe(true);
    expect(page1.changes).toEqual([{ revision: rev + 1, kind: 'app_removed', app_id: 'app_moonmoth', app: null }]);
    const page2 = json(await env.app.inject({ url: `/api/v1/catalog/changes?since=${rev + 1}&limit=1`, headers: auth }));
    expect(page2.has_more).toBe(false);
    expect(page2.changes[0]).toMatchObject({ kind: 'app_upsert', app_id: 'app_wordmoss' });
  });

  it('reset: true when since is too old (journal pruned) or from the future', async () => {
    const head = json(await env.app.inject({ url: '/api/v1/catalog/changes?since=0', headers: auth })).revision as number;
    for (let i = 0; i < 9; i += 1) {
      await env.app.inject({ method: 'PATCH', url: '/admin/v1/apps/app_stridefern', headers: admin(), payload: { rating_count: 3000 + i } });
    }
    const old = json(await env.app.inject({ url: `/api/v1/catalog/changes?since=${head}`, headers: auth }));
    expect(old).toEqual({ revision: head + 9, changes: [], has_more: false, reset: true });
    const recent = json(await env.app.inject({ url: `/api/v1/catalog/changes?since=${head + 2}`, headers: auth }));
    expect(recent.reset).toBe(false);
    expect(recent.changes).toHaveLength(7);
    const future = json(await env.app.inject({ url: `/api/v1/catalog/changes?since=${head + 100}`, headers: auth }));
    expect(future.reset).toBe(true);
    expect((await env.app.inject({ url: '/api/v1/catalog/changes', headers: auth })).statusCode).toBe(400);
  });

  it('storefront replacement emits rooms_changed', async () => {
    const head = json(await env.app.inject({ url: '/api/v1/catalog/changes?since=0', headers: auth })).revision as number;
    const put = await env.app.inject({
      method: 'PUT',
      url: '/admin/v1/storefront/games',
      headers: admin(),
      payload: { rooms: [{ id: 'room_games_only', style: 'shelf_one', title: 'Only', app_ids: ['app_tilegrove'] }] },
    });
    expect(put.statusCode).toBe(200);
    const changes = json(await env.app.inject({ url: `/api/v1/catalog/changes?since=${head}`, headers: auth })).changes;
    expect(changes).toEqual([{ revision: head + 1, kind: 'rooms_changed', app_id: null, app: null }]);
  });
});

describe('catalog stream (SSE)', () => {
  let env: TestEnv;
  let base: string;
  beforeAll(async () => {
    env = await createTestEnv({ ssePingMs: 1000 });
    await env.app.listen({ port: 0, host: '127.0.0.1' });
    base = `http://127.0.0.1:${(env.app.server.address() as AddressInfo).port}`;
  });
  afterAll(async () => {
    await env.close();
  });

  it('requires a token', async () => {
    const s = openStream(`${base}/api/v1/catalog/stream`, {});
    await s.waitFor(() => s.status !== 0);
    expect(s.status).toBe(401);
    s.close();
  });

  it('sends hello, catch-up changes after since, live changes and pings', async () => {
    const rev = env.seed.revision;
    await env.app.inject({ method: 'PATCH', url: '/admin/v1/apps/app_lexiglade', headers: admin(), payload: { rating: 4.9 } });

    const s = openStream(`${base}/api/v1/catalog/stream?since=${rev}`, bearer(env.token));
    await s.waitFor(() => s.events.length >= 2);
    expect(s.status).toBe(200);
    expect(s.headers['content-type']).toBe('text/event-stream; charset=utf-8');
    expect(s.events[0]).toEqual({ id: String(rev), event: 'hello', data: JSON.stringify({ revision: rev + 1 }) });
    expect(s.events[1]!.event).toBe('change');
    expect(s.events[1]!.id).toBe(String(rev + 1));
    expect(JSON.parse(s.events[1]!.data!)).toMatchObject({ revision: rev + 1, kind: 'app_upsert', app_id: 'app_lexiglade' });

    await env.app.inject({ method: 'DELETE', url: '/admin/v1/apps/app_frameloom', headers: admin() });
    await s.waitFor(() => s.events.length >= 3);
    expect(s.events[2]).toEqual({
      id: String(rev + 2),
      event: 'change',
      data: JSON.stringify({ revision: rev + 2, kind: 'app_removed', app_id: 'app_frameloom', app: null }),
    });

    await s.waitFor(() => s.comments.includes(': ping'), 3000);
    s.close();
  });

  it('resumes from Last-Event-ID and resets on a stale id', async () => {
    const head = json(await env.app.inject({ url: '/api/v1/catalog/changes?since=0', headers: bearer(env.token) })).revision as number;
    const s = openStream(`${base}/api/v1/catalog/stream?since=0`, { ...bearer(env.token), 'last-event-id': String(head - 1) });
    await s.waitFor(() => s.events.length >= 2);
    expect(s.events.map((e) => e.event)).toEqual(['hello', 'change']);
    expect(s.events[1]!.id).toBe(String(head));
    s.close();

    const stale = openStream(`${base}/api/v1/catalog/stream?since=${head + 50}`, bearer(env.token));
    await stale.waitFor(() => stale.events.length >= 2);
    expect(stale.events[1]).toEqual({ id: String(head), event: 'reset', data: JSON.stringify({ revision: head }) });
    stale.close();
  });
});

describe('catalog bus', () => {
  it('logs a failed pump through the app logger', async () => {
    const errors: string[] = [];
    const brokenDb = {
      select: () => {
        throw new Error('database is down');
      },
    } as unknown as Db;
    const log = { info: () => undefined, error: (_obj: object, msg: string) => errors.push(msg) };
    const ctx = createContext(loadConfig({}, process.cwd()), { db: brokenDb } as Database, { log });
    await ctx.bus.notify();
    expect(errors).toEqual(['catalog bus pump failed']);
  });
});
