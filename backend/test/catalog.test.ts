import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { encodePng } from '../src/lib/png.js';
import { admin, BASE_URL, bearer, createTestEnv, json, type TestEnv } from './helpers.js';

describe('catalog', () => {
  let env: TestEnv;
  let auth: Record<string, string>;
  beforeAll(async () => {
    env = await createTestEnv();
    auth = bearer(env.token);
  });
  afterAll(async () => {
    await env.close();
  });

  it('groupings: rooms of all four styles with the documented shape', async () => {
    const res = await env.app.inject({ url: '/api/v1/groupings?tab=today', headers: auth });
    expect(res.statusCode).toBe(200);
    expect(res.headers['x-catalog-revision']).toBe(String(env.seed.revision));
    expect(res.headers.etag).toMatch(/^".+"$/);
    const body = json(res);
    expect(body.tab).toBe('today');
    expect(body.revision).toBe(env.seed.revision);
    const styles = body.rooms.map((r: { style: string }) => r.style);
    expect(new Set(styles)).toEqual(new Set(['hero_carousel', 'shelf_one', 'shelf_two', 'chips']));
    for (const room of body.rooms) {
      expect(Object.keys(room).sort()).toEqual(['categories', 'has_more', 'hero', 'id', 'items', 'style', 'subtitle', 'title']);
    }

    const hero = body.rooms.find((r: { style: string }) => r.style === 'hero_carousel');
    expect(hero.hero.length).toBeGreaterThan(0);
    expect(hero.hero.length).toBeLessThanOrEqual(8);
    expect(hero.hero[0]).toMatchObject({
      headline: expect.any(String),
      title: expect.any(String),
      image_url: expect.stringMatching(new RegExp(`^${BASE_URL}/static/hero/`)),
      gradient: [expect.stringMatching(/^#[0-9A-F]{6}$/), expect.stringMatching(/^#[0-9A-F]{6}$/)],
    });
    expect(hero.hero[0].app.id).toBe('app_quillstack');

    const shelf = body.rooms.find((r: { id: string }) => r.id === 'room_today_new');
    expect(shelf.style).toBe('shelf_one');
    expect(shelf.items).toHaveLength(12);
    expect(shelf.has_more).toBe(true);
    const summary = shelf.items[0];
    expect(Object.keys(summary).sort()).toEqual(
      [
        'availability', 'badge', 'bg_color', 'category', 'icon_url', 'id', 'min_os', 'name', 'rating', 'rating_count',
        'size_bytes', 'subtitle', 'tint_dark', 'tint_light', 'version',
      ].sort(),
    );
    expect(summary.icon_url).toMatch(new RegExp(`^${BASE_URL}/static/icons/.+\\.png$`));

    const two = body.rooms.find((r: { style: string }) => r.style === 'shelf_two');
    expect(two.items.length).toBeLessThanOrEqual(8);
    const chips = body.rooms.find((r: { style: string }) => r.style === 'chips');
    expect(chips.categories[0]).toEqual({ id: 'productivity', name: 'Productivity', sf_symbol: 'checkmark.circle' });
    expect(chips.items).toEqual([]);
  });

  it('groupings: other tabs and validation', async () => {
    const games = json(await env.app.inject({ url: '/api/v1/groupings?tab=games', headers: auth }));
    const gameIds = games.rooms.flatMap((r: { items: { category: { id: string } }[] }) => r.items.map((i) => i.category.id));
    expect(new Set(gameIds)).toEqual(new Set(['puzzle', 'arcade']));
    const apps = await env.app.inject({ url: '/api/v1/groupings?tab=apps', headers: auth });
    expect(apps.statusCode).toBe(200);
    const bad = await env.app.inject({ url: '/api/v1/groupings?tab=music', headers: auth });
    expect(bad.statusCode).toBe(400);
    expect(json(bad).error.code).toBe('invalid_request');
  });

  it('ETag + If-None-Match → 304, and a new ETag after a change', async () => {
    const first = await env.app.inject({ url: '/api/v1/groupings?tab=apps', headers: auth });
    const etag = first.headers.etag as string;
    const again = await env.app.inject({ url: '/api/v1/groupings?tab=apps', headers: { ...auth, 'if-none-match': etag } });
    expect(again.statusCode).toBe(304);
    expect(again.body).toBe('');
    expect(again.headers.etag).toBe(etag);
    // Language is part of the representation.
    const ru = await env.app.inject({
      url: '/api/v1/groupings?tab=apps',
      headers: { ...auth, 'if-none-match': etag, 'accept-language': 'ru' },
    });
    expect(ru.statusCode).toBe(200);

    await env.app.inject({ method: 'PATCH', url: '/admin/v1/apps/app_unitbloom', headers: admin(), payload: { rating: 4.1 } });
    const changed = await env.app.inject({ url: '/api/v1/groupings?tab=apps', headers: { ...auth, 'if-none-match': etag } });
    expect(changed.statusCode).toBe(200);
    expect(changed.headers.etag).not.toBe(etag);
  });

  it('"See all": cursor pagination over a room', async () => {
    const seen: string[] = [];
    let cursor: string | null = null;
    const sizes: number[] = [];
    do {
      const url: string = `/api/v1/groupings/room_today_new?limit=10${cursor ? `&cursor=${cursor}` : ''}`;
      const res = await env.app.inject({ url, headers: auth });
      expect(res.statusCode).toBe(200);
      const body = json(res);
      expect(body.room).toEqual({ id: 'room_today_new', title: 'New & Updated', style: 'shelf_one' });
      sizes.push(body.items.length);
      seen.push(...body.items.map((i: { id: string }) => i.id));
      cursor = body.next_cursor;
    } while (cursor);
    expect(sizes).toEqual([10, 10, 4]);
    expect(new Set(seen).size).toBe(24);

    expect((await env.app.inject({ url: '/api/v1/groupings/room_nope', headers: auth })).statusCode).toBe(404);
    expect((await env.app.inject({ url: '/api/v1/groupings/room_today_new?limit=51', headers: auth })).statusCode).toBe(400);
    expect((await env.app.inject({ url: '/api/v1/groupings/room_today_new?cursor=%%%', headers: auth })).statusCode).toBe(400);
  });

  it('app card: Accept-Language ru/en with en fallback', async () => {
    const en = await env.app.inject({ url: '/api/v1/catalog/apps/app_numberwood', headers: auth });
    expect(en.statusCode).toBe(200);
    const enBody = json(en);
    expect(enBody).toMatchObject({
      id: 'app_numberwood',
      name: 'Numberwood',
      subtitle: 'Math puzzles for curious kids',
      developer: 'Owlstone Learning',
      bundle_id: 'com.example.numberwood',
      category: { id: 'education', name: 'Education' },
      languages: expect.arrayContaining(['EN', 'RU']),
    });
    expect(enBody.screenshots).toHaveLength(3);
    expect(enBody.screenshots[0]).toEqual({ url: `${BASE_URL}/static/screens/numberwood-1.png`, width: 645, height: 1398 });
    expect(enBody.info).toContainEqual({ label: 'Developer', value: 'Owlstone Learning' });
    expect(enBody.similar.length).toBeGreaterThan(0);
    expect(enBody.similar[0].category.id).toBe('education');
    expect(enBody.similar.map((s: { id: string }) => s.id)).not.toContain('app_numberwood');

    const ru = json(await env.app.inject({ url: '/api/v1/catalog/apps/app_numberwood', headers: { ...auth, 'accept-language': 'ru-RU,ru;q=0.9,en;q=0.5' } }));
    expect(ru.name).toBe('Числолес');
    expect(ru.subtitle).toBe('Математические задачки для любопытных');
    expect(ru.category.name).toBe('Образование');
    expect(ru.info).toContainEqual({ label: 'Разработчик', value: 'Owlstone Learning' });

    // Unknown language → en
    const de = json(await env.app.inject({ url: '/api/v1/catalog/apps/app_numberwood', headers: { ...auth, 'accept-language': 'de' } }));
    expect(de.name).toBe('Numberwood');
  });

  it('app card: 404 after unpublishing; hidden from rooms', async () => {
    const before = await env.app.inject({ url: '/api/v1/catalog/apps/app_cubelark', headers: auth });
    expect(before.statusCode).toBe(200);
    const del = await env.app.inject({ method: 'DELETE', url: '/admin/v1/apps/app_cubelark', headers: admin() });
    expect(del.statusCode).toBe(204);
    const after = await env.app.inject({ url: '/api/v1/catalog/apps/app_cubelark', headers: auth });
    expect(after.statusCode).toBe(404);
    expect(json(after).error.code).toBe('not_found');
    const games = json(await env.app.inject({ url: '/api/v1/groupings/room_games_top?limit=50', headers: auth }));
    expect(games.items.map((i: { id: string }) => i.id)).not.toContain('app_cubelark');
    expect((await env.app.inject({ url: '/api/v1/catalog/apps/app_cubelark/versions', headers: auth })).statusCode).toBe(404);
  });

  it('versions and category screens are paginated', async () => {
    const versions = await env.app.inject({ url: '/api/v1/catalog/apps/app_quillstack/versions?limit=2', headers: auth });
    expect(versions.statusCode).toBe(200);
    const v = json(versions);
    expect(v.items).toHaveLength(2);
    expect(v.items[0]).toMatchObject({ version: '3.2.0', build: '30200', size_bytes: expect.any(Number), notes: expect.any(String) });
    expect(v.next_cursor).toEqual(expect.any(String));

    const cat = json(await env.app.inject({ url: '/api/v1/catalog/categories/arcade?limit=3', headers: { ...auth, 'accept-language': 'ru' } }));
    expect(cat.category).toEqual({ id: 'arcade', name: 'Аркады', sf_symbol: 'gamecontroller' });
    expect(cat.items).toHaveLength(3);
    const ratings = cat.items.map((i: { rating: number }) => i.rating);
    expect([...ratings].sort((a, b) => b - a)).toEqual(ratings);
    const rest = json(await env.app.inject({ url: `/api/v1/catalog/categories/arcade?limit=3&cursor=${cat.next_cursor}`, headers: auth }));
    expect(rest.items).toHaveLength(2);
    expect(rest.next_cursor).toBeNull();
    expect((await env.app.inject({ url: '/api/v1/catalog/categories/nope', headers: auth })).statusCode).toBe(404);
  });

  it('serves static images and refuses path traversal', async () => {
    const png = encodePng(2, 2, new Uint8Array(12).fill(200));
    await env.ctx.storage.put('static/icons/test.png', png);
    const res = await env.app.inject({ url: '/static/icons/test.png' });
    expect(res.statusCode).toBe(200);
    expect(res.headers['content-type']).toBe('image/png');
    expect(res.rawPayload.equals(png)).toBe(true);
    const cached = await env.app.inject({ url: '/static/icons/test.png', headers: { 'if-none-match': res.headers.etag as string } });
    expect(cached.statusCode).toBe(304);

    for (const url of [
      '/static/../package.json',
      '/static/%2e%2e/%2e%2e/package.json',
      '/static/icons/..%2f..%2fbuilds',
      '/static/.tmp/x',
      '/static/icons\\..\\..\\x',
      '/static/icons/missing.png',
    ]) {
      const r = await env.app.inject({ url });
      expect(r.statusCode, url).toBe(404);
    }
  });
});
