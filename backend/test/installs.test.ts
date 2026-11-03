import { createHash } from 'node:crypto';
import { eq } from 'drizzle-orm';
import { parse as parsePlist } from 'plist';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { clientEvents, installs } from '../src/db/schema.js';
import { BASE_URL, bearer, createTestEnv, json, type TestEnv } from './helpers.js';

describe('installs', () => {
  let env: TestEnv;
  let auth: Record<string, string>;
  const createGrant = (appId: string, version: string | null = null, headers: Record<string, string> = {}) =>
    env.app.inject({ method: 'POST', url: '/api/v1/catalog/installs', headers: { ...auth, ...headers }, payload: { app_id: appId, version } });
  const pathOf = (url: string) => url.replace(BASE_URL, '');

  beforeAll(async () => {
    env = await createTestEnv();
    auth = bearer(env.token);
  });
  afterAll(async () => {
    await env.close();
  });

  it('creates a ready grant with manifest and itms-services URLs', async () => {
    const res = await createGrant('app_quillstack');
    expect(res.statusCode).toBe(201);
    const g = json(res);
    expect(g).toMatchObject({
      app_id: 'app_quillstack',
      version: '3.2.0',
      status: 'ready',
      error_code: null,
      sha256: expect.stringMatching(/^[0-9a-f]{64}$/),
      size_bytes: expect.any(Number),
    });
    expect(g.install_id).toMatch(/^ins_/);
    expect(g.manifest_url).toMatch(new RegExp(`^${BASE_URL}/api/v1/catalog/installs/${g.install_id}/manifest\\.plist\\?t=[A-Za-z0-9_-]+$`));
    expect(g.itms_url).toBe(`itms-services://?action=download-manifest&url=${encodeURIComponent(g.manifest_url)}`);
    const ttl = Date.parse(g.expires_at) - Date.now();
    expect(ttl).toBeGreaterThan(29 * 60_000);
    expect(ttl).toBeLessThanOrEqual(30 * 60_000);

    const polled = await env.app.inject({ url: `/api/v1/catalog/installs/${g.install_id}`, headers: auth });
    expect(polled.statusCode).toBe(200);
    expect(json(polled)).toEqual(g);
  });

  it('serves a valid OTA manifest (XML plist) with bundle id and IPA URL', async () => {
    const g = json(await createGrant('app_quillstack', null, { 'accept-language': 'ru' }));
    const res = await env.app.inject({ url: pathOf(g.manifest_url) });
    expect(res.statusCode).toBe(200);
    expect(res.headers['content-type']).toBe('application/xml; charset=utf-8');
    expect(res.body.startsWith('<?xml version="1.0" encoding="UTF-8"?>')).toBe(true);
    const manifest = parsePlist(res.body) as any;
    const item = manifest.items[0];
    expect(item.metadata).toEqual({
      'bundle-identifier': 'com.example.quillstack',
      'bundle-version': '3.2.0',
      kind: 'software',
      title: 'Quillstack',
    });
    const kinds = item.assets.map((a: { kind: string }) => a.kind);
    expect(kinds).toEqual(['software-package', 'display-image', 'full-size-image']);
    expect(item.assets[0].url).toBe(`${BASE_URL}/api/v1/catalog/installs/${g.install_id}/app.ipa?t=${new URL(g.manifest_url).searchParams.get('t')}`);
    expect(item.assets[1].url).toBe(`${BASE_URL}/static/icons/quillstack-57.png`);
  });

  it('manifest for an IPA with a binary Info.plist', async () => {
    const g = json(await createGrant('app_tilegrove'));
    const manifest = parsePlist((await env.app.inject({ url: pathOf(g.manifest_url) })).body) as any;
    expect(manifest.items[0].metadata['bundle-identifier']).toBe('com.example.tilegrove');
  });

  it('streams the IPA, honours Range with 206 and rejects bad ranges with 416', async () => {
    const g = json(await createGrant('app_quillstack'));
    const ipaUrl = pathOf(g.manifest_url).replace('manifest.plist', 'app.ipa');

    const full = await env.app.inject({ url: ipaUrl });
    expect(full.statusCode).toBe(200);
    expect(full.headers['accept-ranges']).toBe('bytes');
    expect(full.headers['content-type']).toBe('application/octet-stream');
    expect(Number(full.headers['content-length'])).toBe(g.size_bytes);
    expect(createHash('sha256').update(full.rawPayload).digest('hex')).toBe(g.sha256);
    expect(full.rawPayload.subarray(0, 2).toString('latin1')).toBe('PK');

    const part = await env.app.inject({ url: ipaUrl, headers: { range: 'bytes=100-1123' } });
    expect(part.statusCode).toBe(206);
    expect(part.headers['content-range']).toBe(`bytes 100-1123/${g.size_bytes}`);
    expect(part.rawPayload.length).toBe(1024);
    expect(part.rawPayload.equals(full.rawPayload.subarray(100, 1124))).toBe(true);

    const tail = await env.app.inject({ url: ipaUrl, headers: { range: 'bytes=-10' } });
    expect(tail.statusCode).toBe(206);
    expect(tail.rawPayload.equals(full.rawPayload.subarray(-10))).toBe(true);

    const open = await env.app.inject({ url: ipaUrl, headers: { range: `bytes=${g.size_bytes - 5}-` } });
    expect(open.statusCode).toBe(206);
    expect(open.rawPayload.length).toBe(5);

    const bad = await env.app.inject({ url: ipaUrl, headers: { range: `bytes=${g.size_bytes}-` } });
    expect(bad.statusCode).toBe(416);
    expect(bad.headers['content-range']).toBe(`bytes */${g.size_bytes}`);

    const head = await env.app.inject({ method: 'HEAD', url: ipaUrl });
    expect(head.statusCode).toBe(200);
    expect(Number(head.headers['content-length'])).toBe(g.size_bytes);
    expect(head.rawPayload.length).toBe(0);
  });

  it('rejects wrong, missing and expired grant tokens; unknown grants are 404', async () => {
    const g = json(await createGrant('app_quillstack'));
    const manifestPath = `/api/v1/catalog/installs/${g.install_id}/manifest.plist`;
    const ipaPath = `/api/v1/catalog/installs/${g.install_id}/app.ipa`;

    for (const url of [`${manifestPath}?t=wrong`, manifestPath, `${ipaPath}?t=wrong`]) {
      const res = await env.app.inject({ url });
      expect(res.statusCode, url).toBe(401);
      expect(json(res).error.code).toBe('unauthorized');
    }
    expect((await env.app.inject({ url: '/api/v1/catalog/installs/ins_doesnotexist000/manifest.plist?t=x' })).statusCode).toBe(404);
    expect((await env.app.inject({ url: '/api/v1/catalog/installs/../../x/app.ipa?t=x' })).statusCode).toBe(404);

    await env.ctx.db.update(installs).set({ expiresAt: new Date(Date.now() - 1000) }).where(eq(installs.id, g.install_id));
    const expired = await env.app.inject({ url: pathOf(g.manifest_url) });
    expect(expired.statusCode).toBe(401);
    expect(json(expired).error.code).toBe('grant_expired');
    expect((await env.app.inject({ url: `${ipaPath}?${new URL(g.manifest_url).searchParams}` })).statusCode).toBe(401);
    const polled = json(await env.app.inject({ url: `/api/v1/catalog/installs/${g.install_id}`, headers: auth }));
    expect(polled).toMatchObject({ status: 'failed', error_code: 'grant_expired', manifest_url: null, itms_url: null });
  });

  it('errors: 409 no_build, 404 unknown app or version-less app, 401 without token', async () => {
    const noIpa = await createGrant('app_tasklantern');
    expect(noIpa.statusCode).toBe(409);
    expect(json(noIpa).error.code).toBe('no_build');
    const oldVersion = await createGrant('app_quillstack', '3.1.0');
    expect(oldVersion.statusCode).toBe(409);
    expect((await createGrant('app_nope')).statusCode).toBe(404);
    const anon = await env.app.inject({ method: 'POST', url: '/api/v1/catalog/installs', payload: { app_id: 'app_quillstack' } });
    expect(anon.statusCode).toBe(401);
    const other = await env.app.inject({ url: '/api/v1/catalog/installs/ins_doesnotexist000', headers: auth });
    expect(other.statusCode).toBe(404);
  });

  it('records install stage events', async () => {
    const g = json(await createGrant('app_quillstack'));
    const res = await env.app.inject({
      method: 'POST',
      url: `/api/v1/catalog/installs/${g.install_id}/events`,
      headers: auth,
      payload: { stage: 'failed', error_code: 'install_cancelled' },
    });
    expect(res.statusCode).toBe(204);
    const [row] = await env.ctx.db.select().from(installs).where(eq(installs.id, g.install_id));
    expect(row).toMatchObject({ clientStage: 'failed', clientErrorCode: 'install_cancelled' });
    const events = await env.ctx.db.select().from(clientEvents).where(eq(clientEvents.kind, 'install.step'));
    expect(events.some((e) => e.props.install_id === g.install_id)).toBe(true);
    const bad = await env.app.inject({
      method: 'POST',
      url: `/api/v1/catalog/installs/${g.install_id}/events`,
      headers: auth,
      payload: { stage: 'exploded' },
    });
    expect(bad.statusCode).toBe(400);
  });
});
