import { createHash } from 'node:crypto';
import type { FastifyReply, FastifyRequest } from 'fastify';

/** Strong ETag derived from the serialized body. */
export function computeEtag(payload: string | Uint8Array): string {
  return `"${createHash('sha256').update(payload).digest('base64url').slice(0, 32)}"`;
}

/** True when If-None-Match matches the given ETag (weak comparison, RFC 9110 §13.1.2). */
export function ifNoneMatchMatches(header: string | string[] | undefined, etag: string): boolean {
  if (!header) return false;
  const raw = Array.isArray(header) ? header.join(',') : header;
  if (raw.trim() === '*') return true;
  const strip = (t: string) => t.trim().replace(/^W\//, '');
  const target = strip(etag);
  return raw.split(',').some((t) => strip(t) === target);
}

/**
 * Sends a JSON body with ETag; answers 304 when the client already has it.
 * Catalog responses depend on Accept-Language and the caller, hence Vary.
 */
export function sendJsonWithEtag(req: FastifyRequest, reply: FastifyReply, body: unknown): FastifyReply {
  const json = JSON.stringify(body);
  const etag = computeEtag(json);
  void reply.header('etag', etag);
  void reply.header('cache-control', 'private, no-cache');
  void reply.header('vary', 'Accept-Language, Authorization');
  if (ifNoneMatchMatches(req.headers['if-none-match'], etag)) {
    return reply.code(304).send();
  }
  return reply.type('application/json; charset=utf-8').send(json);
}
