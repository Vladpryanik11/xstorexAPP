import { eq } from 'drizzle-orm';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { accounts } from '../src/db/schema.js';
import { activate, admin, bearer, createTestEnv, json, type TestEnv } from './helpers.js';

describe('follows', () => {
  let env: TestEnv;
  let other: string;
  beforeAll(async () => {
    env = await createTestEnv();
    other = json(await activate(env.app, env.seed.codes[0]!, '5a1c2d3e-4444-4b5c-8d6e-7f8091a2b3c4')).token;
  });
  afterAll(async () => {
    await env.close();
  });

  const follow = (id: string, token = env.token) =>
    env.app.inject({ method: 'POST', url: `/api/v1/apps/${id}/follow`, headers: bearer(token) });
  const unfollow = (id: string, token = env.token) =>
    env.app.inject({ method: 'DELETE', url: `/api/v1/apps/${id}/follow`, headers: bearer(token) });
  const mute = (id: string, muted: unknown) =>
    env.app.inject({ method: 'PUT', url: `/api/v1/apps/${id}/follow/mute`, headers: bearer(env.token), payload: { muted } });
  const status = async (id: string) =>
    json(await env.app.inject({ url: `/api/v1/apps/${id}/follow`, headers: bearer(env.token) }));
  const list = async (query = '') =>
    json(await env.app.inject({ url: `/api/v1/client/follows${query}`, headers: bearer(env.token, { 'accept-language': 'ru' }) }));

  it('follow is idempotent and counts followers across accounts', async () => {
    expect(await status('app_quillstack')).toEqual({
      app_id: 'app_quillstack',
      following: false,
      muted: false,
      follower_count: 0,
    });
    const first = await follow('app_quillstack');
    expect(first.statusCode).toBe(200);
    expect(json(first)).toMatchObject({ following: true, muted: false, follower_count: 1 });
    expect(json(await follow('app_quillstack'))).toMatchObject({ following: true, follower_count: 1 });
    expect(json(await follow('app_quillstack', other))).toMatchObject({ following: true, follower_count: 2 });
    expect(await status('app_quillstack')).toMatchObject({ following: true, follower_count: 2 });
  });

  it('lists follows newest first with cursor pagination', async () => {
    await follow('app_numberwood');
    await follow('app_cubelark');
    const all = await list();
    expect(all.items.map((i: any) => i.app.id)).toEqual(['app_cubelark', 'app_numberwood', 'app_quillstack']);
    expect(all.next_cursor).toBeNull();
    expect(all.items[0]).toMatchObject({ muted: false, app: { id: 'app_cubelark', availability: 'available' } });
    expect(all.items[0].followed_at).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/);

    const p1 = await list('?limit=2');
    expect(p1.items.map((i: any) => i.app.id)).toEqual(['app_cubelark', 'app_numberwood']);
    expect(p1.next_cursor).toEqual(expect.any(String));
    const p2 = await list(`?limit=2&cursor=${p1.next_cursor}`);
    expect(p2.items.map((i: any) => i.app.id)).toEqual(['app_quillstack']);
    expect(p2.next_cursor).toBeNull();

    // Другой аккаунт видит только свои подписки.
    const theirs = json(await env.app.inject({ url: '/api/v1/client/follows', headers: bearer(other) }));
    expect(theirs.items.map((i: any) => i.app.id)).toEqual(['app_quillstack']);
  });

  it('mute requires a follow and survives a repeated follow', async () => {
    const muted = await mute('app_cubelark', true);
    expect(muted.statusCode).toBe(200);
    expect(json(muted)).toMatchObject({ following: true, muted: true });
    expect(json(await follow('app_cubelark'))).toMatchObject({ muted: true });
    expect((await list()).items[0]).toMatchObject({ app: { id: 'app_cubelark' }, muted: true });

    await unfollow('app_cubelark');
    const missing = await mute('app_cubelark', true);
    expect(missing.statusCode).toBe(409);
    expect(json(missing).error.code).toBe('not_following');
    expect((await mute('app_numberwood', 'yes')).statusCode).toBe(400);
  });

  it('unfollow is idempotent and resets mute', async () => {
    await follow('app_cubelark');
    const res = await unfollow('app_cubelark');
    expect(res.statusCode).toBe(200);
    expect(json(res)).toMatchObject({ following: false, muted: false });
    expect(json(await unfollow('app_cubelark'))).toMatchObject({ following: false });
    expect((await list()).items.map((i: any) => i.app.id)).toEqual(['app_numberwood', 'app_quillstack']);
  });

  it('unpublished apps are 404 and hidden from the list, the follow is kept', async () => {
    const patch = (published: boolean) =>
      env.app.inject({ method: 'PATCH', url: '/admin/v1/apps/app_numberwood', headers: admin(), payload: { published } });
    expect((await patch(false)).statusCode).toBe(200);
    expect((await env.app.inject({ url: '/api/v1/apps/app_numberwood/follow', headers: bearer(env.token) })).statusCode).toBe(404);
    expect((await follow('app_numberwood')).statusCode).toBe(404);
    expect((await list()).items.map((i: any) => i.app.id)).toEqual(['app_quillstack']);
    expect((await patch(true)).statusCode).toBe(200);
    expect((await list()).items.map((i: any) => i.app.id)).toEqual(['app_numberwood', 'app_quillstack']);
  });

  it('rejects unknown apps, missing tokens and inactive accounts', async () => {
    const unknown = await follow('app_does_not_exist');
    expect(unknown.statusCode).toBe(404);
    expect(json(unknown).error.code).toBe('not_found');
    expect((await env.app.inject({ method: 'POST', url: '/api/v1/apps/app_quillstack/follow' })).statusCode).toBe(401);
    expect((await env.app.inject({ url: '/api/v1/client/follows' })).statusCode).toBe(401);
    expect((await env.app.inject({ url: '/api/v1/client/follows?cursor=!!', headers: bearer(env.token) })).statusCode).toBe(400);

    const { token, account } = json(await activate(env.app, env.seed.codes[1]!, '6b2d3e4f-5555-4c6d-9e7f-8091a2b3c4d5'));
    await env.ctx.db.update(accounts).set({ expiresAt: new Date(Date.now() - 1000) }).where(eq(accounts.id, account.id));
    const inactive = await follow('app_quillstack', token);
    expect(inactive.statusCode).toBe(403);
    expect(json(inactive).error.code).toBe('account_inactive');
  });
});
