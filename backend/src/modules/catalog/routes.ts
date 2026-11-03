import type { ServerResponse } from 'node:http';
import { and, asc, desc, eq, sql } from 'drizzle-orm';
import type { FastifyInstance, FastifyRequest } from 'fastify';
import { z } from 'zod';
import type { AppContext } from '../../context.js';
import { appBuilds, apps, categories } from '../../db/schema.js';
import { notFound } from '../../lib/errors.js';
import { sendJsonWithEtag } from '../../lib/etag.js';
import { pick, pickOpt, resolveLang } from '../../lib/i18n.js';
import { decodeCursor, pageQuerySchema, toPage } from '../../lib/pagination.js';
import { parseInput } from '../../lib/validation.js';
import type { Guard } from '../auth/guard.js';
import { presentChanges } from './changes.js';
import { buildCatalogApp, iso, loadPublished, toSummary } from './present.js';
import { getRevisionInfo, listChanges, type RevisionInfo } from './revision.js';
import { registerCatalogStream } from './sse.js';
import { buildRooms, roomApps, TABS } from './storefront.js';

const idParam = z.object({ id: z.string().min(1).max(80) });
const roomParam = z.object({ room_id: z.string().min(1).max(80) });
const changesQuery = z.object({
  since: z.coerce.number().int().min(0),
  limit: z.coerce.number().int().min(1).max(500).default(100),
});

declare module 'fastify' {
  interface FastifyRequest {
    catalogRevision: RevisionInfo | null;
  }
}

/** Ревизия, прочитанная хуком в начале запроса. */
function revisionOf(req: FastifyRequest): RevisionInfo {
  if (!req.catalogRevision) throw new Error('catalog revision hook did not run');
  return req.catalogRevision;
}

export async function catalogRoutes(
  app: FastifyInstance,
  opts: { ctx: AppContext; guards: { requireActive: Guard }; sseConnections: Set<ServerResponse> },
) {
  const { ctx, guards } = opts;
  const guard = guards.requireActive;

  // Все ответы каталога несут текущую ревизию; обработчики берут её отсюда, а не читают заново.
  app.decorateRequest('catalogRevision', null);
  app.addHook('preHandler', async (req, reply) => {
    req.catalogRevision = await getRevisionInfo(ctx.db);
    void reply.header('x-catalog-revision', String(req.catalogRevision.revision));
  });

  app.get('/groupings', { onRequest: guard }, async (req, reply) => {
    const { tab } = parseInput(z.object({ tab: z.enum(TABS) }), req.query, 'query');
    const lang = resolveLang(req.headers['accept-language']);
    const { revision } = revisionOf(req);
    const rooms = await buildRooms(ctx, tab, lang);
    return sendJsonWithEtag(req, reply, { tab, revision, rooms });
  });

  app.get('/groupings/:room_id', { onRequest: guard }, async (req, reply) => {
    const { room_id } = parseInput(roomParam, req.params, 'params');
    const page = parseInput(pageQuerySchema, req.query, 'query');
    const offset = decodeCursor(page.cursor);
    const lang = resolveLang(req.headers['accept-language']);
    const found = await roomApps(ctx, room_id, lang);
    if (!found) throw notFound();
    const { items, next_cursor } = toPage(found.apps.slice(offset, offset + page.limit + 1), offset, page.limit);
    return sendJsonWithEtag(req, reply, {
      room: {
        id: found.room.id,
        title: pickOpt(found.room.titleEn, found.room.titleRu, lang),
        style: found.room.style,
      },
      items,
      next_cursor,
    });
  });

  app.get('/catalog/apps/:id', { onRequest: guard }, async (req, reply) => {
    const { id } = parseInput(idParam, req.params, 'params');
    const body = await buildCatalogApp(ctx, id, resolveLang(req.headers['accept-language']));
    if (!body) throw notFound();
    return sendJsonWithEtag(req, reply, body);
  });

  app.get('/catalog/apps/:id/versions', { onRequest: guard }, async (req, reply) => {
    const { id } = parseInput(idParam, req.params, 'params');
    const page = parseInput(pageQuerySchema, req.query, 'query');
    const offset = decodeCursor(page.cursor);
    const lang = resolveLang(req.headers['accept-language']);
    if (!(await loadPublished(ctx, [id])).has(id)) throw notFound();
    const rows = await ctx.db
      .select()
      .from(appBuilds)
      .where(eq(appBuilds.appId, id))
      .orderBy(desc(appBuilds.releasedAt), desc(appBuilds.createdAt), desc(appBuilds.id))
      .offset(offset)
      .limit(page.limit + 1);
    const { items, next_cursor } = toPage(rows, offset, page.limit);
    return sendJsonWithEtag(req, reply, {
      items: items.map((b) => ({
        version: b.version,
        build: b.build,
        released_at: iso(b.releasedAt),
        notes: pickOpt(b.notesEn, b.notesRu, lang),
        size_bytes: b.sizeBytes,
      })),
      next_cursor,
    });
  });

  app.get('/catalog/categories/:id', { onRequest: guard }, async (req, reply) => {
    const { id } = parseInput(idParam, req.params, 'params');
    const page = parseInput(pageQuerySchema, req.query, 'query');
    const offset = decodeCursor(page.cursor);
    const lang = resolveLang(req.headers['accept-language']);
    const [cat] = await ctx.db.select().from(categories).where(eq(categories.id, id));
    if (!cat) throw notFound();
    const rows = await ctx.db
      .select({ app: apps, cat: categories })
      .from(apps)
      .innerJoin(categories, eq(apps.categoryId, categories.id))
      .where(and(eq(apps.categoryId, id), eq(apps.published, true)))
      .orderBy(sql`${apps.rating} desc nulls last`, asc(apps.nameEn), asc(apps.id))
      .offset(offset)
      .limit(page.limit + 1);
    const { items, next_cursor } = toPage(rows, offset, page.limit);
    return sendJsonWithEtag(req, reply, {
      category: { id: cat.id, name: pick(cat.nameEn, cat.nameRu, lang), sf_symbol: cat.sfSymbol },
      items: items.map((r) => toSummary(ctx, r, lang)),
      next_cursor,
    });
  });

  app.get('/catalog/changes', { onRequest: guard }, async (req, reply) => {
    const q = parseInput(changesQuery, req.query, 'query');
    const lang = resolveLang(req.headers['accept-language']);
    const info = revisionOf(req);
    void reply.header('cache-control', 'no-cache');
    if (q.since < info.floor || q.since > info.revision) {
      return { revision: info.revision, changes: [], has_more: false, reset: true };
    }
    const rows = await listChanges(ctx.db, q.since, info.revision, q.limit + 1);
    const hasMore = rows.length > q.limit;
    return {
      revision: info.revision,
      changes: await presentChanges(ctx, hasMore ? rows.slice(0, q.limit) : rows, lang),
      has_more: hasMore,
      reset: false,
    };
  });

  // Поток читает ревизию сам, уже после подписки на шину.
  registerCatalogStream(app, ctx, guard, opts.sseConnections);
}
