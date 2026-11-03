import type { ServerResponse } from 'node:http';
import rateLimit from '@fastify/rate-limit';
import Fastify, { type FastifyInstance, type FastifyServerOptions } from 'fastify';
import type { AppConfig } from './config.js';
import { createUrlHelpers, type AppContext } from './context.js';
import { openDatabase, type Database } from './db/index.js';
import { AppError, registerErrorHandling } from './lib/errors.js';
import { adminRoutes } from './modules/admin/routes.js';
import { createGuards } from './modules/auth/guard.js';
import { authRoutes } from './modules/auth/routes.js';
import { CatalogBus } from './modules/catalog/bus.js';
import { catalogRoutes } from './modules/catalog/routes.js';
import { staticRoutes } from './modules/catalog/static.js';
import { clientRoutes } from './modules/client/routes.js';
import { followsRoutes } from './modules/follows/routes.js';
import { installsRoutes } from './modules/installs/routes.js';
import { searchRoutes } from './modules/search/routes.js';
import { ApnsSender } from './push/apns.js';
import { PushNotifier, type PushLog } from './push/notifier.js';
import { DisabledPushSender, type PushSender } from './push/push-sender.js';
import { PreSignedProvider } from './signing/presigned.js';
import type { SigningProvider } from './signing/signing-provider.js';
import type { BlobStorage } from './storage/blob-storage.js';
import { LocalBlobStorage } from './storage/local.js';

export interface BuildAppOptions {
  /** Reuse an already opened database (tests, seed). Otherwise one is opened from config. */
  database?: Database;
  storage?: BlobStorage;
  signing?: SigningProvider;
  /** Канал push; по умолчанию APNs из конфига или выключенный. */
  push?: PushSender;
  now?: () => Date;
}

declare module 'fastify' {
  interface FastifyInstance {
    ctx: AppContext;
  }
}

/** Query-string secrets must never reach the logs. */
export function redactUrl(url: string): string {
  return url.replace(/([?&](?:t|token|code|activation_code)=)[^&#]*/gi, '$1[redacted]');
}

function loggerOptions(config: AppConfig): FastifyServerOptions['logger'] {
  if (config.logLevel === 'silent') return false;
  return {
    level: config.logLevel,
    redact: {
      paths: [
        'req.headers.authorization',
        'req.headers.cookie',
        'headers.authorization',
        'body.activation_code',
        'body.token',
        'token',
      ],
      censor: '[redacted]',
    },
    serializers: {
      req(req: { method: string; url: string; ip?: string; id?: string }) {
        return { method: req.method, url: redactUrl(req.url), remoteAddress: req.ip, reqId: req.id };
      },
    },
  };
}

const SILENT_LOG: PushLog = { info: () => undefined, error: () => undefined };

export function createContext(
  config: AppConfig,
  database: Database,
  deps: { storage?: BlobStorage; signing?: SigningProvider; push?: PushSender; log?: PushLog; now?: () => Date } = {},
): AppContext {
  const sender = deps.push ?? (config.apns ? new ApnsSender(config.apns) : new DisabledPushSender());
  return {
    config,
    db: database.db,
    storage: deps.storage ?? new LocalBlobStorage(config.storageDir),
    signing: deps.signing ?? new PreSignedProvider(),
    bus: new CatalogBus(database.db, deps.log ?? null),
    push: new PushNotifier(database.db, sender, deps.log ?? SILENT_LOG),
    now: deps.now ?? (() => new Date()),
    ...createUrlHelpers(config.publicBaseUrl),
  };
}

export async function buildApp(config: AppConfig, options: BuildAppOptions = {}): Promise<FastifyInstance> {
  const app = Fastify({
    logger: loggerOptions(config),
    trustProxy: config.trustProxy,
    bodyLimit: 1024 * 1024,
  });

  const ownsDatabase = !options.database;
  const database = options.database ?? (await openDatabase({ databaseUrl: config.databaseUrl, pgliteDir: config.pgliteDir }));
  const ctx = createContext(config, database, { ...options, log: app.log });
  await ctx.bus.init();
  ctx.bus.startPolling(config.catalogPollMs);
  app.decorate('ctx', ctx);
  app.decorateRequest('auth', null);

  // JSON parser that tolerates an empty body (e.g. POST /app/sign-out with Content-Type: application/json).
  const defaultJson = app.getDefaultJsonParser('error', 'error');
  app.removeContentTypeParser('application/json');
  app.addContentTypeParser('application/json', { parseAs: 'string' }, (req, body, done) => {
    if (typeof body === 'string' && body.trim() === '') {
      done(null, undefined);
      return;
    }
    defaultJson(req, body as string, done);
  });

  registerErrorHandling(app);

  app.addHook('onSend', async (_req, reply, payload) => {
    void reply.header('x-content-type-options', 'nosniff');
    return payload;
  });

  await app.register(rateLimit, {
    global: false,
    errorResponseBuilder: (_req, context) =>
      new AppError(429, 'rate_limited', {
        en: `Too many attempts. Try again in ${context.after}.`,
        ru: `Слишком много попыток. Повторите через ${context.after}.`,
      }),
  });

  const guards = createGuards(ctx);
  const sseConnections = new Set<ServerResponse>();

  await app.register(
    async (api) => {
      await api.register(authRoutes, { ctx, guards });
      await api.register(clientRoutes, { ctx, guards });
      await api.register(catalogRoutes, { ctx, guards, sseConnections });
      await api.register(searchRoutes, { ctx, guards });
      await api.register(installsRoutes, { ctx, guards });
      await api.register(followsRoutes, { ctx, guards });
    },
    { prefix: '/api/v1' },
  );
  await app.register(adminRoutes, { prefix: '/admin/v1', ctx });
  await app.register(staticRoutes, { ctx });

  app.get('/healthz', async () => ({ ok: true }));

  app.addHook('preClose', async () => {
    for (const res of sseConnections) res.end();
    sseConnections.clear();
  });
  app.addHook('onClose', async () => {
    ctx.bus.stop();
    await ctx.push.drain();
    await ctx.push.sender.close();
    if (ownsDatabase) await database.close();
  });

  return app;
}
