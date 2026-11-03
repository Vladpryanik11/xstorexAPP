import path from 'node:path';
import { createPrivateKey, randomBytes } from 'node:crypto';
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
  /** null → push-уведомления выключены. */
  apns: ApnsConfig | null;
}

export interface ApnsConfig {
  /** Key ID ключа `.p8` из Apple Developer. */
  keyId: string;
  teamId: string;
  /** PEM ключа `.p8`. */
  keyPem: string;
  /** Bundle id приложения Xstore. */
  topic: string;
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
  APNS_KEY_ID: z.preprocess(emptyToUndefined, z.string().regex(/^[A-Z0-9]{10}$/, 'expected a 10-character key id').optional()),
  APNS_TEAM_ID: z.preprocess(emptyToUndefined, z.string().regex(/^[A-Z0-9]{10}$/, 'expected a 10-character team id').optional()),
  APNS_KEY_BASE64: optStr,
  APNS_TOPIC: z.preprocess(emptyToUndefined, z.string().regex(/^[A-Za-z0-9.-]{3,155}$/).default('com.istore.app')),
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
    apns: apnsConfig(e),
  };
}

function apnsConfig(e: z.infer<typeof envSchema>): ApnsConfig | null {
  const parts = { APNS_KEY_ID: e.APNS_KEY_ID, APNS_TEAM_ID: e.APNS_TEAM_ID, APNS_KEY_BASE64: e.APNS_KEY_BASE64 };
  const missing = Object.entries(parts).filter(([, v]) => v === undefined).map(([k]) => k);
  if (missing.length === 3) return null;
  if (missing.length > 0) throw new Error(`APNs is partially configured, missing: ${missing.join(', ')}`);
  const keyPem = Buffer.from(e.APNS_KEY_BASE64 ?? '', 'base64').toString('utf8');
  try {
    createPrivateKey(keyPem);
  } catch {
    throw new Error('APNS_KEY_BASE64 is not a base64-encoded .p8 key (base64 -w0 AuthKey_XXXXXXXXXX.p8)');
  }
  return { keyId: e.APNS_KEY_ID ?? '', teamId: e.APNS_TEAM_ID ?? '', keyPem, topic: e.APNS_TOPIC };
}

export function stripTrailingSlash(url: string): string {
  return url.replace(/\/+$/, '');
}
