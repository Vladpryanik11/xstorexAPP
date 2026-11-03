import { asc, eq } from 'drizzle-orm';
import { z } from 'zod';
import type { AppContext } from '../../context.js';
import { apps, categories, screenshots, type AppRow } from '../../db/schema.js';
import { newId } from '../../lib/crypto.js';
import { invalidRequest, notFound } from '../../lib/errors.js';
import { appIdSchema, hexColor, localizedInput, toLocalized, toLocalizedOpt } from '../../lib/validation.js';
import { isValidKey } from '../../storage/blob-storage.js';
import { iso } from '../catalog/present.js';
import { recordChanges } from '../catalog/revision.js';
import { appSearchText } from '../search/text.js';

/** Absolute http(s) URL or a storage key under `static/` (e.g. `icons/app_x.png`). */
export const assetRef = z
  .string()
  .trim()
  .min(1)
  .max(2048)
  .refine((v) => /^https?:\/\/[^\s]+$/i.test(v) || isValidKey(v), 'expected http(s) URL or storage key');

const bundleIdSchema = z
  .string()
  .max(155)
  .regex(/^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$/, 'expected reverse-DNS bundle id');

const versionSchema = z.string().regex(/^[0-9A-Za-z.\-]{1,32}$/, 'expected version like 1.2.3');

export const appFieldsSchema = z
  .object({
    name: localizedInput(100),
    subtitle: localizedInput(200).nullable().optional(),
    description: localizedInput(10_000).optional(),
    whats_new: localizedInput(5_000).nullable().optional(),
    developer: z.string().trim().min(1).max(100),
    bundle_id: bundleIdSchema.nullable().optional(),
    category_id: z.string().min(1).max(64),
    icon_url: assetRef,
    icon_small_url: assetRef.nullable().optional(),
    rating: z.number().min(0).max(5).nullable().optional(),
    rating_count: z.number().int().min(0).nullable().optional(),
    version: versionSchema.optional(),
    size_bytes: z.number().int().min(0).max(Number.MAX_SAFE_INTEGER).optional(),
    min_os: z
      .string()
      .regex(/^\d{1,2}(\.\d{1,2}){0,2}$/)
      .optional(),
    tint_light: hexColor,
    tint_dark: hexColor,
    bg_color: hexColor,
    badge: z.enum(['new', 'updated']).nullable().optional(),
    availability: z.enum(['available', 'unavailable']).optional(),
    age_rating: z.string().regex(/^\d{1,2}\+$/).optional(),
    languages: z
      .array(z.string().regex(/^[A-Za-z]{2}$/))
      .max(60)
      .optional(),
    screenshots: z
      .array(
        z.object({ url: assetRef, width: z.number().int().min(1).max(10_000), height: z.number().int().min(1).max(10_000) }),
      )
      .max(20)
      .optional(),
    published: z.boolean().optional(),
    released_at: z.iso.datetime({ offset: true }).optional(),
  })
  .strict();

export const appCreateSchema = appFieldsSchema.extend({ id: appIdSchema.optional() }).strict();
export const appPatchSchema = appFieldsSchema.partial().strict();

export type AppCreateInput = z.infer<typeof appCreateSchema>;
export type AppPatchInput = z.infer<typeof appPatchSchema>;

function columns(input: AppPatchInput): Partial<typeof apps.$inferInsert> {
  const out: Partial<typeof apps.$inferInsert> = {};
  if (input.name !== undefined) {
    const n = toLocalized(input.name);
    out.nameEn = n.en;
    out.nameRu = n.ru;
  }
  if (input.subtitle !== undefined) {
    const s = toLocalizedOpt(input.subtitle);
    out.subtitleEn = s.en;
    out.subtitleRu = s.ru;
  }
  if (input.description !== undefined) {
    const d = toLocalized(input.description);
    out.descriptionEn = d.en;
    out.descriptionRu = d.ru;
  }
  if (input.whats_new !== undefined) {
    const w = toLocalizedOpt(input.whats_new);
    out.whatsNewEn = w.en;
    out.whatsNewRu = w.ru;
  }
  if (input.developer !== undefined) out.developer = input.developer;
  if (input.bundle_id !== undefined) out.bundleId = input.bundle_id;
  if (input.category_id !== undefined) out.categoryId = input.category_id;
  if (input.icon_url !== undefined) out.iconUrl = input.icon_url;
  if (input.icon_small_url !== undefined) out.iconSmallUrl = input.icon_small_url;
  if (input.rating !== undefined) out.rating = input.rating;
  if (input.rating_count !== undefined) out.ratingCount = input.rating_count;
  if (input.version !== undefined) out.version = input.version;
  if (input.size_bytes !== undefined) out.sizeBytes = input.size_bytes;
  if (input.min_os !== undefined) out.minOs = input.min_os;
  if (input.tint_light !== undefined) out.tintLight = input.tint_light.toUpperCase();
  if (input.tint_dark !== undefined) out.tintDark = input.tint_dark.toUpperCase();
  if (input.bg_color !== undefined) out.bgColor = input.bg_color.toUpperCase();
  if (input.badge !== undefined) out.badge = input.badge;
  if (input.availability !== undefined) out.availability = input.availability;
  if (input.age_rating !== undefined) out.ageRating = input.age_rating;
  if (input.languages !== undefined) out.languages = [...new Set(input.languages.map((l) => l.toUpperCase()))];
  if (input.published !== undefined) out.published = input.published;
  if (input.released_at !== undefined) out.releasedAt = new Date(input.released_at);
  return out;
}

async function assertCategory(ctx: AppContext, id: string | undefined): Promise<void> {
  if (id === undefined) return;
  const [cat] = await ctx.db.select({ id: categories.id }).from(categories).where(eq(categories.id, id));
  if (!cat) throw invalidRequest(`unknown category_id "${id}"`);
}

async function replaceScreenshots(ctx: AppContext, appId: string, list: AppPatchInput['screenshots']): Promise<void> {
  if (list === undefined) return;
  await ctx.db.delete(screenshots).where(eq(screenshots.appId, appId));
  if (list.length > 0) {
    await ctx.db.insert(screenshots).values(list.map((s, i) => ({ appId, position: i, url: s.url, width: s.width, height: s.height })));
  }
}

export async function createApp(ctx: AppContext, input: AppCreateInput): Promise<AppRow> {
  await assertCategory(ctx, input.category_id);
  const id = input.id ?? newId('app', 10);
  const [existing] = await ctx.db.select({ id: apps.id }).from(apps).where(eq(apps.id, id));
  if (existing) throw invalidRequest(`app "${id}" already exists`);
  const cols = columns(input);
  const now = ctx.now();
  const row = await ctx.db.transaction(async (tx) => {
    const txCtx = { ...ctx, db: tx };
    const [created] = await tx
      .insert(apps)
      .values({
        ...(cols as typeof apps.$inferInsert),
        id,
        searchText: appSearchText({
          nameEn: cols.nameEn!,
          nameRu: cols.nameRu,
          subtitleEn: cols.subtitleEn,
          subtitleRu: cols.subtitleRu,
          developer: cols.developer!,
        }),
        createdAt: now,
        updatedAt: now,
        releasedAt: cols.releasedAt ?? now,
      })
      .returning();
    if (!created) throw new Error('insert returned nothing');
    await replaceScreenshots(txCtx, id, input.screenshots);
    await recordChanges(tx, [{ kind: created.published ? 'app_upsert' : 'app_removed', appId: id }], ctx.config.catalogJournalLimit);
    return created;
  });
  await ctx.bus.notify();
  return row;
}

export async function updateApp(ctx: AppContext, id: string, patch: AppPatchInput): Promise<AppRow> {
  await assertCategory(ctx, patch.category_id);
  const row = await ctx.db.transaction(async (tx) => {
    const [current] = await tx.select().from(apps).where(eq(apps.id, id)).for('update');
    if (!current) throw notFound();
    const merged = { ...current, ...columns(patch) };
    const [updated] = await tx
      .update(apps)
      .set({ ...columns(patch), searchText: appSearchText(merged), updatedAt: ctx.now() })
      .where(eq(apps.id, id))
      .returning();
    if (!updated) throw notFound();
    await replaceScreenshots({ ...ctx, db: tx }, id, patch.screenshots);
    await recordChanges(tx, [{ kind: updated.published ? 'app_upsert' : 'app_removed', appId: id }], ctx.config.catalogJournalLimit);
    return updated;
  });
  await ctx.bus.notify();
  return row;
}

/** DELETE = unpublish; data and builds stay for history. */
export async function unpublishApp(ctx: AppContext, id: string): Promise<void> {
  await updateApp(ctx, id, { published: false });
}

export async function adminAppView(ctx: AppContext, row: AppRow) {
  const shots = await ctx.db.select().from(screenshots).where(eq(screenshots.appId, row.id)).orderBy(asc(screenshots.position));
  return {
    id: row.id,
    published: row.published,
    availability: row.availability,
    name: { en: row.nameEn, ru: row.nameRu },
    subtitle: { en: row.subtitleEn, ru: row.subtitleRu },
    description: { en: row.descriptionEn, ru: row.descriptionRu },
    whats_new: { en: row.whatsNewEn, ru: row.whatsNewRu },
    developer: row.developer,
    bundle_id: row.bundleId,
    category_id: row.categoryId,
    icon_url: row.iconUrl,
    icon_small_url: row.iconSmallUrl,
    rating: row.rating,
    rating_count: row.ratingCount,
    version: row.version,
    size_bytes: row.sizeBytes,
    min_os: row.minOs,
    tint_light: row.tintLight,
    tint_dark: row.tintDark,
    bg_color: row.bgColor,
    badge: row.badge,
    age_rating: row.ageRating,
    languages: row.languages,
    screenshots: shots.map((s) => ({ url: s.url, width: s.width, height: s.height })),
    released_at: iso(row.releasedAt),
    created_at: iso(row.createdAt),
    updated_at: iso(row.updatedAt),
  };
}
