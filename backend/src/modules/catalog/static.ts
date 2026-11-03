import path from 'node:path';
import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import type { AppContext } from '../../context.js';
import { notFound } from '../../lib/errors.js';
import { ifNoneMatchMatches } from '../../lib/etag.js';
import { isValidKey } from '../../storage/blob-storage.js';

const CONTENT_TYPES: Record<string, string> = {
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.webp': 'image/webp',
  '.gif': 'image/gif',
};

/** Public images from storage (`static/**` only; IPAs live elsewhere). */
export async function staticRoutes(app: FastifyInstance, opts: { ctx: AppContext }) {
  const { ctx } = opts;
  const serveStatic = async (req: FastifyRequest, reply: FastifyReply) => {
    const rel = (req.params as { '*'?: string })['*'] ?? '';
    const key = `static/${rel}`;
    if (!isValidKey(key)) throw notFound();
    const stat = await ctx.storage.stat(key);
    if (!stat) throw notFound();

    const etag = `"${stat.size.toString(16)}-${stat.mtime.getTime().toString(16)}"`;
    void reply.header('etag', etag);
    void reply.header('cache-control', 'public, max-age=86400');
    void reply.type(CONTENT_TYPES[path.extname(key).toLowerCase()] ?? 'application/octet-stream');
    if (ifNoneMatchMatches(req.headers['if-none-match'], etag)) return reply.code(304).send();
    void reply.header('content-length', stat.size);
    if (req.method === 'HEAD') return reply.send();
    return reply.send(await ctx.storage.createReadStream(key));
  };
  app.route({ method: ['GET', 'HEAD'], url: '/static/*', handler: serveStatic });
}
