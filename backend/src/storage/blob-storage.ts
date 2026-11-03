import type { Readable } from 'node:stream';

export interface BlobStat {
  size: number;
  mtime: Date;
}

/**
 * Object storage for icons, screenshots and IPA files.
 *
 * Keys are `/`-separated relative paths made of `[A-Za-z0-9._-]` segments; a segment
 * may not start with a dot, so `..` and hidden files are impossible by construction.
 * Layout: `static/**` is publicly served via `/static/…`; `builds/**` holds IPAs and is
 * only reachable through install grants.
 *
 * TODO(stage 2): `S3BlobStorage` for S3-compatible storage (AWS S3, MinIO, R2):
 *  - put/putFile → PutObject (multipart upload for large IPAs);
 *  - createReadStream(range) → GetObject with `Range: bytes=start-end`;
 *  - stat → HeadObject; delete/deletePrefix → DeleteObject(s) with ListObjectsV2;
 *  - optionally serve IPAs through presigned GET URLs instead of proxying bytes.
 */
export interface BlobStorage {
  put(key: string, data: Uint8Array): Promise<void>;
  /** Moves a local file into storage (the source file is consumed). */
  putFile(key: string, sourcePath: string): Promise<void>;
  stat(key: string): Promise<BlobStat | null>;
  /** `end` is inclusive. */
  createReadStream(key: string, range?: { start: number; end: number }): Promise<Readable>;
  delete(key: string): Promise<void>;
  deletePrefix(prefix: string): Promise<void>;
}

const SEGMENT_RE = /^[A-Za-z0-9_-][A-Za-z0-9._-]{0,127}$/;

export function isValidKey(key: string): boolean {
  if (typeof key !== 'string' || key.length === 0 || key.length > 512) return false;
  return key.split('/').every((segment) => SEGMENT_RE.test(segment));
}

export class InvalidKeyError extends Error {
  constructor() {
    super('Invalid storage key');
    this.name = 'InvalidKeyError';
  }
}

export function assertValidKey(key: string): string {
  if (!isValidKey(key)) throw new InvalidKeyError();
  return key;
}
