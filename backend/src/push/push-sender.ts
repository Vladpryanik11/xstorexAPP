export type ApnsEnv = 'sandbox' | 'production';

export interface PushMessage {
  /** Токен устройства APNs, hex. */
  token: string;
  env: ApnsEnv;
  payload: Record<string, unknown>;
  /** Уведомление с тем же collapse id заменяет на устройстве предыдущее. */
  collapseId?: string;
  /** Сколько секунд APNs хранит уведомление, пока устройство недоступно. */
  ttlSeconds?: number;
}

export type PushResult =
  | { ok: true }
  | {
      ok: false;
      /** HTTP-статус APNs; 0 — ответа не было (сеть, таймаут). */
      status: number;
      reason: string;
      /** Токен больше не действует, его нужно удалить. */
      unregistered: boolean;
    };

/** Канал доставки push. В продакшене — APNs, в тестах — подмена. */
export interface PushSender {
  readonly enabled: boolean;
  send(message: PushMessage): Promise<PushResult>;
  close(): Promise<void>;
}

/** APNs не настроен: уведомления не отправляются. */
export class DisabledPushSender implements PushSender {
  readonly enabled = false;

  async send(): Promise<PushResult> {
    return { ok: false, status: 0, reason: 'PushDisabled', unregistered: false };
  }

  async close(): Promise<void> {}
}
