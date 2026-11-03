import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { clientEvents, pushTokens } from '../src/db/schema.js';
import { admin, bearer, createTestEnv, json, type TestEnv } from './helpers.js';

describe('client', () => {
  let env: TestEnv;
  beforeAll(async () => {
    env = await createTestEnv();
  });
  afterAll(async () => {
    await env.close();
  });

  it('store-state is public and open by default', async () => {
    const res = await env.app.inject({ url: '/api/v1/client/store-state' });
    expect(res.statusCode).toBe(200);
    expect(json(res)).toEqual({ state: 'open', closed: null });
  });

  it('store-state reflects the admin closing the store (localized)', async () => {
    const put = await env.app.inject({
      method: 'PUT',
      url: '/admin/v1/store-state',
      headers: admin(),
      payload: {
        state: 'closed',
        closed: {
          title: { en: 'Back soon', ru: 'Скоро вернёмся' },
          message: 'Maintenance',
          reopens_at: '2026-11-03T12:00:00.000Z',
          links: [{ title: { en: 'News', ru: 'Новости' }, url: 'https://t.me/example' }],
        },
      },
    });
    expect(put.statusCode).toBe(200);
    const ru = json(await env.app.inject({ url: '/api/v1/client/store-state', headers: { 'accept-language': 'ru' } }));
    expect(ru).toEqual({
      state: 'closed',
      closed: {
        title: 'Скоро вернёмся',
        message: 'Maintenance',
        reopens_at: '2026-11-03T12:00:00Z',
        links: [{ title: 'Новости', url: 'https://t.me/example' }],
      },
    });
    const bad = await env.app.inject({
      method: 'PUT',
      url: '/admin/v1/store-state',
      headers: admin(),
      payload: { state: 'closed', closed: { links: [{ title: 'x', url: 'javascript:alert(1)' }] } },
    });
    expect(bad.statusCode).toBe(400);
    await env.app.inject({ method: 'PUT', url: '/admin/v1/store-state', headers: admin(), payload: { state: 'open' } });
    expect(json(await env.app.inject({ url: '/api/v1/client/store-state' })).state).toBe('open');
  });

  it('client version: update_available and mandatory', async () => {
    const seeded = json(await env.app.inject({ url: '/api/v1/client/version?build=95' }));
    expect(seeded).toMatchObject({ latest_build: 100, min_supported_build: 90, update_available: true, mandatory: false });

    const put = await env.app.inject({
      method: 'PUT',
      url: '/admin/v1/client-version',
      headers: admin(),
      payload: {
        latest_version: '1.2.0',
        latest_build: 120,
        min_supported_build: 100,
        release_notes: { en: 'Faster installs', ru: 'Быстрее установка' },
        update_url: 'itms-services://?action=download-manifest&url=https%3A%2F%2Fapi.istore.test%2Fclient.plist',
      },
    });
    expect(put.statusCode).toBe(200);

    const old = json(await env.app.inject({ url: '/api/v1/client/version?build=99', headers: { 'accept-language': 'ru' } }));
    expect(old).toEqual({
      latest_version: '1.2.0',
      latest_build: 120,
      min_supported_build: 100,
      update_available: true,
      mandatory: true,
      release_notes: 'Быстрее установка',
      update_url: 'itms-services://?action=download-manifest&url=https%3A%2F%2Fapi.istore.test%2Fclient.plist',
    });
    const supported = json(await env.app.inject({ url: '/api/v1/client/version', headers: { 'x-client-build': '100' } }));
    expect(supported).toMatchObject({ update_available: true, mandatory: false });
    const latest = json(await env.app.inject({ url: '/api/v1/client/version?build=120' }));
    expect(latest).toMatchObject({ update_available: false, mandatory: false });

    expect((await env.app.inject({ url: '/api/v1/client/version' })).statusCode).toBe(400);
    expect((await env.app.inject({ url: '/api/v1/client/version?build=abc' })).statusCode).toBe(400);
    const inverted = await env.app.inject({
      method: 'PUT',
      url: '/admin/v1/client-version',
      headers: admin(),
      payload: { latest_version: '1.0.0', latest_build: 10, min_supported_build: 20 },
    });
    expect(inverted.statusCode).toBe(400);
  });

  it('accepts telemetry events (202) and validates them', async () => {
    const auth = bearer(env.token);
    const res = await env.app.inject({
      method: 'POST',
      url: '/api/v1/client/events',
      headers: auth,
      payload: {
        events: [
          { kind: 'app.launch', ts: '2026-11-02T12:00:00Z', props: { cold: true } },
          { kind: 'net.error', ts: '2026-11-02T12:00:01Z', props: { path: '/groupings', code: -1009 } },
        ],
      },
    });
    expect(res.statusCode).toBe(202);
    expect(await env.ctx.db.select().from(clientEvents)).toHaveLength(2);

    const tooMany = { events: Array.from({ length: 101 }, () => ({ kind: 'app.launch', ts: '2026-11-02T12:00:00Z' })) };
    expect((await env.app.inject({ method: 'POST', url: '/api/v1/client/events', headers: auth, payload: tooMany })).statusCode).toBe(400);
    const badKind = { events: [{ kind: 'spy', ts: '2026-11-02T12:00:00Z' }] };
    expect((await env.app.inject({ method: 'POST', url: '/api/v1/client/events', headers: auth, payload: badKind })).statusCode).toBe(400);
    expect((await env.app.inject({ method: 'POST', url: '/api/v1/client/events', payload: { events: [] } })).statusCode).toBe(401);
  });

  it('stores the push token per device (204, upsert)', async () => {
    const auth = bearer(env.token);
    const send = (token: string) =>
      env.app.inject({
        method: 'POST',
        url: '/api/v1/client/push-token',
        headers: auth,
        payload: { apns_token: token, apns_env: 'sandbox', locale: 'ru_RU', tz_offset_minutes: 180 },
      });
    expect((await send('ab'.repeat(32))).statusCode).toBe(204);
    expect((await send('CD'.repeat(32))).statusCode).toBe(204);
    const rows = await env.ctx.db.select().from(pushTokens);
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({ apnsToken: 'cd'.repeat(32), apnsEnv: 'sandbox', tzOffsetMinutes: 180 });
    expect((await send('not hex')).statusCode).toBe(400);
  });

  it('returns JSON errors for unknown routes and malformed JSON', async () => {
    const missing = await env.app.inject({ url: '/api/v1/nope' });
    expect(missing.statusCode).toBe(404);
    expect(json(missing)).toEqual({ error: { code: 'not_found', message: 'Not found' } });
    const malformed = await env.app.inject({
      method: 'POST',
      url: '/api/v1/app/activate',
      headers: { 'content-type': 'application/json' },
      payload: '{"activation_code":',
    });
    expect(malformed.statusCode).toBe(400);
    expect(json(malformed).error.code).toBe('invalid_request');
    expect(missing.headers['x-content-type-options']).toBe('nosniff');
    expect(missing.headers['access-control-allow-origin']).toBeUndefined();
  });
});
