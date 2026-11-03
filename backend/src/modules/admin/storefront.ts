import { and, eq, inArray, ne } from 'drizzle-orm';
import { z } from 'zod';
import type { AppContext } from '../../context.js';
import { apps, categories, roomItems, rooms } from '../../db/schema.js';
import { conflict, invalidRequest } from '../../lib/errors.js';
import { appIdSchema, hexColor, localizedInput, toLocalized, toLocalizedOpt } from '../../lib/validation.js';
import { recordChanges } from '../catalog/revision.js';
import type { Tab } from '../catalog/storefront.js';
import { assetRef } from './apps.js';

const heroSchema = z
  .object({
    app_id: appIdSchema,
    headline: localizedInput(60),
    title: localizedInput(120),
    image_url: assetRef.nullable().optional(),
    gradient: z.array(hexColor).length(2).nullable().optional(),
  })
  .strict();

const roomSchema = z
  .object({
    id: z.string().regex(/^room_[a-z0-9_]{1,60}$/, 'expected room_<slug>'),
    style: z.enum(['hero_carousel', 'shelf_one', 'shelf_two', 'chips']),
    title: localizedInput(100).nullable().optional(),
    subtitle: localizedInput(200).nullable().optional(),
    app_ids: z.array(appIdSchema).max(200).optional().default([]),
    hero: z.array(heroSchema).max(8).optional().default([]),
    category_ids: z.array(z.string().min(1).max(64)).max(50).optional().default([]),
  })
  .strict()
  .superRefine((room, issue) => {
    if (room.style === 'hero_carousel' && room.hero.length === 0) {
      issue.addIssue({ code: 'custom', message: 'hero_carousel needs hero[]', path: ['hero'] });
    }
    if ((room.style === 'shelf_one' || room.style === 'shelf_two') && room.app_ids.length === 0) {
      issue.addIssue({ code: 'custom', message: `${room.style} needs app_ids[]`, path: ['app_ids'] });
    }
    if (room.style === 'chips' && room.category_ids.length === 0) {
      issue.addIssue({ code: 'custom', message: 'chips needs category_ids[]', path: ['category_ids'] });
    }
  });

export const storefrontSchema = z.object({ rooms: z.array(roomSchema).max(50) }).strict();
export type StorefrontInput = z.infer<typeof storefrontSchema>;

/** Replaces all rooms of a tab atomically and bumps the catalog revision. */
export async function replaceStorefront(ctx: AppContext, tab: Tab, input: StorefrontInput): Promise<number> {
  const ids = input.rooms.map((r) => r.id);
  if (new Set(ids).size !== ids.length) throw invalidRequest('room ids must be unique');

  const appIds = [...new Set(input.rooms.flatMap((r) => [...r.app_ids, ...r.hero.map((h) => h.app_id)]))];
  const categoryIds = [...new Set(input.rooms.flatMap((r) => r.category_ids))];
  if (appIds.length) {
    const found = new Set((await ctx.db.select({ id: apps.id }).from(apps).where(inArray(apps.id, appIds))).map((r) => r.id));
    const missing = appIds.filter((id) => !found.has(id));
    if (missing.length) throw invalidRequest(`unknown app ids: ${missing.slice(0, 5).join(', ')}`);
  }
  if (categoryIds.length) {
    const found = new Set(
      (await ctx.db.select({ id: categories.id }).from(categories).where(inArray(categories.id, categoryIds))).map((r) => r.id),
    );
    const missing = categoryIds.filter((id) => !found.has(id));
    if (missing.length) throw invalidRequest(`unknown category ids: ${missing.slice(0, 5).join(', ')}`);
  }

  const revision = await ctx.db.transaction(async (tx) => {
    if (ids.length) {
      const taken = await tx
        .select({ id: rooms.id, tab: rooms.tab })
        .from(rooms)
        .where(and(inArray(rooms.id, ids), ne(rooms.tab, tab)));
      if (taken.length) {
        throw conflict('room_id_taken', {
          en: `Room ${taken[0]!.id} belongs to tab ${taken[0]!.tab}`,
          ru: `Комната ${taken[0]!.id} принадлежит вкладке ${taken[0]!.tab}`,
        });
      }
    }
    await tx.delete(rooms).where(eq(rooms.tab, tab));
    const now = ctx.now();
    for (const [position, room] of input.rooms.entries()) {
      const title = toLocalizedOpt(room.title);
      const subtitle = toLocalizedOpt(room.subtitle);
      await tx.insert(rooms).values({
        id: room.id,
        tab,
        position,
        style: room.style,
        titleEn: title.en,
        titleRu: title.ru,
        subtitleEn: subtitle.en,
        subtitleRu: subtitle.ru,
        createdAt: now,
        updatedAt: now,
      });
      const items: (typeof roomItems.$inferInsert)[] = [];
      if (room.style === 'hero_carousel') {
        room.hero.forEach((h, i) => {
          const headline = toLocalized(h.headline);
          const heroTitle = toLocalized(h.title);
          items.push({
            roomId: room.id,
            position: i,
            kind: 'hero',
            appId: h.app_id,
            headlineEn: headline.en,
            headlineRu: headline.ru,
            titleEn: heroTitle.en,
            titleRu: heroTitle.ru,
            imageUrl: h.image_url ?? null,
            gradient: h.gradient ? h.gradient.map((c) => c.toUpperCase()) : null,
          });
        });
      } else if (room.style === 'chips') {
        room.category_ids.forEach((categoryId, i) => items.push({ roomId: room.id, position: i, kind: 'category', categoryId }));
      } else {
        room.app_ids.forEach((appId, i) => items.push({ roomId: room.id, position: i, kind: 'app', appId }));
      }
      if (items.length) await tx.insert(roomItems).values(items);
    }
    return recordChanges(tx, [{ kind: 'rooms_changed', appId: null }], ctx.config.catalogJournalLimit);
  });
  await ctx.bus.notify();
  return revision;
}
