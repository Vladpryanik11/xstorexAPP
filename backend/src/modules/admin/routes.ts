import { randomUUID } from 'node:crypto';
import { mkdir, rm } from 'node:fs/promises';
import path from 'node:path';
import multipart from '@fastify/multipart';
import { eq } from 'drizzle-orm';
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import type { AppContext } from '../../context.js';
import { accounts, apps, categories, clientVersion, storeState } from '../../db/schema.js';
import { safeEqual } from '../../lib/crypto.js';
import { AppError, invalidRequest, notFound } from '../../lib/errors.js';
import { localizedInput, parseInput, toLocalized, toLocalizedOpt } from '../../lib/validation.js';
import { accountRecipients } from '../../push/notifier.js';
import { iso } from '../catalog/present.js';
import { recordChanges } from '../catalog/revision.js';
import { TABS } from '../catalog/storefront.js';
import { adminAppView, appCreateSchema, appPatchSchema, createApp, unpublishApp, updateApp } from './apps.js';
import { addBuildFromFile, buildFieldsSchema, buildView, saveStream, type FileDigest } from './builds.js';
import { createActivationCodes } from './codes.js';
import { replaceStorefront, storefrontSchema } from './storefront.js';

const idParam = z.object({ id: z.string().min(1).max(80) });

const codesSchema = z
  .object({
    count: z.number().int().min(1).max(1000),
    plan_id: z.string().min(1).max(64),
    duration_days: z.number().int().min(1).max(3650).optional(),
  })
  .strict();

const pushTestSchema = z
  .object({
    account_id: z.string().min(1).max(80),
    title: z.string().trim().min(1).max(100).optional(),
    body: z.string().trim().min(1).max(500).optional(),
  })
  .strict();

const linkUrl = z.url({ protocol: /^(https?|tg|mailto)$/ }).max(2048);

const storeStateSchema = z
  .object({
    state: z.enum(['open', 'closed']),
    closed: z
      .object({
        title: localizedInput(120).optional(),
        message: localizedInput(2000).optional(),
        reopens_at: z.iso.datetime({ offset: true }).nullable().optional(),
        links: z
          .array(z.object({ title: localizedInput(100), url: linkUrl }).strict())
          .max(10)
          .optional(),
      })
      .strict()
      .nullable()
      .optional(),
  })
  .strict();

const clientVersionSchema = z
  .object({
    latest_version: z.string().regex(/^\d{1,4}(\.\d{1,4}){0,3}$/),
    latest_build: z.number().int().min(0).max(2_147_483_647),
    min_supported_build: z.number().int().min(0).max(2_147_483_647),
    release_notes: localizedInput(4000).nullable().optional(),
    update_url: z
      .string()
      .max(2048)
      .regex(/^(itms-services:\/\/\?|https:\/\/)\S+$/, 'expected itms-services:// or https:// URL')
      .nullable()
      .optional(),
  })
  .strict()
  .refine((v) => v.min_supported_build <= v.latest_build, 'min_supported_build must be <= latest_build');

const categorySchema = z
  .object({
    kind: z.enum(['apps', 'games']),
    name: localizedInput(60),
    sf_symbol: z.string().regex(/^[a-z0-9.]{1,64}$/),
    position: z.number().int().min(0).max(10_000).optional(),
  })
  .strict();

const ADMIN_BEARER_RE = /^Bearer\s+(\S+)\s*$/i;

export async function adminRoutes(app: FastifyInstance, opts: { ctx: AppContext }) {
  const { ctx } = opts;
  const adminToken = ctx.config.adminToken;

  // onRequest: reject before any body (possibly a 2 GB upload) is read.
  app.addHook('onRequest', async (req) => {
    if (!adminToken) {
      throw new AppError(503, 'admin_disabled', {
        en: 'Admin API is disabled: ADMIN_TOKEN is not configured',
        ru: 'Админ-API выключен: не задан ADMIN_TOKEN',
      });
    }
    const m = typeof req.headers.authorization === 'string' ? ADMIN_BEARER_RE.exec(req.headers.authorization) : null;
    if (!m?.[1] || !safeEqual(m[1], adminToken)) {
      throw new AppError(401, 'unauthorized', { en: 'Admin token required', ru: 'Нужен токен администратора' });
    }
  });

  await app.register(multipart, {
    limits: { fileSize: ctx.config.maxUploadBytes, files: 1, fields: 10, fieldSize: 64 * 1024, parts: 12 },
  });

  // --- apps -----------------------------------------------------------------

  app.post('/apps', async (req, reply) => {
    const body = parseInput(appCreateSchema, req.body, 'body');
    const row = await createApp(ctx, body);
    return reply.code(201).send(await adminAppView(ctx, row));
  });

  app.get('/apps/:id', async (req) => {
    const { id } = parseInput(idParam, req.params, 'params');
    const [row] = await ctx.db.select().from(apps).where(eq(apps.id, id));
    if (!row) throw notFound();
    return adminAppView(ctx, row);
  });

  app.patch('/apps/:id', async (req) => {
    const { id } = parseInput(idParam, req.params, 'params');
    const body = parseInput(appPatchSchema, req.body, 'body');
    return adminAppView(ctx, await updateApp(ctx, id, body));
  });

  app.delete('/apps/:id', async (req, reply) => {
    const { id } = parseInput(idParam, req.params, 'params');
    await unpublishApp(ctx, id);
    return reply.code(204).send();
  });

  app.post('/apps/:id/builds', async (req, reply) => {
    const { id } = parseInput(idParam, req.params, 'params');
    const [target] = await ctx.db.select({ id: apps.id }).from(apps).where(eq(apps.id, id));
    if (!target) throw notFound();
    if (!req.isMultipart()) throw invalidRequest('expected multipart/form-data with an "ipa" file');

    await mkdir(ctx.config.uploadTmpDir, { recursive: true });
    const tmp = path.join(ctx.config.uploadTmpDir, `${randomUUID()}.ipa`);
    const fields: Record<string, string> = {};
    let digest: FileDigest | null = null;
    try {
      for await (const part of req.parts()) {
        if (part.type === 'file') {
          if (part.fieldname !== 'ipa' || digest) {
            part.file.resume();
            throw invalidRequest('only one file field named "ipa" is accepted');
          }
          digest = await saveStream(part.file, tmp);
          if (part.file.truncated) {
            throw new AppError(413, 'payload_too_large', { en: 'IPA is too large', ru: 'IPA слишком большой' });
          }
        } else if (typeof part.value === 'string') {
          fields[part.fieldname] = part.value;
        }
      }
      if (!digest) throw invalidRequest('the "ipa" file is required');
      const parsed = parseInput(buildFieldsSchema, fields, 'body');
      const row = await addBuildFromFile(ctx, id, tmp, parsed, digest);
      return reply.code(201).send(buildView(row));
    } finally {
      await rm(tmp, { force: true });
    }
  });

  // --- storefront & categories ---------------------------------------------

  app.put('/storefront/:tab', async (req) => {
    const { tab } = parseInput(z.object({ tab: z.enum(TABS) }), req.params, 'params');
    const body = parseInput(storefrontSchema, req.body, 'body');
    const revision = await replaceStorefront(ctx, tab, body);
    return { tab, revision, rooms: body.rooms.map((r) => ({ id: r.id, style: r.style })) };
  });

  /** Not in API.md: categories have to exist before apps reference them. */
  app.put('/categories/:id', async (req) => {
    const { id } = parseInput(z.object({ id: z.string().regex(/^[a-z0-9_]{2,64}$/) }), req.params, 'params');
    const body = parseInput(categorySchema, req.body, 'body');
    const name = toLocalized(body.name);
    const values = {
      kind: body.kind,
      nameEn: name.en,
      nameRu: name.ru,
      sfSymbol: body.sf_symbol,
      position: body.position ?? 0,
      updatedAt: ctx.now(),
    };
    await ctx.db.transaction(async (tx) => {
      await tx.insert(categories).values({ id, ...values }).onConflictDoUpdate({ target: categories.id, set: values });
      await recordChanges(tx, [{ kind: 'rooms_changed', appId: null }], ctx.config.catalogJournalLimit);
    });
    await ctx.bus.notify();
    return { id, kind: body.kind, name, sf_symbol: body.sf_symbol, position: values.position };
  });

  // --- activation codes ------------------------------------------------------

  app.post('/activation-codes', async (req, reply) => {
    const body = parseInput(codesSchema, req.body, 'body');
    const codes = await createActivationCodes(ctx, body.count, body.plan_id, body.duration_days ?? null);
    req.log.info({ count: codes.length, planId: body.plan_id }, 'activation codes created');
    return reply.code(201).send({ codes });
  });

  // --- store state & client version -----------------------------------------

  app.put('/store-state', async (req) => {
    const body = parseInput(storeStateSchema, req.body, 'body');
    const closed =
      body.state === 'closed'
        ? {
            title: toLocalized(body.closed?.title ?? { en: 'We are closed for now', ru: 'Сейчас мы закрыты' }),
            message: toLocalized(body.closed?.message ?? { en: 'The store will be back soon.', ru: 'Магазин скоро снова откроется.' }),
            reopens_at: body.closed?.reopens_at ? iso(new Date(body.closed.reopens_at)) : null,
            links: (body.closed?.links ?? []).map((l) => ({ title: toLocalized(l.title), url: l.url })),
          }
        : null;
    await ctx.db.update(storeState).set({ state: body.state, closed, updatedAt: ctx.now() }).where(eq(storeState.id, 1));
    return { state: body.state, closed };
  });

  // --- push --------------------------------------------------------------------

  /** Проверка настройки APNs: отправляет тестовое уведомление на устройства аккаунта и ждёт результат. */
  app.post('/push/test', async (req) => {
    const body = parseInput(pushTestSchema, req.body, 'body');
    if (!ctx.push.enabled) {
      throw new AppError(503, 'push_disabled', {
        en: 'APNs is not configured (APNS_KEY_ID, APNS_TEAM_ID, APNS_KEY_BASE64).',
        ru: 'APNs не настроен (APNS_KEY_ID, APNS_TEAM_ID, APNS_KEY_BASE64).',
      });
    }
    const [account] = await ctx.db.select({ id: accounts.id }).from(accounts).where(eq(accounts.id, body.account_id));
    if (!account) throw notFound();
    const recipients = await accountRecipients(ctx.db, account.id);
    const summary = await ctx.push.deliver(recipients, (lang) => ({
      payload: {
        aps: {
          alert: {
            title: body.title ?? 'Xstore',
            body: body.body ?? (lang === 'ru' ? 'Тестовое уведомление: push работает.' : 'Test notification: push works.'),
          },
          sound: 'default',
        },
        kind: 'test',
      },
    }));
    return { devices: recipients.length, ...summary };
  });

  app.put('/client-version', async (req) => {
    const body = parseInput(clientVersionSchema, req.body, 'body');
    const notes = toLocalizedOpt(body.release_notes);
    await ctx.db
      .update(clientVersion)
      .set({
        latestVersion: body.latest_version,
        latestBuild: body.latest_build,
        minSupportedBuild: body.min_supported_build,
        releaseNotesEn: notes.en,
        releaseNotesRu: notes.ru,
        updateUrl: body.update_url ?? null,
        updatedAt: ctx.now(),
      })
      .where(eq(clientVersion.id, 1));
    return { ...body, release_notes: notes, update_url: body.update_url ?? null };
  });
}
