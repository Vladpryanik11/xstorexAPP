import { and, eq, like } from 'drizzle-orm';
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import type { AppContext } from '../../context.js';
import { apps, categories, searchRequests } from '../../db/schema.js';
import { pick, resolveLang, type Lang } from '../../lib/i18n.js';
import { decodeCursor, encodeCursor, pageQuerySchema } from '../../lib/pagination.js';
import { parseInput } from '../../lib/validation.js';
import { authOf, type Guard } from '../auth/guard.js';
import { toSummary, type AppWithCategory } from '../catalog/present.js';
import { getRevision } from '../catalog/revision.js';
import { escapeLike, foldText, switchLayout } from './text.js';

const MAX_MATCHES = 1000;

const searchQuery = pageQuerySchema.extend({ q: z.string().trim().min(1).max(100) });
const hintsQuery = z.object({ q: z.string().trim().max(100).optional().default('') });
const requestBody = z.object({
  query: z.string().trim().min(1).max(200),
  note: z.string().trim().max(1000).nullable().optional(),
});

async function findMatches(ctx: AppContext, folded: string): Promise<AppWithCategory[]> {
  return ctx.db
    .select({ app: apps, cat: categories })
    .from(apps)
    .innerJoin(categories, eq(apps.categoryId, categories.id))
    .where(and(eq(apps.published, true), like(apps.searchText, `%${escapeLike(folded)}%`)))
    .limit(MAX_MATCHES);
}

function startsWord(text: string, q: string): boolean {
  return text.startsWith(q) || text.includes(` ${q}`) || text.includes(`-${q}`);
}

/** Lower is better: exact name, name prefix, word prefix, name substring, other fields. */
function score(row: AppWithCategory, q: string, lang: Lang): number {
  const names = [row.app.nameEn, row.app.nameRu].filter((n): n is string => Boolean(n)).map(foldText);
  const local = foldText(pick(row.app.nameEn, row.app.nameRu, lang));
  if (names.includes(q)) return 0;
  if (local.startsWith(q) || names.some((n) => n.startsWith(q))) return 1;
  if (names.some((n) => startsWord(n, q))) return 2;
  if (names.some((n) => n.includes(q))) return 3;
  return 4;
}

function rank(rows: AppWithCategory[], q: string, lang: Lang): AppWithCategory[] {
  return rows
    .map((row) => ({ row, s: score(row, q, lang) }))
    .sort(
      (a, b) =>
        a.s - b.s ||
        (b.row.app.rating ?? -1) - (a.row.app.rating ?? -1) ||
        a.row.app.nameEn.localeCompare(b.row.app.nameEn) ||
        a.row.app.id.localeCompare(b.row.app.id),
    )
    .map((x) => x.row);
}

export async function searchRoutes(
  app: FastifyInstance,
  opts: { ctx: AppContext; guards: { requireActive: Guard; requireAuth: Guard } },
) {
  const { ctx, guards } = opts;

  app.get('/search', { onRequest: guards.requireActive }, async (req, reply) => {
    const query = parseInput(searchQuery, req.query, 'query');
    const offset = decodeCursor(query.cursor);
    const lang = resolveLang(req.headers['accept-language']);
    let folded = foldText(query.q);
    let corrected: string | null = null;
    let rows = await findMatches(ctx, folded);
    if (rows.length === 0) {
      const alt = foldText(switchLayout(query.q));
      if (alt !== folded) {
        const altRows = await findMatches(ctx, alt);
        if (altRows.length > 0) {
          rows = altRows;
          folded = alt;
          corrected = alt;
        }
      }
    }
    const ranked = rank(rows, folded, lang);
    const slice = ranked.slice(offset, offset + query.limit);
    void reply.header('x-catalog-revision', String(await getRevision(ctx.db)));
    return {
      items: slice.map((r) => toSummary(ctx, r, lang)),
      next_cursor: offset + query.limit < ranked.length ? encodeCursor(offset + query.limit) : null,
      corrected_query: corrected,
    };
  });

  app.get('/search/hints', { onRequest: guards.requireActive }, async (req) => {
    const { q } = parseInput(hintsQuery, req.query, 'query');
    const lang = resolveLang(req.headers['accept-language']);
    const folded = foldText(q);
    if (!folded) return { hints: [] };
    const rows = rank(await findMatches(ctx, folded), folded, lang);
    const hints: { text: string; app_id: string | null }[] = [];
    const seen = new Set<string>();
    const push = (text: string, appId: string | null) => {
      if (hints.length >= 8 || seen.has(text)) return;
      seen.add(text);
      hints.push({ text, app_id: appId });
    };
    for (const r of rows) {
      const names = [pick(r.app.nameEn, r.app.nameRu, lang), r.app.nameEn].map(foldText);
      const name = names.find((n) => startsWord(n, folded));
      if (name) push(name, r.app.id);
    }
    for (const r of rows) {
      const dev = foldText(r.app.developer);
      if (startsWord(dev, folded)) push(dev, null);
    }
    return { hints };
  });

  app.post('/search/requests', { onRequest: guards.requireAuth }, async (req, reply) => {
    const auth = authOf(req);
    const body = parseInput(requestBody, req.body, 'body');
    await ctx.db.insert(searchRequests).values({
      accountId: auth.account.id,
      deviceId: auth.device.id,
      query: body.query,
      note: body.note ?? null,
    });
    return reply.code(202).send();
  });
}
