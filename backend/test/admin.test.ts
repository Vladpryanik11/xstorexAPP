import { createHash } from 'node:crypto';
import { zipSync } from 'fflate';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { buildSyntheticIpa } from '../src/seed/synthetic-ipa.js';
import { activate, admin, bearer, createTestEnv, json, multipart, type TestEnv } from './helpers.js';

const NEW_APP = {
  id: 'app_pebblenote',
  name: { en: 'Pebblenote', ru: 'Галька' },
  subtitle: 'Tiny journal',
  description: { en: 'A tiny journal.', ru: 'Крошечный дневник.' },
  developer: 'Pebble Ink',
  category_id: 'productivity',
  icon_url: 'icons/pebblenote.png',
  tint_light: '#123456',
  tint_dark: '#abcdef',
  bg_color: '#F0F0F0',
  rating: null,
  languages: ['en', 'ru'],
};

describe('admin API', () => {
  let env: TestEnv;
  beforeAll(async () => {
    env = await createTestEnv();
  });
  afterAll(async () => {
    await env.close();
  });

  const upload = (appId: string, ipa: Uint8Array, fields: Record<string, string> = {}) => {
    const body = multipart(fields, { field: 'ipa', filename: 'app.ipa', data: ipa });
    return env.app.inject({ method: 'POST', url: `/admin/v1/apps/${appId}/builds`, headers: admin(body.headers), payload: body.payload });
  };

  it('requires the admin bearer token', async () => {
    expect((await env.app.inject({ method: 'POST', url: '/admin/v1/apps', payload: NEW_APP })).statusCode).toBe(401);
    const wrong = await env.app.inject({ method: 'POST', url: '/admin/v1/apps', headers: bearer(env.token), payload: NEW_APP });
    expect(wrong.statusCode).toBe(401);
    expect(json(wrong).error.code).toBe('unauthorized');
  });

  it('creates an app that shows up in the catalog', async () => {
    const res = await env.app.inject({ method: 'POST', url: '/admin/v1/apps', headers: admin(), payload: NEW_APP });
    expect(res.statusCode).toBe(201);
    expect(json(res)).toMatchObject({ id: 'app_pebblenote', published: true, tint_dark: '#ABCDEF', languages: ['EN', 'RU'] });
    const card = await env.app.inject({ url: '/api/v1/catalog/apps/app_pebblenote', headers: bearer(env.token, { 'accept-language': 'ru' }) });
    expect(card.statusCode).toBe(200);
    expect(json(card)).toMatchObject({ name: 'Галька', subtitle: 'Tiny journal', category: { name: 'Продуктивность' } });

    const dup = await env.app.inject({ method: 'POST', url: '/admin/v1/apps', headers: admin(), payload: NEW_APP });
    expect(dup.statusCode).toBe(400);
    const badCat = await env.app.inject({
      method: 'POST',
      url: '/admin/v1/apps',
      headers: admin(),
      payload: { ...NEW_APP, id: 'app_other', category_id: 'nope' },
    });
    expect(badCat.statusCode).toBe(400);
    const extra = await env.app.inject({
      method: 'POST',
      url: '/admin/v1/apps',
      headers: admin(),
      payload: { ...NEW_APP, id: 'app_other2', hacker: true },
    });
    expect(extra.statusCode).toBe(400);
  });

  it('uploads a build: sha256, size, bundle id and version come from the IPA', async () => {
    const ipa = buildSyntheticIpa({ bundleId: 'com.example.pebblenote', version: '1.4.0', build: '140', name: 'Pebblenote', minOs: '16.0' });
    const res = await upload('app_pebblenote', ipa, { notes: 'First build', build: '140' });
    expect(res.statusCode).toBe(201);
    const build = json(res);
    expect(build).toMatchObject({
      app_id: 'app_pebblenote',
      version: '1.4.0',
      build: '140',
      bundle_id: 'com.example.pebblenote',
      min_os: '16.0',
      size_bytes: ipa.length,
      sha256: createHash('sha256').update(ipa).digest('hex'),
      notes: 'First build',
    });

    const card = json(await env.app.inject({ url: '/api/v1/catalog/apps/app_pebblenote', headers: bearer(env.token) }));
    expect(card).toMatchObject({ version: '1.4.0', size_bytes: ipa.length, bundle_id: 'com.example.pebblenote', min_os: '16.0' });

    const grant = await env.app.inject({ method: 'POST', url: '/api/v1/catalog/installs', headers: bearer(env.token), payload: { app_id: 'app_pebblenote', version: '1.4.0' } });
    expect(grant.statusCode).toBe(201);
  });

  it('reads a binary Info.plist and checks bundle id consistency', async () => {
    const ok = buildSyntheticIpa({ bundleId: 'com.example.pebblenote', version: '1.5.0', build: '150', name: 'P', binaryPlist: true, appDir: 'Pebble Note.app' });
    const res = await upload('app_pebblenote', ok);
    expect(res.statusCode).toBe(201);
    expect(json(res)).toMatchObject({ version: '1.5.0', bundle_id: 'com.example.pebblenote' });

    const mismatch = buildSyntheticIpa({ bundleId: 'com.example.someoneelse', version: '1.6.0', build: '160', name: 'X' });
    const conflict = await upload('app_pebblenote', mismatch);
    expect(conflict.statusCode).toBe(409);
    expect(json(conflict).error.code).toBe('bundle_id_mismatch');

    const wrongVersion = await upload('app_pebblenote', ok, { version: '9.9.9' });
    expect(wrongVersion.statusCode).toBe(400);
  });

  it('rejects broken archives and missing files', async () => {
    const notZip = await upload('app_pebblenote', new TextEncoder().encode('definitely not a zip'));
    expect(notZip.statusCode).toBe(400);
    expect(json(notZip).error.code).toBe('invalid_ipa');

    const noPlist = zipSync({ 'Payload/Demo.app/readme.txt': new TextEncoder().encode('hi') });
    const missing = await upload('app_pebblenote', noPlist);
    expect(missing.statusCode).toBe(400);
    expect(json(missing).error.message).toContain('Info.plist');

    const noFile = multipart({ version: '1.0' });
    const nf = await env.app.inject({ method: 'POST', url: '/admin/v1/apps/app_pebblenote/builds', headers: admin(noFile.headers), payload: noFile.payload });
    expect(nf.statusCode).toBe(400);

    const unknown = await upload('app_missing', noPlist);
    expect(unknown.statusCode).toBe(404);
  });

  it('enforces the upload size limit', async () => {
    const small = await createTestEnv({ maxUploadBytes: 1024 });
    try {
      const ipa = buildSyntheticIpa({ bundleId: 'com.example.quillstack', version: '9.0.0', build: '900', name: 'Q', padBytes: 4096 });
      const body = multipart({}, { field: 'ipa', filename: 'big.ipa', data: ipa });
      const res = await small.app.inject({ method: 'POST', url: '/admin/v1/apps/app_quillstack/builds', headers: admin(body.headers), payload: body.payload });
      expect(res.statusCode).toBe(413);
      expect(json(res).error.code).toBe('payload_too_large');
    } finally {
      await small.close();
    }
  });

  it('PATCH and DELETE apps', async () => {
    const patch = await env.app.inject({ method: 'PATCH', url: '/admin/v1/apps/app_pebblenote', headers: admin(), payload: { badge: 'new', published: true } });
    expect(patch.statusCode).toBe(200);
    expect(json(patch).badge).toBe('new');
    expect((await env.app.inject({ method: 'PATCH', url: '/admin/v1/apps/app_missing', headers: admin(), payload: { badge: 'new' } })).statusCode).toBe(404);
    expect((await env.app.inject({ method: 'PATCH', url: '/admin/v1/apps/app_pebblenote', headers: admin(), payload: { tint_light: 'blue' } })).statusCode).toBe(400);
    expect((await env.app.inject({ method: 'DELETE', url: '/admin/v1/apps/app_pebblenote', headers: admin() })).statusCode).toBe(204);
    const fetched = json(await env.app.inject({ url: '/admin/v1/apps/app_pebblenote', headers: admin() }));
    expect(fetched.published).toBe(false);
  });

  it('replaces a storefront tab and validates rooms', async () => {
    const payload = {
      rooms: [
        {
          id: 'room_apps_hero2',
          style: 'hero_carousel',
          hero: [{ app_id: 'app_skyvellum', headline: 'Hi', title: { en: 'Sky', ru: 'Небо' }, gradient: ['#000000', '#ffffff'] }],
        },
        { id: 'room_apps_list', style: 'shelf_two', title: { en: 'List', ru: 'Список' }, app_ids: ['app_skyvellum', 'app_unitbloom'] },
        { id: 'room_apps_chips2', style: 'chips', category_ids: ['music', 'health'] },
      ],
    };
    const res = await env.app.inject({ method: 'PUT', url: '/admin/v1/storefront/apps', headers: admin(), payload });
    expect(res.statusCode).toBe(200);
    const view = json(await env.app.inject({ url: '/api/v1/groupings?tab=apps', headers: bearer(env.token, { 'accept-language': 'ru' }) }));
    expect(view.rooms.map((r: { id: string }) => r.id)).toEqual(['room_apps_hero2', 'room_apps_list', 'room_apps_chips2']);
    expect(view.rooms[0].hero[0]).toMatchObject({ title: 'Небо', headline: 'Hi', gradient: ['#000000', '#FFFFFF'] });
    expect(view.rooms[1].title).toBe('Список');
    expect(view.rooms[2].categories.map((c: { id: string }) => c.id)).toEqual(['music', 'health']);

    const bad = [
      { rooms: [{ id: 'room_x', style: 'shelf_one', app_ids: [] }] },
      { rooms: [{ id: 'room_x', style: 'shelf_one', app_ids: ['app_unknown'] }] },
      { rooms: [{ id: 'room_x', style: 'hero_carousel' }] },
      { rooms: [{ id: 'bad id', style: 'chips', category_ids: ['music'] }] },
      { rooms: [{ id: 'room_x', style: 'chips', category_ids: ['music'] }, { id: 'room_x', style: 'chips', category_ids: ['music'] }] },
    ];
    for (const p of bad) {
      const r = await env.app.inject({ method: 'PUT', url: '/admin/v1/storefront/apps', headers: admin(), payload: p });
      expect(r.statusCode, JSON.stringify(p)).toBe(400);
    }
    const taken = await env.app.inject({
      method: 'PUT',
      url: '/admin/v1/storefront/apps',
      headers: admin(),
      payload: { rooms: [{ id: 'room_hero_today', style: 'chips', category_ids: ['music'] }] },
    });
    expect(taken.statusCode).toBe(409);
    expect((await env.app.inject({ method: 'PUT', url: '/admin/v1/storefront/movies', headers: admin(), payload })).statusCode).toBe(400);
  });

  it('generates activation codes that work once', async () => {
    const res = await env.app.inject({ method: 'POST', url: '/admin/v1/activation-codes', headers: admin(), payload: { count: 3, plan_id: 'quarter' } });
    expect(res.statusCode).toBe(201);
    const { codes } = json(res);
    expect(codes).toHaveLength(3);
    for (const c of codes) expect(c).toMatch(/^[A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4}$/);
    const act = await activate(env.app, codes[0], 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee');
    expect(act.statusCode).toBe(200);
    expect(json(act).account.plan).toMatchObject({ id: 'quarter', period_months: 3 });
    const bad = await env.app.inject({ method: 'POST', url: '/admin/v1/activation-codes', headers: admin(), payload: { count: 1, plan_id: 'forever' } });
    expect(bad.statusCode).toBe(400);
  });

  it('upserts categories (extension of the contract)', async () => {
    const res = await env.app.inject({
      method: 'PUT',
      url: '/admin/v1/categories/travel',
      headers: admin(),
      payload: { kind: 'apps', name: { en: 'Travel', ru: 'Путешествия' }, sf_symbol: 'airplane' },
    });
    expect(res.statusCode).toBe(200);
    const cat = json(await env.app.inject({ url: '/api/v1/catalog/categories/travel', headers: bearer(env.token, { 'accept-language': 'ru' }) }));
    expect(cat).toEqual({ category: { id: 'travel', name: 'Путешествия', sf_symbol: 'airplane' }, items: [], next_cursor: null });
  });
});

describe('admin API without ADMIN_TOKEN', () => {
  let env: TestEnv;
  beforeAll(async () => {
    env = await createTestEnv({ adminToken: null });
  });
  afterAll(async () => {
    await env.close();
  });

  it('answers 503 admin_disabled', async () => {
    const res = await env.app.inject({ method: 'POST', url: '/admin/v1/activation-codes', headers: admin(), payload: { count: 1, plan_id: 'month' } });
    expect(res.statusCode).toBe(503);
    expect(json(res).error.code).toBe('admin_disabled');
  });
});
