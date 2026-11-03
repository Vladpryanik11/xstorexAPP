import { and, asc, eq, inArray, ne, sql } from 'drizzle-orm';
import type { AppContext } from '../../context.js';
import { apps, categories, screenshots, type AppRow, type CategoryRow } from '../../db/schema.js';
import { formatSize, languageName, pick, pickOpt, type Lang } from '../../lib/i18n.js';

export interface AppSummary {
  id: string;
  name: string;
  subtitle: string | null;
  icon_url: string;
  category: { id: string; name: string };
  rating: number | null;
  rating_count: number | null;
  version: string;
  size_bytes: number;
  min_os: string;
  tint_light: string;
  tint_dark: string;
  bg_color: string;
  badge: 'new' | 'updated' | null;
  availability: 'available' | 'unavailable';
}

export interface CatalogApp extends AppSummary {
  description: string;
  whats_new: string | null;
  developer: string;
  bundle_id: string | null;
  age_rating: string;
  languages: string[];
  released_at: string;
  updated_at: string;
  screenshots: { url: string; width: number; height: number }[];
  info: { label: string; value: string }[];
  similar: AppSummary[];
}

export interface AppWithCategory {
  app: AppRow;
  cat: CategoryRow;
}

export function iso(d: Date): string {
  return d.toISOString().replace(/\.\d{3}Z$/, 'Z');
}

export function categoryName(cat: CategoryRow, lang: Lang): string {
  return pick(cat.nameEn, cat.nameRu, lang);
}

export function toSummary(ctx: AppContext, { app, cat }: AppWithCategory, lang: Lang): AppSummary {
  return {
    id: app.id,
    name: pick(app.nameEn, app.nameRu, lang),
    subtitle: pickOpt(app.subtitleEn, app.subtitleRu, lang),
    icon_url: ctx.assetUrl(app.iconUrl),
    category: { id: cat.id, name: categoryName(cat, lang) },
    rating: app.rating,
    rating_count: app.ratingCount,
    version: app.version,
    size_bytes: app.sizeBytes,
    min_os: app.minOs,
    tint_light: app.tintLight,
    tint_dark: app.tintDark,
    bg_color: app.bgColor,
    badge: app.badge ?? null,
    availability: app.availability,
  };
}

/** Published apps with their categories, keyed by id. */
export async function loadPublished(ctx: AppContext, ids: readonly string[]): Promise<Map<string, AppWithCategory>> {
  const unique = [...new Set(ids)];
  if (unique.length === 0) return new Map();
  const rows = await ctx.db
    .select({ app: apps, cat: categories })
    .from(apps)
    .innerJoin(categories, eq(apps.categoryId, categories.id))
    .where(and(inArray(apps.id, unique), eq(apps.published, true)));
  return new Map(rows.map((r) => [r.app.id, r]));
}

export async function loadSummaries(ctx: AppContext, ids: readonly string[], lang: Lang): Promise<Map<string, AppSummary>> {
  const rows = await loadPublished(ctx, ids);
  return new Map([...rows].map(([id, row]) => [id, toSummary(ctx, row, lang)]));
}

const LABELS = {
  developer: { en: 'Developer', ru: 'Разработчик' },
  category: { en: 'Category', ru: 'Категория' },
  size: { en: 'Size', ru: 'Размер' },
  compatibility: { en: 'Compatibility', ru: 'Совместимость' },
  languages: { en: 'Languages', ru: 'Языки' },
  age: { en: 'Age Rating', ru: 'Возраст' },
  version: { en: 'Version', ru: 'Версия' },
} as const;

function buildInfo(row: AppWithCategory, lang: Lang): { label: string; value: string }[] {
  const { app, cat } = row;
  const info: { label: string; value: string }[] = [
    { label: LABELS.developer[lang], value: app.developer },
    { label: LABELS.category[lang], value: categoryName(cat, lang) },
    { label: LABELS.size[lang], value: formatSize(app.sizeBytes, lang) },
    {
      label: LABELS.compatibility[lang],
      value: lang === 'ru' ? `iOS ${app.minOs} или новее` : `Requires iOS ${app.minOs} or later`,
    },
  ];
  if (app.languages.length > 0) {
    info.push({ label: LABELS.languages[lang], value: app.languages.map((l) => languageName(l, lang)).join(', ') });
  }
  info.push({ label: LABELS.age[lang], value: app.ageRating });
  info.push({ label: LABELS.version[lang], value: app.version });
  return info;
}

/** Up to `limit` published apps: same category first, then same kind (apps/games). */
export async function similarApps(ctx: AppContext, row: AppWithCategory, lang: Lang, limit = 10): Promise<AppSummary[]> {
  const sameKindFirst = await ctx.db
    .select({ app: apps, cat: categories })
    .from(apps)
    .innerJoin(categories, eq(apps.categoryId, categories.id))
    .where(and(eq(apps.published, true), ne(apps.id, row.app.id), eq(categories.kind, row.cat.kind)))
    .orderBy(
      sql`case when ${apps.categoryId} = ${row.app.categoryId} then 0 else 1 end`,
      sql`${apps.rating} desc nulls last`,
      asc(apps.id),
    )
    .limit(limit);
  return sameKindFirst.map((r) => toSummary(ctx, r, lang));
}

export async function buildCatalogApp(ctx: AppContext, id: string, lang: Lang): Promise<CatalogApp | null> {
  const row = (await loadPublished(ctx, [id])).get(id);
  if (!row) return null;
  const shots = await ctx.db
    .select()
    .from(screenshots)
    .where(eq(screenshots.appId, id))
    .orderBy(asc(screenshots.position), asc(screenshots.id));
  const { app } = row;
  return {
    ...toSummary(ctx, row, lang),
    description: pick(app.descriptionEn, app.descriptionRu, lang),
    whats_new: pickOpt(app.whatsNewEn, app.whatsNewRu, lang),
    developer: app.developer,
    bundle_id: app.bundleId,
    age_rating: app.ageRating,
    languages: app.languages,
    released_at: iso(app.releasedAt),
    updated_at: iso(app.updatedAt),
    screenshots: shots.map((s) => ({ url: ctx.assetUrl(s.url), width: s.width, height: s.height })),
    info: buildInfo(row, lang),
    similar: await similarApps(ctx, row, lang),
  };
}

