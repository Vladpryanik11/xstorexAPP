import { asc, eq, inArray } from 'drizzle-orm';
import type { AppContext } from '../../context.js';
import { categories, roomItems, rooms, type RoomItemRow, type RoomRow } from '../../db/schema.js';
import { pick, pickOpt, type Lang } from '../../lib/i18n.js';
import { loadPublished, toSummary, type AppSummary, type AppWithCategory } from './present.js';

export const TABS = ['today', 'games', 'apps'] as const;
export type Tab = (typeof TABS)[number];
export type RoomStyle = RoomRow['style'];

/** How many entries a room shows on the storefront (API.md, Room). */
export const ROOM_LIMITS: Record<RoomStyle, number> = {
  hero_carousel: 8,
  shelf_one: 12,
  shelf_two: 8,
  chips: 50,
};

export interface HeroCard {
  app: AppSummary;
  headline: string;
  title: string;
  image_url: string;
  gradient: [string, string];
}

export interface RoomView {
  id: string;
  style: RoomStyle;
  title: string | null;
  subtitle: string | null;
  items: AppSummary[];
  hero: HeroCard[];
  categories: { id: string; name: string; sf_symbol: string }[];
  has_more: boolean;
}

function heroCard(ctx: AppContext, item: RoomItemRow, row: AppWithCategory, lang: Lang): HeroCard {
  const summary = toSummary(ctx, row, lang);
  const g = item.gradient;
  return {
    app: summary,
    headline: pick(item.headlineEn ?? '', item.headlineRu, lang),
    title: pick(item.titleEn ?? summary.name, item.titleRu, lang),
    image_url: ctx.assetUrl(item.imageUrl ?? row.app.iconUrl),
    gradient: g && g.length >= 2 ? [g[0]!, g[1]!] : [row.app.tintLight, row.app.tintDark],
  };
}

/** Ordered, de-duplicated app ids a room points to (hero cards count as their apps). */
function roomAppIds(items: RoomItemRow[]): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const item of items) {
    if ((item.kind === 'app' || item.kind === 'hero') && item.appId && !seen.has(item.appId)) {
      seen.add(item.appId);
      out.push(item.appId);
    }
  }
  return out;
}

export async function buildRooms(ctx: AppContext, tab: Tab, lang: Lang): Promise<RoomView[]> {
  const roomRows = await ctx.db.select().from(rooms).where(eq(rooms.tab, tab)).orderBy(asc(rooms.position), asc(rooms.id));
  if (roomRows.length === 0) return [];
  const items = await ctx.db
    .select()
    .from(roomItems)
    .where(
      inArray(
        roomItems.roomId,
        roomRows.map((r) => r.id),
      ),
    )
    .orderBy(asc(roomItems.position), asc(roomItems.id));

  const apps = await loadPublished(
    ctx,
    items.flatMap((i) => (i.appId ? [i.appId] : [])),
  );
  const categoryIds = [...new Set(items.flatMap((i) => (i.categoryId ? [i.categoryId] : [])))];
  const cats = categoryIds.length
    ? new Map((await ctx.db.select().from(categories).where(inArray(categories.id, categoryIds))).map((c) => [c.id, c]))
    : new Map();

  const views: RoomView[] = [];
  for (const room of roomRows) {
    const own = items.filter((i) => i.roomId === room.id);
    const limit = ROOM_LIMITS[room.style];
    const view: RoomView = {
      id: room.id,
      style: room.style,
      title: pickOpt(room.titleEn, room.titleRu, lang),
      subtitle: pickOpt(room.subtitleEn, room.subtitleRu, lang),
      items: [],
      hero: [],
      categories: [],
      has_more: false,
    };

    if (room.style === 'chips') {
      view.categories = own
        .flatMap((i) => {
          const c = i.categoryId ? cats.get(i.categoryId) : undefined;
          return c ? [{ id: c.id, name: pick(c.nameEn, c.nameRu, lang), sf_symbol: c.sfSymbol }] : [];
        })
        .slice(0, limit);
      if (view.categories.length === 0) continue;
    } else if (room.style === 'hero_carousel') {
      const cards = own.flatMap((i) => {
        const row = i.kind === 'hero' && i.appId ? apps.get(i.appId) : undefined;
        return row ? [heroCard(ctx, i, row, lang)] : [];
      });
      view.hero = cards.slice(0, limit);
      // Also expose the apps as plain summaries for clients that render `items`.
      view.items = view.hero.map((c) => c.app);
      if (view.hero.length === 0) continue;
    } else {
      const available = roomAppIds(own).flatMap((id) => {
        const row = apps.get(id);
        return row ? [toSummary(ctx, row, lang)] : [];
      });
      view.items = available.slice(0, limit);
      view.has_more = available.length > limit;
      if (view.items.length === 0) continue;
    }
    views.push(view);
  }
  return views;
}

/** Full list of available apps for the "See all" screen. */
export async function roomApps(ctx: AppContext, roomId: string, lang: Lang): Promise<{ room: RoomRow; apps: AppSummary[] } | null> {
  const [room] = await ctx.db.select().from(rooms).where(eq(rooms.id, roomId));
  if (!room) return null;
  const items = await ctx.db
    .select()
    .from(roomItems)
    .where(eq(roomItems.roomId, roomId))
    .orderBy(asc(roomItems.position), asc(roomItems.id));
  const ids = roomAppIds(items);
  const published = await loadPublished(ctx, ids);
  return {
    room,
    apps: ids.flatMap((id) => {
      const row = published.get(id);
      return row ? [toSummary(ctx, row, lang)] : [];
    }),
  };
}
