import { and, desc, eq, isNotNull } from 'drizzle-orm';
import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { z } from 'zod';
import type { AppContext } from '../../context.js';
import { appBuilds, apps, clientEvents, installs, type InstallRow } from '../../db/schema.js';
import { hmacBase64url, newId, safeEqual, sha256Hex } from '../../lib/crypto.js';
import { AppError, conflict, notFound } from '../../lib/errors.js';
import { pick, resolveLang } from '../../lib/i18n.js';
import { parseRange } from '../../lib/range.js';
import { parseInput } from '../../lib/validation.js';
import { authOf, type Guard } from '../auth/guard.js';
import { iso, loadPublished } from '../catalog/present.js';
import { buildManifest } from './manifest.js';

const INSTALL_ID_RE = /^ins_[a-z0-9]{6,40}$/;

const createSchema = z.object({
  app_id: z.string().min(1).max(80),
  version: z.string().trim().min(1).max(32).nullable().optional(),
});
const eventSchema = z.object({
  stage: z.enum(['preparing', 'ready', 'handing_off', 'installing', 'failed']),
  error_code: z
    .string()
    .regex(/^[a-z0-9_.]{1,64}$/)
    .nullable()
    .optional(),
});

export interface InstallGrant {
  install_id: string;
  app_id: string;
  version: string;
  status: 'preparing' | 'ready' | 'failed';
  error_code: string | null;
  manifest_url: string | null;
  itms_url: string | null;
  size_bytes: number | null;
  sha256: string | null;
  expires_at: string;
}

const noBuild = () =>
  conflict('no_build', {
    en: 'This version is not available for installation yet.',
    ru: 'Эту версию пока нельзя установить.',
  });

const badGrantToken = () =>
  new AppError(401, 'unauthorized', {
    en: 'The install link is invalid. Start the installation again.',
    ru: 'Ссылка на установку недействительна. Начните установку заново.',
  });

const grantExpired = () =>
  new AppError(401, 'grant_expired', {
    en: 'The install link has expired. Start the installation again.',
    ru: 'Срок ссылки на установку истёк. Начните установку заново.',
  });

export async function installsRoutes(
  app: FastifyInstance,
  opts: { ctx: AppContext; guards: { requireActive: Guard; requireAuth: Guard } },
) {
  const { ctx, guards } = opts;
  const grantToken = (installId: string) => hmacBase64url(ctx.config.grantSecret, `grant:${installId}`);

  function grantView(row: InstallRow): InstallGrant {
    let status = row.status;
    let errorCode = row.errorCode;
    if (row.expiresAt.getTime() <= ctx.now().getTime() && status !== 'failed') {
      status = 'failed';
      errorCode = 'grant_expired';
    }
    const manifestUrl =
      status === 'ready'
        ? ctx.apiUrl(`/api/v1/catalog/installs/${row.id}/manifest.plist?t=${encodeURIComponent(grantToken(row.id))}`)
        : null;
    return {
      install_id: row.id,
      app_id: row.appId,
      version: row.version,
      status,
      error_code: errorCode,
      manifest_url: manifestUrl,
      itms_url: manifestUrl ? `itms-services://?action=download-manifest&url=${encodeURIComponent(manifestUrl)}` : null,
      size_bytes: row.sizeBytes,
      sha256: row.sha256,
      expires_at: iso(row.expiresAt),
    };
  }

  async function ownGrant(req: FastifyRequest): Promise<InstallRow> {
    const id = (req.params as { install_id?: string }).install_id ?? '';
    if (!INSTALL_ID_RE.test(id)) throw notFound();
    const [row] = await ctx.db
      .select()
      .from(installs)
      .where(and(eq(installs.id, id), eq(installs.accountId, authOf(req).account.id)));
    if (!row) throw notFound();
    return row;
  }

  /** Public manifest/IPA access: authorised only by the grant token in `?t=`. */
  async function grantByToken(req: FastifyRequest): Promise<{ row: InstallRow; token: string }> {
    const id = (req.params as { install_id?: string }).install_id ?? '';
    const t = (req.query as { t?: unknown }).t;
    if (!INSTALL_ID_RE.test(id)) throw notFound();
    const [row] = await ctx.db.select().from(installs).where(eq(installs.id, id));
    if (!row) throw notFound();
    if (typeof t !== 'string' || t.length === 0 || t.length > 128 || !safeEqual(sha256Hex(t), row.tokenHash)) {
      throw badGrantToken();
    }
    if (row.expiresAt.getTime() <= ctx.now().getTime()) throw grantExpired();
    if (row.status !== 'ready' || !row.blobKey) throw conflict('not_ready', { en: 'Not ready yet', ru: 'Ещё не готово' });
    return { row, token: t };
  }

  app.post('/catalog/installs', { onRequest: guards.requireActive }, async (req, reply) => {
    const auth = authOf(req);
    const body = parseInput(createSchema, req.body, 'body');
    const lang = resolveLang(req.headers['accept-language']);
    const target = (await loadPublished(ctx, [body.app_id])).get(body.app_id);
    if (!target) throw notFound();

    const conditions = [eq(appBuilds.appId, body.app_id), isNotNull(appBuilds.blobKey)];
    if (body.version) conditions.push(eq(appBuilds.version, body.version));
    const [build] = await ctx.db
      .select()
      .from(appBuilds)
      .where(and(...conditions))
      .orderBy(desc(appBuilds.releasedAt), desc(appBuilds.createdAt))
      .limit(1);
    if (!build || !build.blobKey) throw noBuild();

    const id = newId('ins', 16);
    const signed = await ctx.signing.prepare({
      installId: id,
      appId: body.app_id,
      build: {
        id: build.id,
        blobKey: build.blobKey,
        bundleId: build.bundleId ?? target.app.bundleId,
        version: build.version,
        sizeBytes: build.sizeBytes,
        sha256: build.sha256,
      },
    });
    const now = ctx.now();
    const [row] = await ctx.db
      .insert(installs)
      .values({
        id,
        accountId: auth.account.id,
        deviceId: auth.device.id,
        appId: body.app_id,
        buildId: build.id,
        version: build.version,
        status: signed.status,
        errorCode: signed.status === 'failed' ? signed.errorCode : null,
        signer: ctx.signing.name,
        tokenHash: sha256Hex(grantToken(id)),
        blobKey: signed.status === 'ready' ? signed.blobKey : null,
        sizeBytes: signed.status === 'ready' ? signed.sizeBytes : build.sizeBytes,
        sha256: signed.status === 'ready' ? signed.sha256 : build.sha256,
        locale: lang,
        expiresAt: new Date(now.getTime() + ctx.config.grantTtlSeconds * 1000),
        createdAt: now,
        updatedAt: now,
      })
      .returning();
    if (!row) throw new Error('install insert returned nothing');
    req.log.info({ installId: id, appId: body.app_id, version: build.version }, 'install grant created');
    return reply.code(201).send(grantView(row));
  });

  app.get('/catalog/installs/:install_id', { onRequest: guards.requireAuth }, async (req) => grantView(await ownGrant(req)));

  app.post('/catalog/installs/:install_id/events', { onRequest: guards.requireAuth }, async (req, reply) => {
    const auth = authOf(req);
    const row = await ownGrant(req);
    const body = parseInput(eventSchema, req.body, 'body');
    const now = ctx.now();
    await ctx.db
      .update(installs)
      .set({ clientStage: body.stage, clientErrorCode: body.error_code ?? null, updatedAt: now })
      .where(eq(installs.id, row.id));
    await ctx.db.insert(clientEvents).values({
      accountId: auth.account.id,
      deviceId: auth.device.id,
      kind: 'install.step',
      ts: now,
      props: { install_id: row.id, app_id: row.appId, version: row.version, stage: body.stage, error_code: body.error_code ?? null },
    });
    return reply.code(204).send();
  });

  app.get('/catalog/installs/:install_id/manifest.plist', async (req, reply) => {
    const { row, token } = await grantByToken(req);
    const [appRow] = await ctx.db.select().from(apps).where(eq(apps.id, row.appId));
    const [build] = await ctx.db.select().from(appBuilds).where(eq(appBuilds.id, row.buildId));
    if (!appRow || !appRow.published || !build) throw notFound();
    const bundleId = build.bundleId ?? appRow.bundleId;
    if (!bundleId) throw notFound();
    const xml = buildManifest({
      ipaUrl: ctx.apiUrl(`/api/v1/catalog/installs/${row.id}/app.ipa?t=${encodeURIComponent(token)}`),
      displayImageUrl: ctx.assetUrl(appRow.iconSmallUrl ?? appRow.iconUrl),
      fullSizeImageUrl: ctx.assetUrl(appRow.iconUrl),
      bundleId,
      bundleVersion: row.version,
      title: pick(appRow.nameEn, appRow.nameRu, row.locale),
    });
    return reply.header('cache-control', 'no-store').type('application/xml; charset=utf-8').send(xml);
  });

  // GET + HEAD in one route: the auto-generated HEAD would read the whole stream.
  const serveIpa = async (req: FastifyRequest, reply: FastifyReply) => {
    const { row } = await grantByToken(req);
    // Снятое с публикации приложение не отдаётся и по действующему гранту.
    const [target] = await ctx.db.select({ published: apps.published }).from(apps).where(eq(apps.id, row.appId));
    if (!target?.published) throw notFound();
    const key = row.blobKey!;
    const stat = await ctx.storage.stat(key);
    if (!stat) {
      req.log.error({ installId: row.id }, 'IPA blob is missing from storage');
      throw notFound();
    }
    void reply.header('accept-ranges', 'bytes');
    void reply.header('cache-control', 'no-store');
    void reply.type('application/octet-stream');
    if (row.sha256) void reply.header('etag', `"${row.sha256}"`);

    const range = parseRange(typeof req.headers.range === 'string' ? req.headers.range : undefined, stat.size);
    if (range.kind === 'unsatisfiable') {
      void reply.header('content-range', `bytes */${stat.size}`);
      throw new AppError(416, 'range_not_satisfiable', {
        en: 'Requested range is not satisfiable',
        ru: 'Запрошенный диапазон недоступен',
      });
    }
    if (range.kind === 'partial') {
      const { start, end } = range.range;
      void reply.code(206);
      void reply.header('content-range', `bytes ${start}-${end}/${stat.size}`);
      void reply.header('content-length', end - start + 1);
      if (req.method === 'HEAD') return reply.send();
      return reply.send(await ctx.storage.createReadStream(key, { start, end }));
    }
    void reply.header('content-length', stat.size);
    if (req.method === 'HEAD') return reply.send();
    return reply.send(await ctx.storage.createReadStream(key));
  };
  app.route({ method: ['GET', 'HEAD'], url: '/catalog/installs/:install_id/app.ipa', handler: serveIpa });
}
