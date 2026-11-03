import { createHash, createHmac, randomBytes, randomInt, timingSafeEqual } from 'node:crypto';

export function sha256Hex(data: string | Uint8Array): string {
  return createHash('sha256').update(data).digest('hex');
}

/** 32 random bytes, base64url (43 chars). */
export function randomToken(): string {
  return randomBytes(32).toString('base64url');
}

const ID_ALPHABET = 'abcdefghijkmnpqrstuvwxyz23456789';

/** Random id like `app_7f3k2m9qxa`. */
export function newId(prefix: string, length = 12): string {
  let out = '';
  for (let i = 0; i < length; i += 1) out += ID_ALPHABET[randomInt(ID_ALPHABET.length)];
  return `${prefix}_${out}`;
}

/** Constant-time string comparison (hashes both sides so lengths do not leak). */
export function safeEqual(a: string, b: string): boolean {
  const ha = createHash('sha256').update(a).digest();
  const hb = createHash('sha256').update(b).digest();
  return timingSafeEqual(ha, hb);
}

export function hmacBase64url(secret: string, data: string): string {
  return createHmac('sha256', secret).update(data).digest('base64url');
}
