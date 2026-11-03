import { and, eq, ne } from 'drizzle-orm';
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import type { AppContext } from '../../context.js';
import { clientEvents, clientVersion, pushTokens, storeState, type LocalizedText } from '../../db/schema.js';
import { invalidRequest } from '../../lib/errors.js';
import { pick, pickOpt, resolveLang, type Lang } from '../../lib/i18n.js';
import { parseInput } from '../../lib/validation.js';
import { accountView } from '../auth/account.js';
import { authOf, type Guard } from '../auth/guard.js';
import { iso } from '../catalog/present.js';

const MAX_PROPS_BYTES = 8 * 1024;

const eventsSchema = z.object({
  events: z
    .array(
      z.object({
        kind: z.enum(['install.step', 'net.error', 'app.launch']),
        ts: z.iso.datetime({ offset: true }),
        props: z
          .record(z.string().max(64), z.unknown())
          .optional()
          .default({})
          .refine((p) => JSON.stringify(p).length <= MAX_PROPS_BYTES, 'props are too large'),
      }),
    )
    .min(1)
    .max(100),
});

const pushSchema = z.object({
  apns_token: z.string().regex(/^[0-9a-fA-F]{32,200}$/, 'expected hex token'),
  apns_env: z.enum(['sandbox', 'production']),
  locale: z.string().trim().max(35).nullable().optional(),
  tz_offset_minutes: z.number().int().min(-900).max(900).nullable().optional(),
});

const versionQuery = z.object({ build: z.coerce.number().int().min(0).max(2_147_483_647).optional() });

const DEFAULT_CLOSED = {
  title: { en: 'We are closed for now', ru: 'Сейчас мы закрыты' },
  message: { en: 'The store will be back soon.', ru: 'Магазин скоро снова откроется.' },
};

function loc(text: LocalizedText | undefined, fallback: { en: string; ru: string }, lang: Lang): string {
  if (!text) return fallback[lang];
  return pick(text.en, text.ru, lang);
}

export async function storeStateView(ctx: AppContext, lang: Lang) {
  const [row] = await ctx.db.select().from(storeState).where(eq(storeState.id, 1));
  if (!row || row.state === 'open') return { state: 'open' as const, closed: null };
  const c = row.closed;
  return {
    state: 'closed' as const,
    closed: {
      title: loc(c?.title, DEFAULT_CLOSED.title, lang),
      message: loc(c?.message, DEFAULT_CLOSED.message, lang),
      reopens_at: c?.reopens_at ?? null,
      links: (c?.links ?? []).map((l) => ({ title: pick(l.title.en, l.title.ru, lang), url: l.url })),
    },
  };
}

export async function clientRoutes(app: FastifyInstance, opts: { ctx: AppContext; guards: { requireAuth: Guard } }) {
  const { ctx, guards } = opts;

  app.get('/client/profile', { onRequest: guards.requireAuth }, async (req) => {
    const auth = authOf(req);
    const lang = resolveLang(req.headers['accept-language']);
    return {
      account: accountView(ctx, auth.account, auth.plan, lang),
      device: {
        id: auth.device.id,
        model: auth.device.model,
        os_version: auth.device.osVersion,
        install_id_last4: auth.device.installId.slice(-4),
      },
      client: {
        locale: auth.device.locale,
        app_build: auth.device.appBuild,
        last_seen: auth.device.lastSeenAt ? iso(auth.device.lastSeenAt) : null,
      },
    };
  });

  app.get('/client/store-state', async (req, reply) => {
    void reply.header('cache-control', 'no-cache');
    return storeStateView(ctx, resolveLang(req.headers['accept-language']));
  });

  app.get('/client/version', async (req, reply) => {
    const q = parseInput(versionQuery, req.query, 'query');
    const header = req.headers['x-client-build'];
    const build = q.build ?? (typeof header === 'string' && /^\d{1,10}$/.test(header) ? Number(header) : undefined);
    if (build === undefined) throw invalidRequest('build is required (query ?build= or X-Client-Build)');
    const lang = resolveLang(req.headers['accept-language']);
    const [v] = await ctx.db.select().from(clientVersion).where(eq(clientVersion.id, 1));
    if (!v) throw new Error('client_version singleton is missing');
    void reply.header('cache-control', 'no-cache');
    return {
      latest_version: v.latestVersion,
      latest_build: v.latestBuild,
      min_supported_build: v.minSupportedBuild,
      update_available: build < v.latestBuild,
      mandatory: build < v.minSupportedBuild,
      release_notes: pickOpt(v.releaseNotesEn, v.releaseNotesRu, lang),
      update_url: v.updateUrl,
    };
  });

  app.post('/client/events', { onRequest: guards.requireAuth }, async (req, reply) => {
    const auth = authOf(req);
    const body = parseInput(eventsSchema, req.body, 'body');
    await ctx.db.insert(clientEvents).values(
      body.events.map((e) => ({
        accountId: auth.account.id,
        deviceId: auth.device.id,
        kind: e.kind,
        ts: new Date(e.ts),
        props: e.props,
      })),
    );
    return reply.code(202).send();
  });

  app.post('/client/push-token', { onRequest: guards.requireAuth }, async (req, reply) => {
    const auth = authOf(req);
    const body = parseInput(pushSchema, req.body, 'body');
    const values = {
      apnsToken: body.apns_token.toLowerCase(),
      apnsEnv: body.apns_env,
      locale: body.locale ?? null,
      tzOffsetMinutes: body.tz_offset_minutes ?? null,
      updatedAt: ctx.now(),
    };
    await ctx.db.transaction(async (tx) => {
      // Токен APNs принадлежит одной установке: после повторного входа он уходит новому устройству.
      await tx.delete(pushTokens).where(and(eq(pushTokens.apnsToken, values.apnsToken), ne(pushTokens.deviceId, auth.device.id)));
      await tx
        .insert(pushTokens)
        .values({ deviceId: auth.device.id, ...values })
        .onConflictDoUpdate({ target: pushTokens.deviceId, set: values });
    });
    return reply.code(204).send();
  });
}
