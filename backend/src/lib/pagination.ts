import { z } from 'zod';
import { invalidRequest } from './errors.js';

export const DEFAULT_LIMIT = 20;
export const MAX_LIMIT = 50;

export const pageQuerySchema = z.object({
  cursor: z.string().min(1).max(256).optional(),
  limit: z.coerce.number().int().min(1).max(MAX_LIMIT).default(DEFAULT_LIMIT),
});

const MAX_OFFSET = 1_000_000;

/** Opaque cursor: base64url JSON `{"o": offset}`. */
export function encodeCursor(offset: number): string {
  return Buffer.from(JSON.stringify({ o: offset }), 'utf8').toString('base64url');
}

export function decodeCursor(cursor: string | undefined): number {
  if (cursor === undefined) return 0;
  try {
    if (!/^[A-Za-z0-9_-]+$/.test(cursor)) throw new Error('bad charset');
    const parsed: unknown = JSON.parse(Buffer.from(cursor, 'base64url').toString('utf8'));
    const o = (parsed as { o?: unknown }).o;
    if (typeof o === 'number' && Number.isInteger(o) && o >= 0 && o <= MAX_OFFSET) return o;
  } catch {
    // fallthrough
  }
  throw invalidRequest('cursor is malformed');
}

export interface Page<T> {
  items: T[];
  next_cursor: string | null;
}

/** `rows` must be fetched with `limit + 1` to detect the next page. */
export function toPage<T>(rows: T[], offset: number, limit: number): Page<T> {
  const hasMore = rows.length > limit;
  return {
    items: hasMore ? rows.slice(0, limit) : rows,
    next_cursor: hasMore ? encodeCursor(offset + limit) : null,
  };
}
