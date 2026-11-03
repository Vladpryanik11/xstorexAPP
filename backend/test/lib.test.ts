import { mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { inflateSync } from 'node:zlib';
import { parse as parsePlist } from 'plist';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { redactUrl } from '../src/app.js';
import { createUrlHelpers } from '../src/context.js';
import { decodeCursor, encodeCursor } from '../src/lib/pagination.js';
import { ifNoneMatchMatches } from '../src/lib/etag.js';
import { formatSize, resolveLang } from '../src/lib/i18n.js';
import { buildXmlPlist, escapeXml } from '../src/lib/plist.js';
import { encodePng, readPngSize } from '../src/lib/png.js';
import { parseRange } from '../src/lib/range.js';
import { normalizeCode } from '../src/modules/auth/codes.js';
import { buildManifest } from '../src/modules/installs/manifest.js';
import { switchLayout } from '../src/modules/search/text.js';
import { isValidKey } from '../src/storage/blob-storage.js';
import { LocalBlobStorage } from '../src/storage/local.js';

describe('png encoder', () => {
  it('writes a decodable RGB PNG', () => {
    const w = 3;
    const h = 2;
    const px = new Uint8Array(w * h * 3).map((_, i) => (i * 37) % 256);
    const png = encodePng(w, h, px);
    expect(readPngSize(png)).toEqual({ width: 3, height: 2 });
    // Find IDAT, inflate and undo the Paeth filter to compare pixels.
    const idatLen = png.readUInt32BE(33);
    expect(png.toString('ascii', 37, 41)).toBe('IDAT');
    const raw = inflateSync(png.subarray(41, 41 + idatLen));
    const stride = w * 3;
    const out = new Uint8Array(w * h * 3);
    for (let y = 0; y < h; y += 1) {
      expect(raw[y * (stride + 1)]).toBe(4);
      for (let i = 0; i < stride; i += 1) {
        const a = i >= 3 ? out[y * stride + i - 3]! : 0;
        const b = y > 0 ? out[(y - 1) * stride + i]! : 0;
        const c = y > 0 && i >= 3 ? out[(y - 1) * stride + i - 3]! : 0;
        const p = a + b - c;
        const pa = Math.abs(p - a);
        const pb = Math.abs(p - b);
        const pc = Math.abs(p - c);
        const pred = pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
        out[y * stride + i] = (raw[y * (stride + 1) + 1 + i]! + pred) & 0xff;
      }
    }
    expect(Buffer.from(out).equals(Buffer.from(px))).toBe(true);
  });
});

describe('plist', () => {
  it('escapes XML special characters and strips control characters', () => {
    expect(escapeXml(`a&b<c>"d'\u0001`)).toBe('a&amp;b&lt;c&gt;&quot;d&apos;');
  });

  it('builds a manifest that round-trips through a plist parser', () => {
    const xml = buildManifest({
      ipaUrl: 'https://x.test/app.ipa?t=a&b=<c>',
      displayImageUrl: 'https://x.test/57.png',
      fullSizeImageUrl: 'https://x.test/512.png',
      bundleId: 'com.example.app',
      bundleVersion: '1.0',
      title: 'Tom & Jerry <Deluxe>',
    });
    const parsed = parsePlist(xml) as any;
    expect(parsed.items[0].assets[0].url).toBe('https://x.test/app.ipa?t=a&b=<c>');
    expect(parsed.items[0].metadata.title).toBe('Tom & Jerry <Deluxe>');
    expect(buildXmlPlist({ n: 1, f: 1.5, b: true, a: [], d: {} })).toContain('<integer>1</integer>');
  });
});

describe('range parsing', () => {
  it.each([
    [undefined, { kind: 'full' }],
    ['bytes=0-9', { kind: 'partial', range: { start: 0, end: 9 } }],
    ['bytes=90-', { kind: 'partial', range: { start: 90, end: 99 } }],
    ['bytes=-10', { kind: 'partial', range: { start: 90, end: 99 } }],
    ['bytes=-500', { kind: 'partial', range: { start: 0, end: 99 } }],
    ['bytes=50-5000', { kind: 'partial', range: { start: 50, end: 99 } }],
    ['bytes=100-', { kind: 'unsatisfiable' }],
    ['bytes=-0', { kind: 'unsatisfiable' }],
    ['bytes=9-1', { kind: 'full' }],
    ['bytes=0-1,5-6', { kind: 'full' }],
    ['items=0-1', { kind: 'full' }],
  ])('%s', (header, expected) => {
    expect(parseRange(header, 100)).toEqual(expected);
  });
});

describe('small helpers', () => {
  it('resolves Accept-Language', () => {
    expect(resolveLang('ru-RU,ru;q=0.9,en;q=0.8')).toBe('ru');
    expect(resolveLang('en-US,ru;q=0.5')).toBe('en');
    expect(resolveLang('de-DE,ru;q=0.7')).toBe('ru');
    expect(resolveLang('fr')).toBe('en');
    expect(resolveLang('ru;q=0, en')).toBe('en');
    expect(resolveLang(undefined)).toBe('en');
  });

  it('normalizes activation codes', () => {
    expect(normalizeCode(' demo-demo-0001 ')).toBe('DEMODEMO0001');
    expect(normalizeCode('abcd efgh jklm')).toBe('ABCDEFGHJKLM');
    expect(normalizeCode('abcd—efgh–jklm')).toBe('ABCDEFGHJKLM');
    expect(normalizeCode('ab')).toBeNull();
    expect(normalizeCode('ABCD-EFGH-JK$M')).toBeNull();
  });

  it('cursors are opaque and validated', () => {
    expect(decodeCursor(encodeCursor(40))).toBe(40);
    expect(decodeCursor(undefined)).toBe(0);
    expect(() => decodeCursor('bm9wZQ')).toThrow();
    expect(() => decodeCursor(Buffer.from('{"o":-1}').toString('base64url'))).toThrow();
  });

  it('matches If-None-Match lists and weak tags', () => {
    expect(ifNoneMatchMatches('"a", W/"b"', '"b"')).toBe(true);
    expect(ifNoneMatchMatches('*', '"x"')).toBe(true);
    expect(ifNoneMatchMatches('"c"', '"b"')).toBe(false);
  });

  it('redacts secrets in logged URLs', () => {
    expect(redactUrl('/api/v1/catalog/installs/ins_1/app.ipa?t=SECRET&x=1')).toBe('/api/v1/catalog/installs/ins_1/app.ipa?t=[redacted]&x=1');
  });

  it('switches keyboard layout', () => {
    expect(switchLayout('ешдупкщму')).toBe('tilegrove');
    expect(switchLayout('nfqv')).toBe('тайм');
  });

  it('formats sizes and builds asset URLs', () => {
    expect(formatSize(48_211_968, 'en')).toBe('48.2 MB');
    expect(formatSize(48_211_968, 'ru')).toBe('48,2 МБ');
    const urls = createUrlHelpers('https://api.test');
    expect(urls.assetUrl('icons/a b.png')).toBe('https://api.test/static/icons/a%20b.png');
    expect(urls.assetUrl('https://cdn.test/x.png')).toBe('https://cdn.test/x.png');
  });
});

describe('LocalBlobStorage', () => {
  let dir: string;
  let storage: LocalBlobStorage;
  beforeAll(async () => {
    dir = await mkdtemp(path.join(os.tmpdir(), 'istore-blob-'));
    storage = new LocalBlobStorage(dir);
  });
  afterAll(async () => {
    await rm(dir, { recursive: true, force: true });
  });

  it('rejects keys that could escape the root', () => {
    for (const key of ['../x', 'a/../../x', '/etc/passwd', 'a//b', '.hidden', 'a/.git/config', 'C:\\x', 'a\\..\\b', '', 'a/']) {
      expect(isValidKey(key), key).toBe(false);
      expect(() => storage.resolve(key), key).toThrow();
    }
    expect(storage.resolve('static/icons/a.png').startsWith(path.resolve(dir))).toBe(true);
  });

  it('stores, stats, streams ranges and deletes', async () => {
    await storage.put('builds/a/b.bin', Buffer.from('0123456789'));
    expect((await storage.stat('builds/a/b.bin'))?.size).toBe(10);
    const chunks: Buffer[] = [];
    for await (const c of await storage.createReadStream('builds/a/b.bin', { start: 2, end: 4 })) chunks.push(c as Buffer);
    expect(Buffer.concat(chunks).toString()).toBe('234');
    expect(await storage.stat('builds/missing')).toBeNull();
    expect(await storage.stat('../outside')).toBeNull();
    await storage.deletePrefix('builds');
    expect(await storage.stat('builds/a/b.bin')).toBeNull();
  });
});
