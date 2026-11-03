import { createReadStream } from 'node:fs';
import { copyFile, mkdir, rename, rm, stat, unlink, writeFile } from 'node:fs/promises';
import path from 'node:path';
import type { Readable } from 'node:stream';
import { randomBytes } from 'node:crypto';
import { assertValidKey, InvalidKeyError, type BlobStat, type BlobStorage } from './blob-storage.js';

/** BlobStorage on the local filesystem (dev and single-node deployments). */
export class LocalBlobStorage implements BlobStorage {
  readonly root: string;

  constructor(root: string) {
    this.root = path.resolve(root);
  }

  /** Resolves a key to an absolute path inside root; rejects anything that escapes it. */
  resolve(key: string): string {
    assertValidKey(key);
    const full = path.resolve(this.root, ...key.split('/'));
    if (!full.startsWith(this.root + path.sep)) throw new InvalidKeyError();
    return full;
  }

  async put(key: string, data: Uint8Array): Promise<void> {
    const target = this.resolve(key);
    await mkdir(path.dirname(target), { recursive: true });
    const tmp = `${target}.${randomBytes(6).toString('hex')}.part`;
    await writeFile(tmp, data);
    await rename(tmp, target);
  }

  async putFile(key: string, sourcePath: string): Promise<void> {
    const target = this.resolve(key);
    await mkdir(path.dirname(target), { recursive: true });
    try {
      await rename(sourcePath, target);
    } catch (err) {
      if ((err as NodeJS.ErrnoException).code !== 'EXDEV') throw err;
      await copyFile(sourcePath, target);
      await unlink(sourcePath);
    }
  }

  async stat(key: string): Promise<BlobStat | null> {
    try {
      const s = await stat(this.resolve(key));
      return s.isFile() ? { size: s.size, mtime: s.mtime } : null;
    } catch (err) {
      if (err instanceof InvalidKeyError) return null;
      if ((err as NodeJS.ErrnoException).code === 'ENOENT') return null;
      throw err;
    }
  }

  async createReadStream(key: string, range?: { start: number; end: number }): Promise<Readable> {
    const file = this.resolve(key);
    return range ? createReadStream(file, { start: range.start, end: range.end }) : createReadStream(file);
  }

  async delete(key: string): Promise<void> {
    await rm(this.resolve(key), { force: true });
  }

  async deletePrefix(prefix: string): Promise<void> {
    await rm(this.resolve(prefix), { recursive: true, force: true });
  }
}
