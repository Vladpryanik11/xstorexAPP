import { mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import type { FastifyInstance, LightMyRequestResponse } from 'fastify';
import { buildApp } from '../src/app.js';
import { loadConfig, type AppConfig } from '../src/config.js';
import type { AppContext } from '../src/context.js';
import { openDatabase, type Database } from '../src/db/index.js';
import { seedDemo, type SeedResult } from '../src/seed/run.js';

export const ADMIN_TOKEN = 'test-admin-token-0123456789abcdef';
export const BASE_URL = 'https://api.istore.test';

export interface TestEnv {
  app: FastifyInstance;
  ctx: AppContext;
  config: AppConfig;
  database: Database;
  seed: SeedResult;
  token: string;
  close(): Promise<void>;
}

export async function createTestEnv(overrides: Partial<AppConfig> = {}): Promise<TestEnv> {
  const storageDir = await mkdtemp(path.join(os.tmpdir(), 'istore-test-'));
  const config: AppConfig = {
    ...loadConfig({}, storageDir),
    publicBaseUrl: BASE_URL,
    adminToken: ADMIN_TOKEN,
    pgliteDir: null,
    storageDir,
    uploadTmpDir: path.join(storageDir, '.tmp'),
    logLevel: 'silent',
    catalogPollMs: 0,
    ssePingMs: 25_000,
    ...overrides,
  };
  const database = await openDatabase({ databaseUrl: null, pgliteDir: null });
  const app = await buildApp(config, { database });
  const seed = await seedDemo(app.ctx, { images: false, extraCodes: 3 });
  return {
    app,
    ctx: app.ctx,
    config,
    database,
    seed,
    token: seed.devToken,
    async close() {
      await app.close();
      await database.close();
      await rm(storageDir, { recursive: true, force: true });
    },
  };
}

export const bearer = (token: string, extra: Record<string, string> = {}) => ({ authorization: `Bearer ${token}`, ...extra });
export const admin = (extra: Record<string, string> = {}) => ({ authorization: `Bearer ${ADMIN_TOKEN}`, ...extra });

export function json<T = any>(res: LightMyRequestResponse): T {
  return JSON.parse(res.body) as T;
}

/** Builds a multipart/form-data body for app.inject(). */
export function multipart(
  fields: Record<string, string>,
  file?: { field: string; filename: string; data: Uint8Array; contentType?: string },
): { payload: Buffer; headers: Record<string, string> } {
  const boundary = `----istore${Math.random().toString(16).slice(2)}`;
  const parts: Buffer[] = [];
  for (const [name, value] of Object.entries(fields)) {
    parts.push(Buffer.from(`--${boundary}\r\nContent-Disposition: form-data; name="${name}"\r\n\r\n${value}\r\n`));
  }
  if (file) {
    parts.push(
      Buffer.from(
        `--${boundary}\r\nContent-Disposition: form-data; name="${file.field}"; filename="${file.filename}"\r\n` +
          `Content-Type: ${file.contentType ?? 'application/octet-stream'}\r\n\r\n`,
      ),
      Buffer.from(file.data),
      Buffer.from('\r\n'),
    );
  }
  parts.push(Buffer.from(`--${boundary}--\r\n`));
  return { payload: Buffer.concat(parts), headers: { 'content-type': `multipart/form-data; boundary=${boundary}` } };
}

export async function activate(app: FastifyInstance, code: string, installId: string) {
  return app.inject({
    method: 'POST',
    url: '/api/v1/app/activate',
    payload: { activation_code: code, device: { install_id: installId, model: 'iPhone16,2', os_version: '18.1', locale: 'ru_RU' } },
  });
}
