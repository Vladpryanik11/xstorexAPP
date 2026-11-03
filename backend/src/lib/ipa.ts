import yauzl from 'yauzl';
import { parsePlistBuffer } from './plist.js';

export interface IpaInfo {
  /** e.g. `Payload/Demo.app` */
  appPath: string;
  bundleId: string;
  shortVersion: string | null;
  bundleVersion: string | null;
  minOs: string | null;
  displayName: string | null;
}

export class IpaError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'IpaError';
  }
}

const INFO_PLIST_RE = /^Payload\/([^/]+\.app)\/Info\.plist$/;
const MAX_INFO_PLIST_BYTES = 1024 * 1024;
const BUNDLE_ID_RE = /^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$/;

async function readLimited(stream: NodeJS.ReadableStream, limit: number): Promise<Buffer> {
  const chunks: Buffer[] = [];
  let total = 0;
  for await (const chunk of stream as AsyncIterable<Buffer>) {
    total += chunk.length;
    if (total > limit) throw new IpaError('Info.plist is too large');
    chunks.push(chunk);
  }
  return Buffer.concat(chunks);
}

function str(v: unknown): string | null {
  return typeof v === 'string' && v.trim() !== '' ? v.trim() : null;
}

/**
 * Reads `Payload/*.app/Info.plist` from an IPA (zip) on disk.
 * Uses the central directory, so large IPAs are not loaded into memory.
 */
export async function readIpaInfo(filePath: string): Promise<IpaInfo> {
  let zip: yauzl.ZipFile;
  try {
    zip = await yauzl.openPromise(filePath, { lazyEntries: true, autoClose: false, validateEntrySizes: true });
  } catch {
    throw new IpaError('File is not a valid zip archive');
  }
  try {
    for await (const entry of zip.eachEntry()) {
      const m = INFO_PLIST_RE.exec(entry.fileName);
      if (!m) continue;
      if (entry.uncompressedSize > MAX_INFO_PLIST_BYTES) throw new IpaError('Info.plist is too large');
      const stream = await zip.openReadStreamPromise(entry);
      const data = await readLimited(stream, MAX_INFO_PLIST_BYTES);
      let plist: unknown;
      try {
        plist = parsePlistBuffer(data);
      } catch {
        throw new IpaError('Info.plist cannot be parsed');
      }
      if (!plist || typeof plist !== 'object' || Array.isArray(plist)) {
        throw new IpaError('Info.plist root must be a dictionary');
      }
      const dict = plist as Record<string, unknown>;
      const bundleId = str(dict.CFBundleIdentifier);
      if (!bundleId || !BUNDLE_ID_RE.test(bundleId) || bundleId.length > 155) {
        throw new IpaError('CFBundleIdentifier is missing or invalid');
      }
      return {
        appPath: `Payload/${m[1]}`,
        bundleId,
        shortVersion: str(dict.CFBundleShortVersionString),
        bundleVersion: str(dict.CFBundleVersion),
        minOs: str(dict.MinimumOSVersion),
        displayName: str(dict.CFBundleDisplayName) ?? str(dict.CFBundleName),
      };
    }
  } catch (err) {
    if (err instanceof IpaError) throw err;
    throw new IpaError('IPA archive is corrupted');
  } finally {
    zip.close();
  }
  throw new IpaError('Payload/*.app/Info.plist not found');
}
