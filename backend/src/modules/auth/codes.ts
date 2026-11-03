import { randomInt } from 'node:crypto';
import { sha256Hex } from '../../lib/crypto.js';

/** Unambiguous alphabet: no 0/O, 1/I/L. */
const CODE_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

/** Upper-case, without spaces and dashes. Returns null when the result cannot be a code. */
export function normalizeCode(input: string): string | null {
  const normalized = input.toUpperCase().replace(/[\s\-‐-―_]/g, '');
  return /^[A-Z0-9]{8,32}$/.test(normalized) ? normalized : null;
}

export function hashCode(normalized: string): string {
  return sha256Hex(`activation:${normalized}`);
}

/** `ABCD-EFGH-JKLM` */
export function generateCode(groups = 3, groupLength = 4): string {
  const parts: string[] = [];
  for (let g = 0; g < groups; g += 1) {
    let part = '';
    for (let i = 0; i < groupLength; i += 1) part += CODE_ALPHABET[randomInt(CODE_ALPHABET.length)];
    parts.push(part);
  }
  return parts.join('-');
}
