import { and, asc, count, desc, eq } from 'drizzle-orm';
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import type { AppContext } from '../../context.js';
import { apps, categories, follows } from '../../db/schema.js';
import { conflict, notFound } from '../../lib/errors.js';
import { resolveLang } from '../../lib/i18n.js';
import { decodeCursor, pageQuerySchema, toPage } from '../../lib/pagination.js';
import { parseInput } from '../../lib/validation.js';
import { authOf, type Guard } from '../auth/guard.js';
import { iso, loadPublished, toSummary } from '../catalog/present.js';

const idParam = z.object({ id: z.string().min(1).max(80) });
const muteSchema = z.object({ muted: z.boolean() });

async function requirePublished(ctx: AppContext, id: string): Promise<void> {
  if (!(await loadPublished(ctx, [id])).has(id)) throw notFound();
}

async function followStatus(ctx: AppContext, accountId: string, appId: string) {
  const [own] = await ctx.db
    .select({ muted: follows.muted })
    .from(follows)
    .where(and(eq(follows.accountId, accountId), eq(follows.appId, appId)));
  const [total] = await ctx.db.select({ n: count() }).from(follows).where(eq(follows.appId, appId));
  return {
    app_id: appId,
    following: own !== undefined,
    muted: own?.muted ?? false,
    follower_count: total?.n ?? 0,
  };
}

/** Подписки аккаунта на приложения. Как и каталог, доступны только при активной подписке. */
export async function followsRoutes(app: FastifyInstance, opts: { ctx: AppContext; guards: { requireActive: Guard } }) {
  const { ctx } = opts;
  const guard = opts.guards.requireActive;

  app.get('/apps/:id/follow', { onRequest: guard }, async (req) => {
    const { id } = parseInput(idParam, req.params, 'params');
    await requirePublished(ctx, id);
    return followStatus(ctx, authOf(req).account.id, id);
  });

  app.post('/apps/:id/follow', { onRequest: guard }, async (req) => {
    const { id } = parseInput(idParam, req.params, 'params');
    const accountId = authOf(req).account.id;
    await requirePublished(ctx, id);
    await ctx.db.insert(follows).values({ accountId, appId: id }).onConflictDoNothing();
    return followStatus(ctx, accountId, id);
  });

  app.delete('/apps/:id/follow', { onRequest: guard }, async (req) => {
    const { id } = parseInput(idParam, req.params, 'params');
    const accountId = authOf(req).account.id;
    await requirePublished(ctx, id);
    await ctx.db.delete(follows).where(and(eq(follows.accountId, accountId), eq(follows.appId, id)));
    return followStatus(ctx, accountId, id);
  });

  app.put('/apps/:id/follow/mute', { onRequest: guard }, async (req) => {
    const { id } = parseInput(idParam, req.params, 'params');
    const { muted } = parseInput(muteSchema, req.body, 'body');
    const accountId = authOf(req).account.id;
    await requirePublished(ctx, id);
    const updated = await ctx.db
      .update(follows)
      .set({ muted })
      .where(and(eq(follows.accountId, accountId), eq(follows.appId, id)))
      .returning({ appId: follows.appId });
    if (updated.length === 0) {
      throw conflict('not_following', {
        en: 'Follow the app first.',
        ru: 'Сначала подпишитесь на приложение.',
      });
    }
    return followStatus(ctx, accountId, id);
  });

  app.get('/client/follows', { onRequest: guard }, async (req) => {
    const page = parseInput(pageQuerySchema, req.query, 'query');
    const offset = decodeCursor(page.cursor);
    const lang = resolveLang(req.headers['accept-language']);
    const rows = await ctx.db
      .select({ app: apps, cat: categories, muted: follows.muted, followedAt: follows.createdAt })
      .from(follows)
      .innerJoin(apps, eq(follows.appId, apps.id))
      .innerJoin(categories, eq(apps.categoryId, categories.id))
      .where(and(eq(follows.accountId, authOf(req).account.id), eq(apps.published, true)))
      .orderBy(desc(follows.createdAt), asc(follows.appId))
      .offset(offset)
      .limit(page.limit + 1);
    const { items, next_cursor } = toPage(rows, offset, page.limit);
    return {
      items: items.map((r) => ({ app: toSummary(ctx, r, lang), muted: r.muted, followed_at: iso(r.followedAt) })),
      next_cursor,
    };
  });
}
