import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { searchRequests } from '../src/db/schema.js';
import { bearer, createTestEnv, json, type TestEnv } from './helpers.js';

describe('search', () => {
  let env: TestEnv;
  let auth: Record<string, string>;
  const search = (q: string, extra = '', headers: Record<string, string> = {}) =>
    env.app.inject({ url: `/api/v1/search?q=${encodeURIComponent(q)}${extra}`, headers: { ...auth, ...headers } });

  beforeAll(async () => {
    env = await createTestEnv();
    auth = bearer(env.token);
  });
  afterAll(async () => {
    await env.close();
  });

  it('finds apps by name, case-insensitively, best match first', async () => {
    const res = await search('QUILL');
    expect(res.statusCode).toBe(200);
    expect(res.headers['x-catalog-revision']).toBeDefined();
    const body = json(res);
    expect(body.items[0].id).toBe('app_quillstack');
    expect(body.corrected_query).toBeNull();
    expect(body.next_cursor).toBeNull();
  });

  it('finds by developer and by Russian subtitle (Cyrillic case folding, ё = е)', async () => {
    const dev = json(await search('owlstone'));
    expect(dev.items.map((i: { id: string }) => i.id).sort()).toEqual(['app_lexiglade', 'app_numberwood']);
    const ru = json(await search('МЕТРОНОМ', '', { 'accept-language': 'ru' }));
    expect(ru.items.map((i: { id: string }) => i.id)).toEqual(['app_tunewisp']);
    expect(ru.items[0].subtitle).toBe('Карманный тюнер и метроном');
    const yo = json(await search('ПЛЁНОЧНЫЕ'));
    const ye = json(await search('пленочные'));
    expect(yo.items.map((i: { id: string }) => i.id)).toEqual(['app_prismadrift']);
    expect(ye.items).toEqual(yo.items);
    const localizedName = json(await search('числолес'));
    expect(localizedName.items[0].id).toBe('app_numberwood');
  });

  it('paginates results with a cursor', async () => {
    const first = json(await search('a', '&limit=5'));
    expect(first.items).toHaveLength(5);
    expect(first.next_cursor).toEqual(expect.any(String));
    const second = json(await search('a', `&limit=5&cursor=${first.next_cursor}`));
    const ids = [...first.items, ...second.items].map((i: { id: string }) => i.id);
    expect(new Set(ids).size).toBe(ids.length);
  });

  it('corrects a query typed in the wrong keyboard layout', async () => {
    const body = json(await search('ешдупкщму')); // "tilegrove" typed with a Russian layout
    expect(body.corrected_query).toBe('tilegrove');
    expect(body.items[0].id).toBe('app_tilegrove');
    const nothing = json(await search('zzzzqqqq'));
    expect(nothing).toEqual({ items: [], next_cursor: null, corrected_query: null });
  });

  it('escapes LIKE wildcards and validates q', async () => {
    expect(json(await search('%')).items).toEqual([]);
    expect(json(await search('_')).items).toEqual([]);
    expect((await search('')).statusCode).toBe(400);
    expect((await search('x'.repeat(101))).statusCode).toBe(400);
  });

  it('hints: up to 8, apps carry app_id, developers do not', async () => {
    const res = await env.app.inject({ url: '/api/v1/search/hints?q=t', headers: auth });
    expect(res.statusCode).toBe(200);
    const { hints } = json(res);
    expect(hints.length).toBeGreaterThan(0);
    expect(hints.length).toBeLessThanOrEqual(8);
    expect(hints).toContainEqual({ text: 'tilegrove', app_id: 'app_tilegrove' });
    const dev = json(await env.app.inject({ url: '/api/v1/search/hints?q=gearm', headers: auth })).hints;
    expect(dev).toEqual([{ text: 'gearmint', app_id: null }]);
    const ru = json(await env.app.inject({ url: '/api/v1/search/hints?q=%D1%87%D0%B8%D1%81', headers: { ...auth, 'accept-language': 'ru' } }));
    expect(ru.hints[0]).toEqual({ text: 'числолес', app_id: 'app_numberwood' });
    expect(json(await env.app.inject({ url: '/api/v1/search/hints?q=', headers: auth }))).toEqual({ hints: [] });
  });

  it('accepts "request an app" with 202', async () => {
    const res = await env.app.inject({
      method: 'POST',
      url: '/api/v1/search/requests',
      headers: auth,
      payload: { query: 'Sketchbook for kids', note: null },
    });
    expect(res.statusCode).toBe(202);
    const rows = await env.ctx.db.select().from(searchRequests);
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({ query: 'Sketchbook for kids', accountId: env.seed.devAccountId });
    const bad = await env.app.inject({ method: 'POST', url: '/api/v1/search/requests', headers: auth, payload: { query: '' } });
    expect(bad.statusCode).toBe(400);
  });
});
