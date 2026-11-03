import { EventEmitter } from 'node:events';
import type { FastifyBaseLogger } from 'fastify';
import type { Db } from '../../db/index.js';
import { getRevisionInfo, listChanges, type ChangeRow } from './revision.js';

export type BusEvent = { type: 'change'; change: ChangeRow } | { type: 'reset'; revision: number };

/**
 * Fan-out of committed catalog changes to SSE connections.
 * Writers call notify() after commit; the bus re-reads the journal past the last
 * broadcast revision, so events always go out once and in revision order.
 */
export class CatalogBus {
  private readonly emitter = new EventEmitter();
  private lastBroadcast: number | null = null;
  private chain: Promise<void> = Promise.resolve();
  private pollTimer: NodeJS.Timeout | null = null;

  constructor(
    private readonly db: Db,
    private readonly log: FastifyBaseLogger | null = null,
  ) {
    this.emitter.setMaxListeners(0);
  }

  async init(): Promise<void> {
    this.lastBroadcast = (await getRevisionInfo(this.db)).revision;
  }

  subscribe(listener: (event: BusEvent) => void): () => void {
    this.emitter.on('event', listener);
    return () => {
      this.emitter.off('event', listener);
    };
  }

  get subscriberCount(): number {
    return this.emitter.listenerCount('event');
  }

  /** Broadcasts everything committed since the last call. Resolves when done. */
  notify(): Promise<void> {
    this.chain = this.chain.then(
      () => this.pump(),
      () => this.pump(),
    );
    return this.chain.catch((err: unknown) => {
      this.log?.error({ err }, 'catalog bus pump failed');
    });
  }

  /** Periodic re-check (useful with several API instances sharing one database). */
  startPolling(intervalMs: number): void {
    if (intervalMs <= 0 || this.pollTimer) return;
    this.pollTimer = setInterval(() => {
      if (this.subscriberCount > 0) void this.notify();
    }, intervalMs);
    this.pollTimer.unref();
  }

  stop(): void {
    if (this.pollTimer) clearInterval(this.pollTimer);
    this.pollTimer = null;
    this.emitter.removeAllListeners();
  }

  private async pump(): Promise<void> {
    if (this.lastBroadcast === null) await this.init();
    const info = await getRevisionInfo(this.db);
    let last = this.lastBroadcast ?? 0;
    if (info.revision < last || info.floor > last) {
      // Journal was reset (e.g. reseeded DB) or pruned past us: tell clients to reload.
      this.lastBroadcast = info.revision;
      this.emitter.emit('event', { type: 'reset', revision: info.revision } satisfies BusEvent);
      return;
    }
    while (last < info.revision) {
      const rows = await listChanges(this.db, last, info.revision, 500);
      if (rows.length === 0) break;
      for (const change of rows) {
        this.emitter.emit('event', { type: 'change', change } satisfies BusEvent);
        last = change.revision;
      }
    }
    this.lastBroadcast = Math.max(last, info.revision);
  }
}
