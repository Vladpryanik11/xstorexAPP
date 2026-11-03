import path from 'node:path';
import { randomBytes } from 'node:crypto';
import { z } from 'zod';

export interface AppConfig {
  port: number;
  host: string;
  /** Public base URL without trailing slash, e.g. https://api.istore.example */
  publicBaseUrl: string;
  /** null → admin API disabled (503). */
  adminToken: string | null;
  /** null → embedded PGlite. */
  databaseUrl: string | null;
  /** PGlite data directory; null → in-memory (tests). Ignored when databaseUrl is set. */
  pgliteDir: string | null;
  storageDir: string;
  /** Scratch directory for uploads in progress. */
  uploadTmpDir: string;
  logLevel: string;
  maxUploadBytes: number;
  grantSecret: string;
  grantTtlSeconds: number;
  ssePingMs: number;
  catalogJournalLimit: number;
  /** Re-check the change journal every N ms while SSE clients are connected (0 = off). */
  catalogPollMs: number;
  activateRateLimit: { max: number; timeWindowMs: number };
  renewUrl: string | null;
  trustProxy: boolean;
}

const emptyToUndefined = (v: unknown) => (typeof v === 'string' && v.trim() === '' ? undefined : v);
const optStr = z.preprocess(emptyToUndefined, z.string().optional());
const optInt = (def: number, min = 0) =>
  z.preprocess(emptyToUndefined, z.coerce.number().int().min(min).default(def));

const envSchema = z.object({
  PORT: optInt(8080, 1),
  HOST: optStr,
  PUBLIC_BASE_URL: z.preprocess(emptyToUndefined, z.url({ protocol: /^https?$/ }).optional()),
  ADMIN_TOKEN: optStr,
  DATABASE_URL: optStr,
  PGLITE_DIR: optStr,
  STORAGE_DIR: optStr,
  UPLOAD_TMP_DIR: optStr,
  LOG_LEVEL: z.preprocess(
    emptyToUndefined,
    z.enum(['fatal', 'error', 'warn', 'info', 'debug', 'trace', 'silent']).default('info'),
  ),
  MAX_UPLOAD_BYTES: optInt(2 * 1024 * 1024 * 1024, 1),
  GRANT_SECRET: optStr,
  GRANT_TTL_SECONDS: optInt(30 * 60, 60),
  SSE_PING_MS: optInt(25_000, 1000),
  CATALOG_JOURNAL_LIMIT: optInt(10_000, 1),
  CATALOG_POLL_MS: optInt(5_000, 0),
  ACTIVATE_RATE_LIMIT_MAX: optInt(10, 1),
  ACTIVATE_RATE_LIMIT_WINDOW_MS: optInt(60_000, 1000),
  RENEW_URL: z.preprocess(emptyToUndefined, z.url({ protocol: /^https?$/ }).optional()),
  TRUST_PROXY: z.preprocess(emptyToUndefined, z.enum(['true', 'false', '1', '0']).default('false')),
});

export function loadConfig(env: NodeJS.ProcessEnv = process.env, cwd = process.cwd()): AppConfig {
  const parsed = envSchema.safeParse(env);
  if (!parsed.success) {
    const details = parsed.error.issues.map((i) => `${i.path.join('.')}: ${i.message}`).join('; ');
    throw new Error(`Invalid environment: ${details}`);
  }
  const e = parsed.data;
  const storageDir = path.resolve(cwd, e.STORAGE_DIR ?? 'storage');
  const adminToken = e.ADMIN_TOKEN ?? null;
  if (adminToken !== null && adminToken.length < 16) {
    throw new Error('ADMIN_TOKEN must be at least 16 characters long');
  }
  return {
    port: e.PORT,
    host: e.HOST ?? '0.0.0.0',
    publicBaseUrl: stripTrailingSlash(e.PUBLIC_BASE_URL ?? `http://localhost:${e.PORT}`),
    adminToken,
    databaseUrl: e.DATABASE_URL ?? null,
    pgliteDir: path.resolve(cwd, e.PGLITE_DIR ?? '.data/pglite'),
    storageDir,
    uploadTmpDir: path.resolve(cwd, e.UPLOAD_TMP_DIR ?? path.join(storageDir, '.tmp')),
    logLevel: e.LOG_LEVEL,
    maxUploadBytes: e.MAX_UPLOAD_BYTES,
    grantSecret: e.GRANT_SECRET ?? randomBytes(32).toString('base64url'),
    grantTtlSeconds: e.GRANT_TTL_SECONDS,
    ssePingMs: e.SSE_PING_MS,
    catalogJournalLimit: e.CATALOG_JOURNAL_LIMIT,
    catalogPollMs: e.CATALOG_POLL_MS,
    activateRateLimit: { max: e.ACTIVATE_RATE_LIMIT_MAX, timeWindowMs: e.ACTIVATE_RATE_LIMIT_WINDOW_MS },
    renewUrl: e.RENEW_URL ?? null,
    trustProxy: e.TRUST_PROXY === 'true' || e.TRUST_PROXY === '1',
  };
}

export function stripTrailingSlash(url: string): string {
  return url.replace(/\/+$/, '');
}
