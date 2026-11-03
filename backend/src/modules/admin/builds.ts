import { createHash } from 'node:crypto';
import { createReadStream, createWriteStream } from 'node:fs';
import { Transform, type Readable } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import { eq } from 'drizzle-orm';
import { z } from 'zod';
import type { AppContext } from '../../context.js';
import { appBuilds, apps, type BuildRow } from '../../db/schema.js';
import { newId } from '../../lib/crypto.js';
import { AppError, conflict, invalidRequest, notFound } from '../../lib/errors.js';
import { IpaError, readIpaInfo } from '../../lib/ipa.js';
import { compareVersions } from '../../lib/version.js';
import { notifyAppUpdate } from '../../push/notifier.js';
import { iso } from '../catalog/present.js';
import { recordChanges } from '../catalog/revision.js';

export const buildFieldsSchema = z
  .object({
    version: z
      .string()
      .regex(/^[0-9A-Za-z.\-]{1,32}$/)
      .optional(),
    build: z
      .string()
      .regex(/^[0-9A-Za-z.\-]{1,32}$/)
      .optional(),
    notes: z.string().trim().max(4000).optional(),
    notes_ru: z.string().trim().max(4000).optional(),
    released_at: z.iso.datetime({ offset: true }).optional(),
  })
  .strict();

export type BuildFields = z.infer<typeof buildFieldsSchema>;

export interface FileDigest {
  sha256: string;
  size: number;
}

/** Streams `source` into `dest`, computing SHA-256 and size on the way. */
export async function saveStream(source: Readable, dest: string): Promise<FileDigest> {
  const hash = createHash('sha256');
  let size = 0;
  const tap = new Transform({
    transform(chunk: Buffer, _enc, cb) {
      hash.update(chunk);
      size += chunk.length;
      cb(null, chunk);
    },
  });
  await pipeline(source, tap, createWriteStream(dest, { flags: 'wx' }));
  return { sha256: hash.digest('hex'), size };
}

export async function digestFile(filePath: string): Promise<FileDigest> {
  const hash = createHash('sha256');
  let size = 0;
  for await (const chunk of createReadStream(filePath) as AsyncIterable<Buffer>) {
    hash.update(chunk);
    size += chunk.length;
  }
  return { sha256: hash.digest('hex'), size };
}

const invalidIpa = (detail: string) =>
  new AppError(400, 'invalid_ipa', { en: `Invalid IPA: ${detail}`, ru: `Некорректный IPA: ${detail}` });

/**
 * Registers an already-signed IPA located at `filePath` (the file is moved into storage).
 * Version/bundle id come from Payload/*.app/Info.plist; form fields must agree with it.
 */
export async function addBuildFromFile(
  ctx: AppContext,
  appId: string,
  filePath: string,
  fields: BuildFields,
  digest: FileDigest,
): Promise<BuildRow> {
  const [app] = await ctx.db.select().from(apps).where(eq(apps.id, appId));
  if (!app) throw notFound();

  let info;
  try {
    info = await readIpaInfo(filePath);
  } catch (err) {
    if (err instanceof IpaError) throw invalidIpa(err.message);
    throw err;
  }
  if (fields.version && info.shortVersion && fields.version !== info.shortVersion) {
    throw invalidRequest(`version "${fields.version}" does not match CFBundleShortVersionString "${info.shortVersion}"`);
  }
  if (fields.build && info.bundleVersion && fields.build !== info.bundleVersion) {
    throw invalidRequest(`build "${fields.build}" does not match CFBundleVersion "${info.bundleVersion}"`);
  }
  const version = info.shortVersion ?? fields.version;
  const build = info.bundleVersion ?? fields.build ?? version;
  if (!version || !build) throw invalidIpa('CFBundleShortVersionString is missing and no version field was sent');
  if (app.bundleId && app.bundleId !== info.bundleId) {
    throw conflict('bundle_id_mismatch', {
      en: `IPA bundle id ${info.bundleId} does not match the app (${app.bundleId})`,
      ru: `Bundle id в IPA (${info.bundleId}) не совпадает с приложением (${app.bundleId})`,
    });
  }

  const buildId = newId('bld', 12);
  const blobKey = `builds/${appId}/${buildId}.ipa`;
  await ctx.storage.putFile(blobKey, filePath);
  const now = ctx.now();
  try {
    const { row, notify } = await ctx.db.transaction(async (tx) => {
      const [current] = await tx.select().from(apps).where(eq(apps.id, appId)).for('update');
      if (!current) throw notFound();
      const previous = await tx.select({ version: appBuilds.version }).from(appBuilds).where(eq(appBuilds.appId, appId));
      // Сборка в историю (старше уже загруженных) карточку приложения не меняет.
      const latest = previous.every((b) => compareVersions(version, b.version) >= 0);
      const newVersion = latest && compareVersions(version, current.version) !== 0;
      const [created] = await tx
        .insert(appBuilds)
        .values({
          id: buildId,
          appId,
          version,
          build,
          bundleId: info.bundleId,
          minOs: info.minOs,
          sha256: digest.sha256,
          sizeBytes: digest.size,
          blobKey,
          notesEn: fields.notes ?? null,
          notesRu: fields.notes_ru ?? null,
          releasedAt: fields.released_at ? new Date(fields.released_at) : now,
          createdAt: now,
        })
        .returning();
      if (!created) throw new Error('build insert returned nothing');
      await tx
        .update(apps)
        .set({
          bundleId: current.bundleId ?? info.bundleId,
          ...(latest
            ? {
                version,
                sizeBytes: digest.size,
                ...(info.minOs && /^\d{1,2}(\.\d{1,2}){0,2}$/.test(info.minOs) ? { minOs: info.minOs } : {}),
                // «Что нового» относится к версии: у новой версии без notes прежний текст убирается.
                ...(fields.notes || newVersion ? { whatsNewEn: fields.notes || null, whatsNewRu: fields.notes_ru || null } : {}),
              }
            : {}),
          updatedAt: now,
        })
        .where(eq(apps.id, appId));
      await recordChanges(tx, [{ kind: current.published ? 'app_upsert' : 'app_removed', appId }], ctx.config.catalogJournalLimit);
      return { row: created, notify: current.published && latest && compareVersions(version, current.version) > 0 };
    });
    await ctx.bus.notify();
    if (notify) notifyAppUpdate(ctx, appId);
    return row;
  } catch (err) {
    await ctx.storage.delete(blobKey).catch(() => undefined);
    throw err;
  }
}

export function buildView(b: BuildRow) {
  return {
    id: b.id,
    app_id: b.appId,
    version: b.version,
    build: b.build,
    bundle_id: b.bundleId,
    min_os: b.minOs,
    sha256: b.sha256,
    size_bytes: b.sizeBytes,
    released_at: iso(b.releasedAt),
    notes: b.notesEn,
  };
}
