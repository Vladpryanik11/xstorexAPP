export interface ByteRange {
  start: number;
  /** inclusive */
  end: number;
}

export type RangeResult = { kind: 'full' } | { kind: 'partial'; range: ByteRange } | { kind: 'unsatisfiable' };

/**
 * Parses a single-range `Range: bytes=…` header (RFC 9110 §14).
 * Multi-range and malformed headers are ignored (full response), which the RFC allows.
 */
export function parseRange(header: string | undefined, size: number): RangeResult {
  if (!header) return { kind: 'full' };
  const m = /^\s*bytes\s*=\s*(\d*)\s*-\s*(\d*)\s*$/i.exec(header);
  if (!m) return { kind: 'full' };
  const [, startRaw = '', endRaw = ''] = m;
  if (startRaw === '' && endRaw === '') return { kind: 'full' };

  if (startRaw === '') {
    // suffix: last N bytes
    const suffix = Number(endRaw);
    if (!Number.isSafeInteger(suffix)) return { kind: 'full' };
    if (suffix === 0 || size === 0) return { kind: 'unsatisfiable' };
    return { kind: 'partial', range: { start: Math.max(0, size - suffix), end: size - 1 } };
  }

  const start = Number(startRaw);
  if (!Number.isSafeInteger(start)) return { kind: 'full' };
  let end = endRaw === '' ? Number.MAX_SAFE_INTEGER : Number(endRaw);
  if (!Number.isSafeInteger(end)) return { kind: 'full' };
  if (end < start) return { kind: 'full' };
  if (start >= size) return { kind: 'unsatisfiable' };
  end = Math.min(end, size - 1);
  return { kind: 'partial', range: { start, end } };
}
