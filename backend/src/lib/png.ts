import { crc32, deflateSync } from 'node:zlib';

const SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

function chunk(type: string, data: Uint8Array): Buffer {
  const typeBuf = Buffer.from(type, 'ascii');
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length, 0);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(Buffer.concat([typeBuf, data])) >>> 0, 0);
  return Buffer.concat([len, typeBuf, data, crc]);
}

function paeth(a: number, b: number, c: number): number {
  const p = a + b - c;
  const pa = Math.abs(p - a);
  const pb = Math.abs(p - b);
  const pc = Math.abs(p - c);
  if (pa <= pb && pa <= pc) return a;
  return pb <= pc ? b : c;
}

/**
 * Minimal PNG encoder (8-bit RGB or RGBA, Paeth filter, zlib deflate).
 * `pixels` is row-major, `channels` bytes per pixel.
 */
export function encodePng(width: number, height: number, pixels: Uint8Array, channels: 3 | 4 = 3): Buffer {
  if (!Number.isInteger(width) || !Number.isInteger(height) || width <= 0 || height <= 0) {
    throw new RangeError('PNG dimensions must be positive integers');
  }
  const stride = width * channels;
  if (pixels.length !== stride * height) throw new RangeError('pixel buffer size mismatch');

  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = channels === 4 ? 6 : 2; // color type: RGBA / RGB
  ihdr[10] = 0; // compression
  ihdr[11] = 0; // filter method
  ihdr[12] = 0; // no interlace

  const raw = Buffer.alloc((stride + 1) * height);
  for (let y = 0; y < height; y += 1) {
    const rowIn = y * stride;
    const rowOut = y * (stride + 1);
    raw[rowOut] = 4; // Paeth
    for (let i = 0; i < stride; i += 1) {
      const x = pixels[rowIn + i]!;
      const a = i >= channels ? pixels[rowIn + i - channels]! : 0;
      const b = y > 0 ? pixels[rowIn - stride + i]! : 0;
      const c = y > 0 && i >= channels ? pixels[rowIn - stride + i - channels]! : 0;
      raw[rowOut + 1 + i] = (x - paeth(a, b, c)) & 0xff;
    }
  }

  return Buffer.concat([
    SIGNATURE,
    chunk('IHDR', ihdr),
    chunk('IDAT', deflateSync(raw, { level: 6 })),
    chunk('IEND', new Uint8Array(0)),
  ]);
}

/** Reads width/height from a PNG header (for tests and sanity checks). */
export function readPngSize(buf: Uint8Array): { width: number; height: number } | null {
  const b = Buffer.from(buf.buffer, buf.byteOffset, buf.byteLength);
  if (b.length < 24 || !b.subarray(0, 8).equals(SIGNATURE) || b.toString('ascii', 12, 16) !== 'IHDR') return null;
  return { width: b.readUInt32BE(16), height: b.readUInt32BE(20) };
}
