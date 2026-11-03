import type { ServerResponse } from 'node:http';
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import type { AppContext } from '../../context.js';
import { resolveLang } from '../../lib/i18n.js';
import { parseInput } from '../../lib/validation.js';
import type { Guard } from '../auth/guard.js';
import type { BusEvent } from './bus.js';
import { presentChanges } from './changes.js';
import { getRevisionInfo, listChanges } from './revision.js';

const streamQuery = z.object({ since: z.coerce.number().int().min(0).optional() });

/**
 * GET /catalog/stream — Server-Sent Events.
 * hello → catch-up `change` events after `since` / Last-Event-ID (or `reset`) → live events.
 */
export function registerCatalogStream(
  app: FastifyInstance,
  ctx: AppContext,
  guard: Guard,
  connections: Set<ServerResponse>,
): void {
  app.get('/catalog/stream', { onRequest: guard }, async (req, reply) => {
    const q = parseInput(streamQuery, req.query, 'query');
    const lastEventId = req.headers['last-event-id'];
    const fromHeader =
      typeof lastEventId === 'string' && /^\d{1,10}$/.test(lastEventId.trim()) ? Number(lastEventId.trim()) : undefined;
    const since = fromHeader ?? q.since;
    const lang = resolveLang(req.headers['accept-language']);
    const info = await getRevisionInfo(ctx.db);

    reply.hijack();
    const res = reply.raw;
    res.writeHead(200, {
      'content-type': 'text/event-stream; charset=utf-8',
      'cache-control': 'no-cache, no-transform',
      connection: 'keep-alive',
      'x-accel-buffering': 'no',
      'x-content-type-options': 'nosniff',
      'x-catalog-revision': String(info.revision),
    });

    let closed = false;
    let live = false;
    let lastSent = since ?? info.revision;
    const pending: BusEvent[] = [];
    let chain: Promise<void> = Promise.resolve();

    const write = (chunk: string) => {
      if (closed || res.writableEnded || res.destroyed) return;
      res.write(chunk);
    };
    const send = (event: string, id: number, data: unknown) => write(`id: ${id}\nevent: ${event}\ndata: ${JSON.stringify(data)}\n\n`);

    const ping = setInterval(() => write(': ping\n\n'), ctx.config.ssePingMs);
    ping.unref();

    const cleanup = () => {
      if (closed) return;
      closed = true;
      clearInterval(ping);
      unsubscribe();
      connections.delete(res);
    };

    const handle = async (ev: BusEvent) => {
      if (closed) return;
      if (ev.type === 'reset') {
        lastSent = ev.revision;
        send('reset', ev.revision, { revision: ev.revision });
        return;
      }
      if (ev.change.revision <= lastSent) return;
      const [view] = await presentChanges(ctx, [ev.change], lang);
      if (view) send('change', view.revision, view);
      lastSent = ev.change.revision;
    };
    const enqueue = (ev: BusEvent) => {
      chain = chain.then(() => handle(ev)).catch((err: unknown) => {
        req.log.warn({ err }, 'sse delivery failed');
        res.destroy();
      });
    };

    const unsubscribe = ctx.bus.subscribe((ev) => {
      if (closed) return;
      if (live) enqueue(ev);
      else pending.push(ev);
    });
    connections.add(res);
    req.raw.on('close', cleanup);
    res.on('close', cleanup);
    res.on('error', cleanup);

    try {
      send('hello', since ?? info.revision, { revision: info.revision });
      if (since !== undefined) {
        if (since < info.floor || since > info.revision) {
          send('reset', info.revision, { revision: info.revision });
        } else {
          let cursor = since;
          while (!closed && cursor < info.revision) {
            const rows = await listChanges(ctx.db, cursor, info.revision, 200);
            const last = rows.at(-1);
            if (!last) break;
            for (const view of await presentChanges(ctx, rows, lang)) send('change', view.revision, view);
            cursor = last.revision;
          }
        }
        lastSent = info.revision;
      }
      live = true;
      for (const ev of pending.splice(0)) enqueue(ev);
    } catch (err) {
      req.log.warn({ err }, 'sse catch-up failed');
      cleanup();
      res.destroy();
    }
  });
}
