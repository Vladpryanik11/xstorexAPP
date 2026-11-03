#!/usr/bin/env node
// Генерирует иконку iStore 1024×1024 (PNG, RGB без альфы, как требует App Store):
// бренд-градиент по диагонали сверху справа → снизу слева и белая монограмма «i».
// Собственный PNG-энкодер на node:zlib, без зависимостей.
// Запуск: node ios/scripts/make-icon.mjs [путь/к/AppIcon.png]
import { deflateSync } from "node:zlib";
import { writeFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const SIZE = 1024;
const here = dirname(fileURLToPath(import.meta.url));
const output =
  process.argv[2] ?? join(here, "..", "iStore", "Resources", "Assets.xcassets", "AppIcon.appiconset", "AppIcon.png");

// Бренд-градиент (SPEC §3).
const stops = [
  [0.0, [0x00, 0x41, 0xdc]],
  [0.36, [0x36, 0x72, 0xe0]],
  [0.72, [0x6a, 0xa2, 0xe3]],
  [1.0, [0x92, 0xbd, 0xef]],
];

function gradientAt(t) {
  for (let i = 1; i < stops.length; i++) {
    const [t1, c1] = stops[i];
    const [t0, c0] = stops[i - 1];
    if (t <= t1) {
      const k = (t - t0) / (t1 - t0);
      return c0.map((v, j) => v + (c1[j] - v) * k);
    }
  }
  return stops[stops.length - 1][1];
}

const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));

// Монограмма «i»: капсула-ножка и точка. Геометрия совпадает с BrandMarkView.
const cx = SIZE / 2;
const stemWidth = SIZE * 0.17;
const stemTop = SIZE * 0.4;
const stemBottom = SIZE * 0.8;
const stemRadius = stemWidth / 2;
const dotRadius = (SIZE * 0.19) / 2;
const dotCenterY = SIZE * 0.17 + dotRadius;

function distanceToStem(x, y) {
  const top = stemTop + stemRadius;
  const bottom = stemBottom - stemRadius;
  const py = clamp(y, top, bottom);
  return Math.hypot(x - cx, y - py) - stemRadius;
}

function distanceToDot(x, y) {
  return Math.hypot(x - cx, y - dotCenterY) - dotRadius;
}

const rowLength = SIZE * 3 + 1;
const raw = Buffer.alloc(rowLength * SIZE);
for (let y = 0; y < SIZE; y++) {
  raw[y * rowLength] = 0; // фильтр None
  for (let x = 0; x < SIZE; x++) {
    const px = x + 0.5;
    const py = y + 0.5;
    // Проекция на диагональ от верхнего правого угла к нижнему левому.
    const t = clamp((SIZE - px + py) / (2 * SIZE), 0, 1);
    let [r, g, b] = gradientAt(t);

    // Мягкий блик сверху справа для объёма.
    const glow = Math.max(0, 1 - Math.hypot(px - SIZE * 0.85, py - SIZE * 0.1) / (SIZE * 0.75));
    r += (255 - r) * glow * 0.12;
    g += (255 - g) * glow * 0.12;
    b += (255 - b) * glow * 0.12;

    // Лёгкая тень под монограммой.
    const shadowDistance = Math.min(distanceToStem(px, py - 14), distanceToDot(px, py - 14));
    const shadow = clamp(1 - shadowDistance / 40, 0, 1) * 0.18;
    r *= 1 - shadow;
    g *= 1 - shadow;
    b *= 1 - shadow;

    // Монограмма со сглаживанием по расстоянию.
    const d = Math.min(distanceToStem(px, py), distanceToDot(px, py));
    const coverage = clamp(0.5 - d, 0, 1);
    r += (255 - r) * coverage;
    g += (255 - g) * coverage;
    b += (255 - b) * coverage;

    const offset = y * rowLength + 1 + x * 3;
    raw[offset] = Math.round(clamp(r, 0, 255));
    raw[offset + 1] = Math.round(clamp(g, 0, 255));
    raw[offset + 2] = Math.round(clamp(b, 0, 255));
  }
}

// CRC-32 для чанков PNG.
const crcTable = new Uint32Array(256);
for (let n = 0; n < 256; n++) {
  let c = n;
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  crcTable[n] = c >>> 0;
}
function crc32(buffer) {
  let c = 0xffffffff;
  for (const byte of buffer) c = crcTable[(c ^ byte) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length);
  const typeAndData = Buffer.concat([Buffer.from(type, "ascii"), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(typeAndData));
  return Buffer.concat([length, typeAndData, crc]);
}

const header = Buffer.alloc(13);
header.writeUInt32BE(SIZE, 0);
header.writeUInt32BE(SIZE, 4);
header[8] = 8; // глубина цвета
header[9] = 2; // RGB
header[10] = 0;
header[11] = 0;
header[12] = 0;

const png = Buffer.concat([
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
  chunk("IHDR", header),
  chunk("IDAT", deflateSync(raw, { level: 9 })),
  chunk("IEND", Buffer.alloc(0)),
]);

mkdirSync(dirname(output), { recursive: true });
writeFileSync(output, png);
console.log(`Wrote ${output} (${png.length} bytes, ${SIZE}x${SIZE})`);
