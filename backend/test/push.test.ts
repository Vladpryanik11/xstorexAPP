import { generateKeyPairSync, verify } from 'node:crypto';
import http2 from 'node:http2';
import type { AddressInfo } from 'node:net';
import { eq } from 'drizzle-orm';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { loadConfig } from '../src/config.js';
import { accounts, pushTokens } from '../src/db/schema.js';
import { compareVersions } from '../src/lib/version.js';
import { ApnsSender } from '../src/push/apns.js';
import type { PushMessage, PushResult, PushSender } from '../src/push/push-sender.js';
import { buildSyntheticIpa } from '../src/seed/synthetic-ipa.js';
import { activate, admin, bearer, createTestEnv, json, multipart, type TestEnv } from './helpers.js';

const { privateKey, publicKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
const keyPem = privateKey.export({ type: 'pkcs8', format: 'pem' }).toString();
const APNS = { keyId: 'KEY1234567', teamId: 'TEAM123456', keyPem, topic: 'com.istore.app' };

class RecordingSender implements PushSender {
  readonly enabled = true;
  sent: PushMessage[] = [];
  readonly dead = new Set<string>();

  async send(message: PushMessage): Promise<PushResult> {
    this.sent.push(message);
    if (this.dead.has(message.token)) return { ok: false, status: 410, reason: 'Unregistered', unregistered: true };
    return { ok: true };
  }

  async close(): Promise<void> {}
}

describe('compareVersions', () => {
  it('compares numeric parts', () => {
    expect(compareVersions('3.10.0', '3.9.9')).toBe(1);
    expect(compareVersions('2.0', '2')).toBe(0);
    expect(compareVersions('1.2.3', '1.2.4')).toBe(-1);
    expect(compareVersions('1.0-beta', '1.0')).toBe(0);
  });
});

describe('APNs config', () => {
  it('is off by default, all-or-nothing, and validates the key', () => {
    expect(loadConfig({}).apns).toBeNull();
    expect(() => loadConfig({ APNS_KEY_ID: 'KEY1234567' })).toThrow(/partially configured.*APNS_TEAM_ID, APNS_KEY_BASE64/);
    expect(() =>
      loadConfig({ APNS_KEY_ID: 'KEY1234567', APNS_TEAM_ID: 'TEAM123456', APNS_KEY_BASE64: Buffer.from('nope').toString('base64') }),
    ).toThrow(/not a base64-encoded \.p8 key/);
    expect(() => loadConfig({ APNS_KEY_ID: 'short', APNS_TEAM_ID: 'TEAM123456', APNS_KEY_BASE64: 'x' })).toThrow(/APNS_KEY_ID/);
    const config = loadConfig({
      APNS_KEY_ID: 'KEY1234567',
      APNS_TEAM_ID: 'TEAM123456',
      APNS_KEY_BASE64: Buffer.from(keyPem).toString('base64'),
    });
    expect(config.apns).toEqual(APNS);
  });
});

describe('ApnsSender', () => {
  const seen: { headers: http2.IncomingHttpHeaders; body: string }[] = [];
  let server: http2.Http2Server;
  let origin: string;
  let expiredOnce = true;

  beforeAll(async () => {
    // Локальный HTTP/2 без TLS вместо APNs: ответы зависят от токена устройства в пути.
    server = http2.createServer();
    server.on('stream', (stream, headers) => {
      const chunks: Buffer[] = [];
      stream.on('data', (chunk: Buffer) => chunks.push(chunk));
      stream.on('end', () => {
        seen.push({ headers, body: Buffer.concat(chunks).toString('utf8') });
        const reply = (status: number, reason?: string) => {
          stream.respond({ ':status': status, 'content-type': 'application/json' });
          stream.end(reason ? JSON.stringify({ reason }) : '');
        };
        const token = String(headers[':path']).split('/').pop();
        if (token === 'aa01') reply(200);
        else if (token === 'dead') reply(410, 'Unregistered');
        else if (token === 'bad0') reply(400, 'BadDeviceToken');
        else if (token === 'exp0' && expiredOnce) {
          expiredOnce = false;
          reply(403, 'ExpiredProviderToken');
        } else if (token === 'exp0') reply(200);
        else reply(500, 'InternalServerError');
      });
    });
    await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
    origin = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  });
  afterAll(async () => {
    await new Promise<void>((resolve) => server.close(() => resolve()));
  });

  const makeSender = () => new ApnsSender(APNS, { origins: { production: origin, sandbox: origin }, now: () => 1_762_000_000_000 });
  const message = (token: string): PushMessage => ({ token, env: 'production', payload: { aps: { alert: 'hi' } } });

  it('sends an alert with a valid ES256 provider token', async () => {
    const sender = makeSender();
    try {
      const result = await sender.send({ ...message('aa01'), env: 'sandbox', collapseId: 'c1', ttlSeconds: 60 });
      expect(result).toEqual({ ok: true });
      const request = seen.at(-1)!;
      expect(request.headers).toMatchObject({
        ':method': 'POST',
        ':path': '/3/device/aa01',
        'apns-topic': 'com.istore.app',
        'apns-push-type': 'alert',
        'apns-priority': '10',
        'apns-collapse-id': 'c1',
        'apns-expiration': String(1_762_000_000 + 60),
      });
      expect(JSON.parse(request.body)).toEqual({ aps: { alert: 'hi' } });

      const jwt = String(request.headers.authorization).replace(/^bearer /, '');
      const [header, claims, signature] = jwt.split('.');
      expect(JSON.parse(Buffer.from(header!, 'base64url').toString())).toEqual({ alg: 'ES256', kid: 'KEY1234567' });
      expect(JSON.parse(Buffer.from(claims!, 'base64url').toString())).toEqual({ iss: 'TEAM123456', iat: 1_762_000_000 });
      const valid = verify(
        'sha256',
        Buffer.from(`${header}.${claims}`),
        { key: publicKey, dsaEncoding: 'ieee-p1363' },
        Buffer.from(signature!, 'base64url'),
      );
      expect(valid).toBe(true);
    } finally {
      await sender.close();
    }
  });

  it('maps failures and retries an expired provider token once', async () => {
    const sender = makeSender();
    try {
      expect(await sender.send(message('dead'))).toEqual({ ok: false, status: 410, reason: 'Unregistered', unregistered: true });
      expect(await sender.send(message('bad0'))).toEqual({ ok: false, status: 400, reason: 'BadDeviceToken', unregistered: true });
      expect(await sender.send(message('boom'))).toEqual({
        ok: false,
        status: 500,
        reason: 'InternalServerError',
        unregistered: false,
      });
      const before = seen.length;
      expect(await sender.send(message('exp0'))).toEqual({ ok: true });
      expect(seen.length - before).toBe(2);
    } finally {
      await sender.close();
    }
  });

  it('reports an unreachable APNs without dropping the token', async () => {
    const sender = new ApnsSender(APNS, { origins: { production: 'http://127.0.0.1:1' } });
    try {
      expect(await sender.send(message('aa01'))).toMatchObject({ ok: false, status: 0, unregistered: false });
    } finally {
      await sender.close();
    }
  });
});

describe('app update notifications', () => {
  let env: TestEnv;
  const sender = new RecordingSender();
  const APNS_TOKENS = { ru: 'a'.repeat(64), en: 'b'.repeat(64), muted: 'c'.repeat(64), signedOut: 'd'.repeat(64) };
  let signedOutAccountId = '';
  let mutedToken = '';

  const registerPush = (token: string, apnsToken: string, locale: string) =>
    env.app.inject({
      method: 'POST',
      url: '/api/v1/client/push-token',
      headers: bearer(token),
      payload: { apns_token: apnsToken, apns_env: 'production', locale },
    });
  const follow = (token: string) =>
    env.app.inject({ method: 'POST', url: '/api/v1/apps/app_quillstack/follow', headers: bearer(token) });
  const upload = (version: string, build: string, notes?: string) => {
    const ipa = buildSyntheticIpa({ bundleId: 'com.example.quillstack', version, build, name: 'Quillstack' });
    const body = multipart(notes ? { notes } : {}, { field: 'ipa', filename: 'app.ipa', data: ipa });
    return env.app.inject({
      method: 'POST',
      url: '/admin/v1/apps/app_quillstack/builds',
      headers: admin(body.headers),
      payload: body.payload,
    });
  };
  const sentTokens = () => sender.sent.map((m) => m.token).sort();
  const card = async () =>
    json(await env.app.inject({ url: '/api/v1/catalog/apps/app_quillstack', headers: bearer(env.token) }));

  beforeAll(async () => {
    env = await createTestEnv({}, { push: sender });
    expect((await registerPush(env.token, APNS_TOKENS.ru, 'ru_RU')).statusCode).toBe(204);
    await follow(env.token);

    const en = json(await activate(env.app, env.seed.codes[0]!, '1a2b3c4d-1111-4a5b-8c6d-7e8f9a0b1c2d')).token;
    await registerPush(en, APNS_TOKENS.en, 'en_US');
    await follow(en);

    mutedToken = json(await activate(env.app, env.seed.codes[1]!, '2b3c4d5e-2222-4b6c-9d7e-8f9a0b1c2d3e')).token;
    await registerPush(mutedToken, APNS_TOKENS.muted, 'ru_RU');
    await follow(mutedToken);
    await env.app.inject({
      method: 'PUT',
      url: '/api/v1/apps/app_quillstack/follow/mute',
      headers: bearer(mutedToken),
      payload: { muted: true },
    });

    const out = json(await activate(env.app, env.seed.codes[2]!, '3c4d5e6f-3333-4c7d-8e8f-9a0b1c2d3e4f'));
    signedOutAccountId = out.account.id;
    await registerPush(out.token, APNS_TOKENS.signedOut, 'en_US');
    await follow(out.token);
    await env.app.inject({ method: 'POST', url: '/api/v1/app/sign-out', headers: bearer(out.token) });
  });
  afterAll(async () => {
    await env.close();
  });

  it('notifies active, unmuted, signed-in followers in their language', async () => {
    sender.sent = [];
    expect((await upload('3.3.0', '330', 'Faster sync')).statusCode).toBe(201);
    await env.ctx.push.drain();
    expect(sentTokens()).toEqual([APNS_TOKENS.ru, APNS_TOKENS.en]);
    const ru = sender.sent.find((m) => m.token === APNS_TOKENS.ru)!;
    expect(ru).toMatchObject({ env: 'production', collapseId: 'update-app_quillstack', ttlSeconds: 86_400 });
    expect(ru.payload).toEqual({
      aps: {
        alert: { title: 'Quillstack', body: 'Вышла версия 3.3.0. Faster sync' },
        sound: 'default',
        'thread-id': 'app_update',
      },
      kind: 'app_update',
      app_id: 'app_quillstack',
      version: '3.3.0',
    });
    const en = sender.sent.find((m) => m.token === APNS_TOKENS.en)!;
    expect(en.payload).toMatchObject({ aps: { alert: { body: 'Version 3.3.0 is out. Faster sync' } } });
  });

  it('stays quiet for the same or an older version', async () => {
    sender.sent = [];
    expect((await upload('3.3.0', '331')).statusCode).toBe(201);
    expect((await upload('3.2.5', '325')).statusCode).toBe(201);
    await env.ctx.push.drain();
    expect(sender.sent).toEqual([]);
    // Сборка в историю не откатывает карточку, пересборка той же версии не стирает «Что нового».
    expect(await card()).toMatchObject({ version: '3.3.0', whats_new: 'Faster sync' });
  });

  it('a new version without notes drops the previous notes', async () => {
    sender.sent = [];
    expect((await upload('3.3.5', '335')).statusCode).toBe(201);
    await env.ctx.push.drain();
    const ru = sender.sent.find((m) => m.token === APNS_TOKENS.ru)!;
    expect(ru.payload).toMatchObject({ aps: { alert: { body: 'Вышла версия 3.3.5' } }, version: '3.3.5' });
    expect(await card()).toMatchObject({ version: '3.3.5', whats_new: null });
  });

  it('removes dead tokens and skips expired accounts', async () => {
    sender.sent = [];
    sender.dead.add(APNS_TOKENS.en);
    await upload('3.4.0', '340');
    await env.ctx.push.drain();
    expect(sentTokens()).toEqual([APNS_TOKENS.ru, APNS_TOKENS.en]);
    expect(await env.ctx.db.select().from(pushTokens).where(eq(pushTokens.apnsToken, APNS_TOKENS.en))).toEqual([]);

    sender.sent = [];
    await env.ctx.db.update(accounts).set({ expiresAt: new Date(Date.now() - 1000) }).where(eq(accounts.id, env.seed.devAccountId));
    await upload('3.5.0', '350');
    await env.ctx.push.drain();
    expect(sender.sent).toEqual([]);
  });

  it('admin test push reaches signed-in devices of an account', async () => {
    sender.sent = [];
    const res = await env.app.inject({
      method: 'POST',
      url: '/admin/v1/push/test',
      headers: admin(),
      payload: { account_id: env.seed.devAccountId },
    });
    expect(res.statusCode).toBe(200);
    expect(json(res)).toEqual({ devices: 1, sent: 1, failed: 0, removed: 0, errors: [] });
    expect(sender.sent[0]!.payload).toMatchObject({
      kind: 'test',
      aps: { alert: { title: 'Xstore', body: 'Тестовое уведомление: push работает.' } },
    });

    const signedOut = await env.app.inject({
      method: 'POST',
      url: '/admin/v1/push/test',
      headers: admin(),
      payload: { account_id: signedOutAccountId },
    });
    expect(json(signedOut)).toMatchObject({ devices: 0, sent: 0 });
    const unknown = await env.app.inject({ method: 'POST', url: '/admin/v1/push/test', headers: admin(), payload: { account_id: 'acc_nope' } });
    expect(unknown.statusCode).toBe(404);
  });

  it('a re-registered APNs token belongs only to the newest device', async () => {
    expect((await registerPush(mutedToken, APNS_TOKENS.ru, 'ru_RU')).statusCode).toBe(204);
    const rows = await env.ctx.db.select().from(pushTokens).where(eq(pushTokens.apnsToken, APNS_TOKENS.ru));
    const mutedDevice = json(await env.app.inject({ url: '/api/v1/client/profile', headers: bearer(mutedToken) })).device.id;
    expect(rows.map((r) => r.deviceId)).toEqual([mutedDevice]);
  });
});

describe('push without APNs', () => {
  let env: TestEnv;
  beforeAll(async () => {
    env = await createTestEnv();
  });
  afterAll(async () => {
    await env.close();
  });

  it('admin test push answers 503 and uploads still work', async () => {
    const res = await env.app.inject({
      method: 'POST',
      url: '/admin/v1/push/test',
      headers: admin(),
      payload: { account_id: env.seed.devAccountId },
    });
    expect(res.statusCode).toBe(503);
    expect(json(res).error.code).toBe('push_disabled');
    expect(env.ctx.push.enabled).toBe(false);
  });
});
