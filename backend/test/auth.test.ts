import { eq } from 'drizzle-orm';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { accounts } from '../src/db/schema.js';
import { activate, bearer, createTestEnv, json, type TestEnv } from './helpers.js';

const INSTALL_A = '3f2504e0-4f89-41d3-9a0c-0305e82c3301';
const INSTALL_B = '9b2c7d1e-1111-4a2b-8c3d-1234567890ab';

describe('auth', () => {
  let env: TestEnv;
  beforeAll(async () => {
    env = await createTestEnv({ activateRateLimit: { max: 1000, timeWindowMs: 60_000 } });
  });
  afterAll(async () => {
    await env.close();
  });

  it('activates a device with a valid code', async () => {
    const res = await activate(env.app, 'DEMO-DEMO-0001', INSTALL_A);
    expect(res.statusCode).toBe(200);
    const body = json(res);
    expect(body.token).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect(body.account).toMatchObject({
      plan: { id: 'month', name: '1 month', period_months: 1 },
      status: 'active',
      display_name: null,
    });
    expect(body.account.id).toMatch(/^acc_/);
    const days = (Date.parse(body.account.expires_at) - Date.now()) / 86_400_000;
    expect(days).toBeGreaterThan(29);
    expect(days).toBeLessThanOrEqual(30);
    expect(body.account.expires_at).toMatch(/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$/);

    const profile = await env.app.inject({
      url: '/api/v1/client/profile',
      headers: bearer(body.token, { 'accept-language': 'ru', 'x-client-build': '101' }),
    });
    expect(profile.statusCode).toBe(200);
    expect(json(profile)).toMatchObject({
      account: { id: body.account.id, plan: { name: '1 месяц' } },
      device: { model: 'iPhone16,2', os_version: '18.1', install_id_last4: '3301' },
      client: { locale: 'ru_RU', app_build: '101' },
    });
  });

  it('re-activation with the same install_id is idempotent and returns a new token', async () => {
    const first = json(await activate(env.app, 'DEMO-DEMO-0001', INSTALL_A.toUpperCase()));
    const second = await activate(env.app, 'demo demo 0001', INSTALL_A);
    expect(second.statusCode).toBe(200);
    const body = json(second);
    expect(body.token).not.toBe(first.token);
    expect(body.account.id).toBe(first.account.id);
    // The previous token of this device is revoked.
    const old = await env.app.inject({ url: '/api/v1/client/profile', headers: bearer(first.token) });
    expect(old.statusCode).toBe(401);
  });

  it('rejects a used code on another device with 409 code_used', async () => {
    const res = await activate(env.app, 'DEMO-DEMO-0001', INSTALL_B);
    expect(res.statusCode).toBe(409);
    expect(json(res)).toEqual({ error: { code: 'code_used', message: expect.any(String) } });
  });

  it('returns 404 invalid_code for unknown or malformed codes', async () => {
    for (const code of ['ZZZZ-ZZZZ-ZZZZ', '!!', 'DEMO']) {
      const res = await activate(env.app, code, INSTALL_B);
      expect(res.statusCode).toBe(404);
      expect(json(res).error.code).toBe('invalid_code');
    }
  });

  it('normalizes codes: case, spaces and dashes', async () => {
    const [code] = env.seed.codes;
    const messy = ` ${code!.toLowerCase().replace(/-/g, ' - ')} `;
    const res = await activate(env.app, messy, INSTALL_B);
    expect(res.statusCode).toBe(200);
  });

  it('validates the request body', async () => {
    const res = await env.app.inject({
      method: 'POST',
      url: '/api/v1/app/activate',
      payload: { activation_code: 'DEMO-DEMO-0001', device: { install_id: 'not-a-uuid' } },
    });
    expect(res.statusCode).toBe(400);
    expect(json(res).error.code).toBe('invalid_request');
  });

  it('answers 401 without a token or with a bad one', async () => {
    const none = await env.app.inject({ url: '/api/v1/groupings?tab=today' });
    expect(none.statusCode).toBe(401);
    expect(json(none)).toEqual({ error: { code: 'unauthorized', message: expect.any(String) } });
    const bad = await env.app.inject({ url: '/api/v1/client/profile', headers: bearer('x'.repeat(43)) });
    expect(bad.statusCode).toBe(401);
    const scheme = await env.app.inject({ url: '/api/v1/client/profile', headers: { authorization: `Basic ${env.token}` } });
    expect(scheme.statusCode).toBe(401);
  });

  it('sign-out revokes the token (empty JSON body is accepted)', async () => {
    const { token } = json(await activate(env.app, env.seed.codes[1]!, '0b5f8c3a-2222-4c1d-9e8f-abcdefabcdef'));
    const out = await env.app.inject({
      method: 'POST',
      url: '/api/v1/app/sign-out',
      headers: bearer(token, { 'content-type': 'application/json' }),
    });
    expect(out.statusCode).toBe(204);
    const after = await env.app.inject({ url: '/api/v1/client/profile', headers: bearer(token) });
    expect(after.statusCode).toBe(401);
  });

  it('expired subscription: 403 account_inactive on catalog, profile still works', async () => {
    const { token, account } = json(await activate(env.app, env.seed.codes[2]!, '7d9e0a1b-3333-4e5f-8a9b-0c1d2e3f4a5b'));
    await env.ctx.db.update(accounts).set({ expiresAt: new Date(Date.now() - 1000) }).where(eq(accounts.id, account.id));
    const catalog = await env.app.inject({ url: '/api/v1/groupings?tab=today', headers: bearer(token) });
    expect(catalog.statusCode).toBe(403);
    expect(json(catalog).error.code).toBe('account_inactive');
    const profile = await env.app.inject({ url: '/api/v1/client/profile', headers: bearer(token) });
    expect(profile.statusCode).toBe(200);
    expect(json(profile).account.status).toBe('expired');
  });

  it('localizes error messages', async () => {
    const res = await env.app.inject({ url: '/api/v1/client/profile', headers: { 'accept-language': 'ru-RU,ru;q=0.9' } });
    expect(json(res).error.message).toBe('Войдите заново.');
  });
});

describe('auth rate limit', () => {
  let env: TestEnv;
  beforeAll(async () => {
    env = await createTestEnv({ activateRateLimit: { max: 3, timeWindowMs: 60_000 } });
  });
  afterAll(async () => {
    await env.close();
  });

  it('limits /app/activate with 429 rate_limited and Retry-After', async () => {
    const codes: number[] = [];
    for (let i = 0; i < 4; i += 1) codes.push((await activate(env.app, 'NOPE-NOPE-NOPE', INSTALL_B)).statusCode);
    expect(codes.slice(0, 3)).toEqual([404, 404, 404]);
    const limited = await activate(env.app, 'NOPE-NOPE-NOPE', INSTALL_B);
    expect(limited.statusCode).toBe(429);
    expect(limited.headers['retry-after']).toBeDefined();
    expect(json(limited).error.code).toBe('rate_limited');
  });
});
