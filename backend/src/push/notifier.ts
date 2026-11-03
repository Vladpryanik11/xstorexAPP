import { and, eq, exists, gt, isNull, or } from 'drizzle-orm';
import type { Db } from '../db/index.js';
import { accounts, apps, devices, follows, pushTokens, tokens, type AppRow } from '../db/schema.js';
import { pick, pickOpt, resolveLang, type Lang } from '../lib/i18n.js';
import type { ApnsEnv, PushMessage, PushSender } from './push-sender.js';

export interface PushLog {
  info(obj: object, msg: string): void;
  error(obj: object, msg: string): void;
}

export interface PushRecipient {
  deviceId: string;
  token: string;
  env: ApnsEnv;
  lang: Lang;
}

export interface DeliverySummary {
  sent: number;
  failed: number;
  /** Сколько недействительных токенов удалено. */
  removed: number;
  errors: { device_id: string; status: number; reason: string }[];
}

type MessageBuilder = (lang: Lang) => Omit<PushMessage, 'token' | 'env'>;

const CONCURRENCY = 20;
const MAX_REPORTED_ERRORS = 20;

/** Рассылка push: очередь фоновых задач и доставка с чисткой мёртвых токенов. */
export class PushNotifier {
  private queue: Promise<void> = Promise.resolve();

  constructor(
    private readonly db: Db,
    readonly sender: PushSender,
    readonly log: PushLog,
  ) {}

  get enabled(): boolean {
    return this.sender.enabled;
  }

  /** Ставит задачу в очередь и сразу возвращает управление. Задачи выполняются по одной. */
  enqueue(name: string, job: () => Promise<void>): void {
    this.queue = this.queue.then(job).catch((err: unknown) => this.log.error({ err, job: name }, 'push job failed'));
  }

  /** Ждёт завершения всех задач в очереди (тесты, остановка сервера). */
  drain(): Promise<void> {
    return this.queue;
  }

  async deliver(recipients: PushRecipient[], build: MessageBuilder): Promise<DeliverySummary> {
    const summary: DeliverySummary = { sent: 0, failed: 0, removed: 0, errors: [] };
    for (let i = 0; i < recipients.length; i += CONCURRENCY) {
      const batch = recipients.slice(i, i + CONCURRENCY);
      await Promise.all(
        batch.map(async (r) => {
          const result = await this.sender.send({ ...build(r.lang), token: r.token, env: r.env });
          if (result.ok) {
            summary.sent += 1;
            return;
          }
          summary.failed += 1;
          if (summary.errors.length < MAX_REPORTED_ERRORS) {
            summary.errors.push({ device_id: r.deviceId, status: result.status, reason: result.reason });
          }
          if (result.unregistered) {
            const removed = await this.db
              .delete(pushTokens)
              .where(and(eq(pushTokens.deviceId, r.deviceId), eq(pushTokens.apnsToken, r.token)))
              .returning({ id: pushTokens.id });
            summary.removed += removed.length;
          }
        }),
      );
    }
    return summary;
  }
}

/** Устройство с выполненным входом: у него есть неотозванный токен. */
function signedIn(db: Db) {
  return exists(
    db
      .select({ id: tokens.id })
      .from(tokens)
      .where(and(eq(tokens.deviceId, devices.id), isNull(tokens.revokedAt))),
  );
}

function activeAccount(now: Date) {
  return and(eq(accounts.status, 'active'), or(isNull(accounts.expiresAt), gt(accounts.expiresAt, now)));
}

const recipientColumns = {
  deviceId: pushTokens.deviceId,
  token: pushTokens.apnsToken,
  env: pushTokens.apnsEnv,
  pushLocale: pushTokens.locale,
  deviceLocale: devices.locale,
};

function toRecipients(rows: { deviceId: string; token: string; env: ApnsEnv; pushLocale: string | null; deviceLocale: string | null }[]) {
  const seen = new Set<string>();
  const result: PushRecipient[] = [];
  for (const row of rows) {
    if (seen.has(row.token)) continue;
    seen.add(row.token);
    result.push({
      deviceId: row.deviceId,
      token: row.token,
      env: row.env,
      lang: resolveLang(row.pushLocale ?? row.deviceLocale ?? undefined),
    });
  }
  return result;
}

/** Подписчики приложения без mute, с активной подпиской и выполненным входом на устройстве. */
export async function followerRecipients(db: Db, appId: string, now: Date): Promise<PushRecipient[]> {
  const rows = await db
    .select(recipientColumns)
    .from(follows)
    .innerJoin(accounts, eq(accounts.id, follows.accountId))
    .innerJoin(devices, eq(devices.accountId, follows.accountId))
    .innerJoin(pushTokens, eq(pushTokens.deviceId, devices.id))
    .where(and(eq(follows.appId, appId), eq(follows.muted, false), activeAccount(now), signedIn(db)));
  return toRecipients(rows);
}

/** Все устройства аккаунта с выполненным входом и push-токеном (тестовая отправка из админки). */
export async function accountRecipients(db: Db, accountId: string): Promise<PushRecipient[]> {
  const rows = await db
    .select(recipientColumns)
    .from(devices)
    .innerJoin(pushTokens, eq(pushTokens.deviceId, devices.id))
    .where(and(eq(devices.accountId, accountId), signedIn(db)));
  return toRecipients(rows);
}

const UPDATE_TTL_SECONDS = 24 * 60 * 60;
const NOTES_PREVIEW_CHARS = 120;

function preview(text: string): string {
  const flat = text.replace(/\s+/g, ' ').trim();
  return flat.length > NOTES_PREVIEW_CHARS ? `${flat.slice(0, NOTES_PREVIEW_CHARS - 1)}…` : flat;
}

/** Payload уведомления об обновлении (контракт — раздел «Push» в API.md). */
export function appUpdateMessage(app: AppRow, lang: Lang): Omit<PushMessage, 'token' | 'env'> {
  const headline = lang === 'ru' ? `Вышла версия ${app.version}` : `Version ${app.version} is out`;
  const notes = pickOpt(app.whatsNewEn, app.whatsNewRu, lang);
  return {
    payload: {
      aps: {
        alert: { title: pick(app.nameEn, app.nameRu, lang), body: notes ? `${headline}. ${preview(notes)}` : headline },
        sound: 'default',
        'thread-id': 'app_update',
      },
      kind: 'app_update',
      app_id: app.id,
      version: app.version,
    },
    collapseId: `update-${app.id}`.slice(0, 64),
    ttlSeconds: UPDATE_TTL_SECONDS,
  };
}

export interface AppUpdateContext {
  db: Db;
  push: PushNotifier;
  now(): Date;
}

/** Ставит в очередь уведомление подписчикам о новой версии. Текущую версию читает в момент отправки. */
export function notifyAppUpdate(ctx: AppUpdateContext, appId: string): void {
  if (!ctx.push.enabled) return;
  ctx.push.enqueue(`app_update:${appId}`, async () => {
    const [app] = await ctx.db.select().from(apps).where(eq(apps.id, appId));
    if (!app || !app.published) return;
    const recipients = await followerRecipients(ctx.db, appId, ctx.now());
    if (recipients.length === 0) return;
    const summary = await ctx.push.deliver(recipients, (lang) => appUpdateMessage(app, lang));
    ctx.push.log.info({ appId, version: app.version, ...summary, errors: summary.errors.length }, 'app update push sent');
  });
}
