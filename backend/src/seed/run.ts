import { randomUUID } from 'node:crypto';
import { mkdir, rm, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { sql } from 'drizzle-orm';
import type { AppContext } from '../context.js';
import { ensureSingletons } from '../db/index.js';
import { accounts, appBuilds, categories, clientVersion, devices, storeState, tokens } from '../db/schema.js';
import { randomToken, sha256Hex } from '../lib/crypto.js';
import { createApp } from '../modules/admin/apps.js';
import { addBuildFromFile, digestFile } from '../modules/admin/builds.js';
import { createActivationCodes, insertActivationCode } from '../modules/admin/codes.js';
import { replaceStorefront, type StorefrontInput } from '../modules/admin/storefront.js';
import { APPS, appId, CATEGORIES, STOREFRONT, type SeedApp } from './data.js';
import { renderHero, renderIcon, renderScreenshot } from './images.js';
import { buildSyntheticIpa } from './synthetic-ipa.js';

export const DEMO_CODE = 'DEMO-DEMO-0001';
export const DEV_INSTALL_ID = '00000000-0000-4000-8000-000000000001';
export const SCREENSHOT_SIZE = { width: 645, height: 1398 } as const;

export interface SeedOptions {
  /** Render PNG assets into storage (slow-ish); tests skip it. */
  images?: boolean;
  /** Number of random activation codes besides DEMO-DEMO-0001. */
  extraCodes?: number;
  log?: (line: string) => void;
}

export interface SeedResult {
  apps: number;
  categories: number;
  rooms: number;
  revision: number;
  demoCode: string;
  codes: string[];
  devToken: string;
  devAccountId: string;
  installableApps: string[];
}

const TABLES = [
  'client_events',
  'search_requests',
  'push_tokens',
  'installs',
  'tokens',
  'activation_codes',
  'devices',
  'accounts',
  'plans',
  'room_items',
  'rooms',
  'screenshots',
  'app_builds',
  'apps',
  'categories',
  'catalog_changes',
  'store_state',
  'client_version',
];

const DAY = 24 * 60 * 60 * 1000;

function olderVersions(version: string): string[] {
  const [major = 1, minor = 0] = version.split('.').map((n) => Number.parseInt(n, 10) || 0);
  const out: string[] = [];
  if (minor > 0) out.push(`${major}.${minor - 1}.0`);
  if (minor > 1) out.push(`${major}.${minor - 2}.0`);
  else if (major > 1) out.push(`${major - 1}.9.0`);
  return out.slice(0, 2);
}

const buildNumber = (version: string) =>
  String(
    version
      .split('.')
      .map((n) => Number.parseInt(n, 10) || 0)
      .reduce((acc, n) => acc * 100 + n, 0),
  );

function localizedName(app: SeedApp): { en: string; ru: string } {
  return typeof app.name === 'string' ? { en: app.name, ru: app.name } : app.name;
}

/** Wipes the database and storage, then loads the demo catalog. */
export async function seedDemo(ctx: AppContext, options: SeedOptions = {}): Promise<SeedResult> {
  const log = options.log ?? (() => undefined);
  const renderImages = options.images ?? true;
  const now = ctx.now();

  await ctx.db.execute(sql.raw(`TRUNCATE TABLE ${TABLES.map((t) => `"${t}"`).join(', ')} RESTART IDENTITY CASCADE`));
  await ensureSingletons(ctx.db);
  await ctx.storage.deletePrefix('static');
  await ctx.storage.deletePrefix('builds');
  await ctx.bus.init();

  // тарифы создаёт ensureSingletons выше
  await ctx.db.insert(categories).values(
    CATEGORIES.map((c, i) => ({ id: c.id, kind: c.kind, nameEn: c.en, nameRu: c.ru, sfSymbol: c.sf, position: i })),
  );
  log(`categories: ${CATEGORIES.length}`);

  // --- apps, screenshots, version history ----------------------------------
  for (const [index, app] of APPS.entries()) {
    const id = appId(app.slug);
    const [tintLight, tintDark, bgColor] = app.colors;
    const palette = { tintLight, tintDark, bgColor };
    if (renderImages) {
      await ctx.storage.put(`static/icons/${app.slug}.png`, renderIcon(512, palette, app.shape));
      await ctx.storage.put(`static/icons/${app.slug}-57.png`, renderIcon(57, palette, app.shape));
      for (let n = 0; n < 3; n += 1) {
        await ctx.storage.put(
          `static/screens/${app.slug}-${n + 1}.png`,
          renderScreenshot(SCREENSHOT_SIZE.width, SCREENSHOT_SIZE.height, palette, app.shape, index + n),
        );
      }
    }
    const updatedDaysAgo = app.badge ? 2 + (index % 5) : 10 + index * 3;
    await createApp(ctx, {
      id,
      name: localizedName(app),
      subtitle: { en: app.subtitle[0], ru: app.subtitle[1] },
      description: { en: app.description[0], ru: app.description[1] },
      whats_new: { en: app.whatsNew[0], ru: app.whatsNew[1] },
      developer: app.developer,
      bundle_id: `com.example.${app.slug.replace(/_/g, '')}`,
      category_id: app.category,
      icon_url: `icons/${app.slug}.png`,
      icon_small_url: `icons/${app.slug}-57.png`,
      rating: app.rating,
      rating_count: app.ratingCount,
      version: app.version,
      size_bytes: Math.round(app.sizeMb * 1_000_000 + index * 37_421),
      min_os: index % 4 === 3 ? '16.0' : '15.0',
      tint_light: tintLight,
      tint_dark: tintDark,
      bg_color: bgColor,
      badge: app.badge ?? null,
      age_rating: app.age ?? '4+',
      languages: index % 3 === 0 ? ['EN', 'RU', 'DE'] : ['EN', 'RU'],
      screenshots: [1, 2, 3].map((n) => ({ url: `screens/${app.slug}-${n}.png`, ...SCREENSHOT_SIZE })),
      published: true,
      released_at: new Date(now.getTime() - (200 + index * 9) * DAY).toISOString(),
    });

    const history = [...(app.ipa ? [] : [app.version]), ...olderVersions(app.version)];
    await ctx.db.insert(appBuilds).values(
      history.map((version, i) => ({
        id: `bld_${app.slug}_${i}`,
        appId: id,
        version,
        build: buildNumber(version),
        bundleId: `com.example.${app.slug.replace(/_/g, '')}`,
        sizeBytes: Math.round(app.sizeMb * 1_000_000 * (1 - i * 0.04)),
        notesEn: i === 0 && !app.ipa ? app.whatsNew[0] : 'Bug fixes and performance improvements.',
        notesRu: i === 0 && !app.ipa ? app.whatsNew[1] : 'Исправления ошибок и улучшения производительности.',
        releasedAt: new Date(now.getTime() - (updatedDaysAgo + (app.ipa ? i + 1 : i) * 30) * DAY),
      })),
    );
  }
  log(`apps: ${APPS.length}${renderImages ? ' (icons and screenshots rendered)' : ''}`);

  // --- synthetic IPAs for the install path -----------------------------------
  const installable: string[] = [];
  await mkdir(ctx.config.uploadTmpDir, { recursive: true });
  for (const app of APPS.filter((a) => a.ipa)) {
    const tmp = path.join(ctx.config.uploadTmpDir, `${randomUUID()}.ipa`);
    try {
      await writeFile(
        tmp,
        buildSyntheticIpa({
          bundleId: `com.example.${app.slug.replace(/_/g, '')}`,
          version: app.version,
          build: buildNumber(app.version),
          name: localizedName(app).en,
          binaryPlist: app.ipa === 'binary',
          padBytes: 2_500_000,
        }),
      );
      await addBuildFromFile(
        ctx,
        appId(app.slug),
        tmp,
        { notes: app.whatsNew[0], notes_ru: app.whatsNew[1] },
        await digestFile(tmp),
      );
      installable.push(appId(app.slug));
    } finally {
      await rm(tmp, { force: true });
    }
  }
  log(`synthetic IPAs: ${installable.join(', ')}`);

  // --- storefront --------------------------------------------------------------
  let roomCount = 0;
  for (const [tab, seedRooms] of Object.entries(STOREFRONT) as [keyof typeof STOREFRONT, (typeof STOREFRONT)['today']][]) {
    const input: StorefrontInput = { rooms: [] };
    for (const room of seedRooms) {
      const hero = [];
      for (const [i, h] of (room.hero ?? []).entries()) {
        const app = APPS.find((a) => a.slug === h.slug)!;
        const gradient = h.gradient ?? [app.colors[0], app.colors[1]];
        const key = `hero/${room.id}-${i + 1}.png`;
        if (renderImages) await ctx.storage.put(`static/${key}`, renderHero(1600, 900, gradient, app.shape));
        hero.push({
          app_id: appId(h.slug),
          headline: { en: h.headline[0], ru: h.headline[1] },
          title: { en: h.title[0], ru: h.title[1] },
          image_url: key,
          gradient,
        });
      }
      input.rooms.push({
        id: room.id,
        style: room.style,
        title: room.title ? { en: room.title[0], ru: room.title[1] } : null,
        subtitle: room.subtitle ? { en: room.subtitle[0], ru: room.subtitle[1] } : null,
        app_ids: (room.apps ?? []).map(appId),
        hero,
        category_ids: room.categories ?? [],
      });
    }
    await replaceStorefront(ctx, tab, input);
    roomCount += input.rooms.length;
  }
  log(`rooms: ${roomCount}`);

  // --- singletons ---------------------------------------------------------------
  await ctx.db.update(storeState).set({ state: 'open', closed: null });
  await ctx.db.update(clientVersion).set({
    latestVersion: '1.0.0',
    latestBuild: 100,
    minSupportedBuild: 90,
    releaseNotesEn: 'First public release of iStore.',
    releaseNotesRu: 'Первый публичный релиз iStore.',
    updateUrl: null,
  });

  // --- activation codes and a ready-to-use dev token -------------------------------
  await insertActivationCode(ctx, DEMO_CODE, 'month', 30);
  const codes = await createActivationCodes(ctx, options.extraCodes ?? 5, 'month');

  const devAccountId = 'acc_dev';
  const devToken = randomToken();
  await ctx.db.insert(accounts).values({
    id: devAccountId,
    displayName: 'Dev device',
    planId: 'year',
    status: 'active',
    expiresAt: new Date(now.getTime() + 365 * DAY),
  });
  await ctx.db.insert(devices).values({
    id: 'dev_dev',
    accountId: devAccountId,
    installId: DEV_INSTALL_ID,
    model: 'iPhone16,2',
    osVersion: '18.1',
    locale: 'ru_RU',
  });
  await ctx.db.insert(tokens).values({ id: 'tok_dev', tokenHash: sha256Hex(devToken), accountId: devAccountId, deviceId: 'dev_dev' });

  const [state] = await ctx.db.select({ revision: storeState.catalogRevision }).from(storeState);
  return {
    apps: APPS.length,
    categories: CATEGORIES.length,
    rooms: roomCount,
    revision: state?.revision ?? 0,
    demoCode: DEMO_CODE,
    codes,
    devToken,
    devAccountId,
    installableApps: installable,
  };
}
