import { createPrivateKey, sign, type KeyObject } from 'node:crypto';
import http2 from 'node:http2';
import type { ApnsConfig } from '../config.js';
import type { ApnsEnv, PushMessage, PushResult, PushSender } from './push-sender.js';

const ORIGINS: Record<ApnsEnv, string> = {
  production: 'https://api.push.apple.com',
  sandbox: 'https://api.sandbox.push.apple.com',
};

/** Apple принимает токен провайдера до часа и просит обновлять его не чаще раза в 20 минут. */
const PROVIDER_TOKEN_TTL_MS = 50 * 60 * 1000;
const REQUEST_TIMEOUT_MS = 10_000;
const SESSION_IDLE_MS = 5 * 60 * 1000;
/** Причины отказа, после которых токен устройства удаляется (вместе со статусом 410). */
const DEAD_TOKEN_REASONS = new Set(['BadDeviceToken', 'DeviceTokenNotForTopic', 'Unregistered']);

export interface ApnsSenderOptions {
  /** Подмена адресов APNs (тесты). */
  origins?: Partial<Record<ApnsEnv, string>>;
  now?: () => number;
}

/** JWT провайдера APNs (ES256): заголовок `kid`, claims `iss` и `iat`. */
export function makeProviderToken(config: Pick<ApnsConfig, 'keyId' | 'teamId'>, key: KeyObject, issuedAtSec: number): string {
  const header = base64url(JSON.stringify({ alg: 'ES256', kid: config.keyId }));
  const claims = base64url(JSON.stringify({ iss: config.teamId, iat: issuedAtSec }));
  const signature = sign('sha256', Buffer.from(`${header}.${claims}`), { key, dsaEncoding: 'ieee-p1363' });
  return `${header}.${claims}.${signature.toString('base64url')}`;
}

function base64url(text: string): string {
  return Buffer.from(text, 'utf8').toString('base64url');
}

function parseReason(body: Buffer): string | null {
  try {
    const parsed: unknown = JSON.parse(body.toString('utf8'));
    const reason = (parsed as { reason?: unknown }).reason;
    return typeof reason === 'string' && reason ? reason : null;
  } catch {
    return null;
  }
}

/** Отправка через HTTP/2 API APNs с токеном провайдера (ключ `.p8`). */
export class ApnsSender implements PushSender {
  readonly enabled = true;
  private readonly key: KeyObject;
  private readonly origins: Record<ApnsEnv, string>;
  private readonly now: () => number;
  private providerToken: { value: string; issuedAt: number } | null = null;
  private readonly sessions = new Map<string, http2.ClientHttp2Session>();

  constructor(
    private readonly config: ApnsConfig,
    options: ApnsSenderOptions = {},
  ) {
    this.key = createPrivateKey(config.keyPem);
    this.origins = { ...ORIGINS, ...options.origins };
    this.now = options.now ?? Date.now;
  }

  async send(message: PushMessage): Promise<PushResult> {
    const result = await this.request(message);
    if (!result.ok && result.status === 403 && result.reason === 'ExpiredProviderToken') {
      this.providerToken = null;
      return this.request(message);
    }
    return result;
  }

  async close(): Promise<void> {
    const sessions = [...this.sessions.values()];
    this.sessions.clear();
    await Promise.all(
      sessions.map(
        (session) =>
          new Promise<void>((resolve) => {
            if (session.closed || session.destroyed) {
              resolve();
              return;
            }
            session.close(() => resolve());
          }),
      ),
    );
  }

  private currentProviderToken(): string {
    const now = this.now();
    if (!this.providerToken || now - this.providerToken.issuedAt > PROVIDER_TOKEN_TTL_MS) {
      this.providerToken = { value: makeProviderToken(this.config, this.key, Math.floor(now / 1000)), issuedAt: now };
    }
    return this.providerToken.value;
  }

  private session(origin: string): http2.ClientHttp2Session {
    const existing = this.sessions.get(origin);
    if (existing && !existing.closed && !existing.destroyed) return existing;
    const session = http2.connect(origin);
    const forget = () => {
      if (this.sessions.get(origin) === session) this.sessions.delete(origin);
    };
    // Ошибка соединения приходит и в каждый запрос; здесь только убираем сессию из кэша.
    session.on('error', forget);
    session.on('goaway', forget);
    session.on('close', forget);
    session.setTimeout(SESSION_IDLE_MS, () => session.close());
    this.sessions.set(origin, session);
    return session;
  }

  private request(message: PushMessage): Promise<PushResult> {
    const headers: http2.OutgoingHttpHeaders = {
      ':method': 'POST',
      ':path': `/3/device/${message.token}`,
      authorization: `bearer ${this.currentProviderToken()}`,
      'apns-topic': this.config.topic,
      'apns-push-type': 'alert',
      'apns-priority': '10',
      'content-type': 'application/json',
    };
    if (message.collapseId) headers['apns-collapse-id'] = message.collapseId;
    if (message.ttlSeconds !== undefined) {
      headers['apns-expiration'] = String(Math.floor(this.now() / 1000) + message.ttlSeconds);
    }
    const body = JSON.stringify(message.payload);

    return new Promise<PushResult>((resolve) => {
      let settled = false;
      let status = 0;
      const chunks: Buffer[] = [];
      const finish = (result: PushResult) => {
        if (settled) return;
        settled = true;
        resolve(result);
      };
      const failure = (reason: string): PushResult => ({ ok: false, status, reason, unregistered: false });

      let stream: http2.ClientHttp2Stream;
      try {
        stream = this.session(this.origins[message.env]).request(headers);
      } catch (err) {
        finish(failure(err instanceof Error ? err.message : String(err)));
        return;
      }
      stream.setTimeout(REQUEST_TIMEOUT_MS, () => {
        finish(failure('Timeout'));
        stream.close(http2.constants.NGHTTP2_CANCEL);
      });
      stream.on('response', (responseHeaders) => {
        status = Number(responseHeaders[':status'] ?? 0);
      });
      stream.on('data', (chunk: Buffer) => chunks.push(chunk));
      stream.on('end', () => {
        if (status === 200) {
          finish({ ok: true });
          return;
        }
        const reason = parseReason(Buffer.concat(chunks)) ?? `HTTP ${status}`;
        finish({ ok: false, status, reason, unregistered: status === 410 || DEAD_TOKEN_REASONS.has(reason) });
      });
      stream.on('error', (err) => finish(failure(err.message)));
      stream.on('close', () => finish(failure(status ? `HTTP ${status}` : 'ConnectionClosed')));
      stream.end(body);
    });
  }
}
