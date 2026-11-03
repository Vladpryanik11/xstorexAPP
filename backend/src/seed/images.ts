import { encodePng } from '../lib/png.js';

type RGB = [number, number, number];
export type Shape = 'circle' | 'ring' | 'triangle' | 'diamond' | 'square' | 'plus';
type Sdf = (x: number, y: number) => number;

export function hexToRgb(hex: string): RGB {
  const v = Number.parseInt(hex.replace('#', ''), 16);
  return [(v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff];
}

const mix = (a: RGB, b: RGB, t: number): RGB => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];
const WHITE: RGB = [255, 255, 255];

class Raster {
  readonly data: Uint8Array;
  constructor(
    readonly w: number,
    readonly h: number,
  ) {
    this.data = new Uint8Array(w * h * 3);
  }

  /** Linear gradient from `from` at (x0,y0) to `to` at (x1,y1), coordinates in 0..1. */
  gradient(from: RGB, to: RGB, x0: number, y0: number, x1: number, y1: number): void {
    const dx = (x1 - x0) * this.w;
    const dy = (y1 - y0) * this.h;
    const len2 = dx * dx + dy * dy || 1;
    for (let y = 0; y < this.h; y += 1) {
      for (let x = 0; x < this.w; x += 1) {
        const t = Math.min(1, Math.max(0, ((x - x0 * this.w) * dx + (y - y0 * this.h) * dy) / len2));
        const i = (y * this.w + x) * 3;
        this.data[i] = from[0] + (to[0] - from[0]) * t;
        this.data[i + 1] = from[1] + (to[1] - from[1]) * t;
        this.data[i + 2] = from[2] + (to[2] - from[2]) * t;
      }
    }
  }

  /** Fills an SDF shape with anti-aliased edges, limited to a bounding box. */
  fill(sdf: Sdf, color: RGB, alpha: number, box: [number, number, number, number]): void {
    const [bx0, by0, bx1, by1] = box.map((v) => Math.round(v)) as [number, number, number, number];
    for (let y = Math.max(0, by0); y < Math.min(this.h, by1); y += 1) {
      for (let x = Math.max(0, bx0); x < Math.min(this.w, bx1); x += 1) {
        const cov = Math.min(1, Math.max(0, 0.5 - sdf(x + 0.5, y + 0.5))) * alpha;
        if (cov <= 0) continue;
        const i = (y * this.w + x) * 3;
        this.data[i] = this.data[i]! + (color[0] - this.data[i]!) * cov;
        this.data[i + 1] = this.data[i + 1]! + (color[1] - this.data[i + 1]!) * cov;
        this.data[i + 2] = this.data[i + 2]! + (color[2] - this.data[i + 2]!) * cov;
      }
    }
  }

  rect(cx: number, cy: number, hw: number, hh: number, rad: number, color: RGB, alpha: number): void {
    this.fill(roundRect(cx, cy, hw, hh, rad), color, alpha, [cx - hw - 2, cy - hh - 2, cx + hw + 2, cy + hh + 2]);
  }

  disc(cx: number, cy: number, r: number, color: RGB, alpha: number): void {
    this.fill(circle(cx, cy, r), color, alpha, [cx - r - 2, cy - r - 2, cx + r + 2, cy + r + 2]);
  }

  annulus(cx: number, cy: number, r: number, w: number, color: RGB, alpha: number): void {
    const o = r + w;
    this.fill(ring(cx, cy, r, w), color, alpha, [cx - o - 2, cy - o - 2, cx + o + 2, cy + o + 2]);
  }

  png(): Buffer {
    return encodePng(this.w, this.h, this.data, 3);
  }
}

const circle = (cx: number, cy: number, r: number): Sdf => (x, y) => Math.hypot(x - cx, y - cy) - r;
const ring = (cx: number, cy: number, r: number, w: number): Sdf => (x, y) => Math.abs(Math.hypot(x - cx, y - cy) - r) - w / 2;
const roundRect =
  (cx: number, cy: number, hw: number, hh: number, rad: number): Sdf =>
  (x, y) => {
    const qx = Math.abs(x - cx) - hw + rad;
    const qy = Math.abs(y - cy) - hh + rad;
    return Math.hypot(Math.max(qx, 0), Math.max(qy, 0)) + Math.min(Math.max(qx, qy), 0) - rad;
  };
const diamond = (cx: number, cy: number, r: number): Sdf => (x, y) => (Math.abs(x - cx) + Math.abs(y - cy) - r) / Math.SQRT2;
const triangle =
  (cx: number, cy: number, r: number): Sdf =>
  (x, y) => {
    // Equilateral triangle SDF (Inigo Quilez), y axis pointing up.
    const k = Math.sqrt(3);
    let px = Math.abs(x - cx) - r;
    let py = -(y - cy) + r / k;
    if (px + k * py > 0) {
      const nx = (px - k * py) / 2;
      const ny = (-k * px - py) / 2;
      px = nx;
      py = ny;
    }
    px -= Math.min(Math.max(px, -2 * r), 0);
    return -Math.hypot(px, py) * Math.sign(py);
  };
const plus =
  (cx: number, cy: number, r: number): Sdf =>
  (x, y) =>
    Math.min(roundRect(cx, cy, r, r * 0.34, r * 0.12)(x, y), roundRect(cx, cy, r * 0.34, r, r * 0.12)(x, y));

function shapeSdf(shape: Shape, cx: number, cy: number, r: number): Sdf {
  switch (shape) {
    case 'circle':
      return circle(cx, cy, r);
    case 'ring':
      return ring(cx, cy, r * 0.8, r * 0.36);
    case 'triangle':
      return triangle(cx, cy + r * 0.12, r * 1.05);
    case 'diamond':
      return diamond(cx, cy, r * 1.1);
    case 'square':
      return roundRect(cx, cy, r * 0.85, r * 0.85, r * 0.22);
    case 'plus':
      return plus(cx, cy, r);
  }
}

function drawShape(img: Raster, shape: Shape, cx: number, cy: number, r: number, color: RGB, alpha = 1): void {
  const pad = r * 1.4;
  img.fill(shapeSdf(shape, cx, cy, r), color, alpha, [cx - pad, cy - pad, cx + pad, cy + pad]);
}

export interface Palette {
  tintLight: string;
  tintDark: string;
  bgColor: string;
}

/** App icon: diagonal gradient tint_light → bg_color with a light geometric mark. */
export function renderIcon(size: number, p: Palette, shape: Shape): Buffer {
  const tint = hexToRgb(p.tintLight);
  const bg = hexToRgb(p.bgColor);
  const img = new Raster(size, size);
  img.gradient(tint, mix(tint, bg, 0.6), 0, 0, 1, 1);
  const c = size / 2;
  drawShape(img, shape, c, c, size * 0.27, bg, 0.96);
  img.fill(circle(size * 0.74, size * 0.26, size * 0.07), hexToRgb(p.tintDark), 0.9, [size * 0.6, size * 0.12, size * 0.88, size * 0.4]);
  return img.png();
}

/** Wide 16:9 hero artwork. */
export function renderHero(width: number, height: number, gradient: [string, string], shape: Shape): Buffer {
  const a = hexToRgb(gradient[0]);
  const b = hexToRgb(gradient[1]);
  const img = new Raster(width, height);
  img.gradient(a, b, 1, 0, 0, 1); // top-right → bottom-left, like the brand gradient
  const decor: [number, number, number, number][] = [
    [0.12, 0.2, 0.18, 0.1],
    [0.32, 0.85, 0.24, 0.08],
    [0.55, 0.12, 0.1, 0.14],
  ];
  for (const [x, y, r, alpha] of decor) {
    img.disc(x * width, y * height, r * height, WHITE, alpha);
  }
  drawShape(img, shape, width * 0.72, height * 0.5, height * 0.26, WHITE, 0.92);
  return img.png();
}

/** Phone-sized screenshot with a simple UI mock in the app colors. */
export function renderScreenshot(width: number, height: number, p: Palette, shape: Shape, variant: number): Buffer {
  const tint = hexToRgb(p.tintLight);
  const dark = hexToRgb(p.tintDark);
  const bg = hexToRgb(p.bgColor);
  const img = new Raster(width, height);
  img.gradient(bg, mix(bg, tint, 0.35), 0, 0, 0, 1);
  const m = width * 0.06;
  // navigation bar
  img.rect(width / 2, height * 0.06, width / 2 - m, height * 0.018, height * 0.009, tint, 0.25);
  if (variant % 3 === 0) {
    img.rect(width / 2, height * 0.25, width / 2 - m, height * 0.13, width * 0.06, tint, 1);
    drawShape(img, shape, width / 2, height * 0.25, height * 0.07, WHITE, 0.95);
    for (let i = 0; i < 4; i += 1) {
      const y = height * (0.47 + i * 0.12);
      img.rect(width / 2, y, width / 2 - m, height * 0.045, width * 0.04, WHITE, 0.85);
      img.disc(m + width * 0.1, y, height * 0.022, i % 2 ? dark : tint, 1);
    }
  } else if (variant % 3 === 1) {
    for (let row = 0; row < 3; row += 1) {
      for (let col = 0; col < 2; col += 1) {
        const cx = width * (0.29 + col * 0.42);
        const cy = height * (0.24 + row * 0.24);
        img.rect(cx, cy, width * 0.18, height * 0.1, width * 0.05, WHITE, 0.88);
        drawShape(img, shape, cx, cy, width * 0.08, (row + col) % 2 ? tint : dark, 0.95);
      }
    }
  } else {
    drawShape(img, shape, width / 2, height * 0.38, width * 0.3, tint, 1);
    img.annulus(width / 2, height * 0.38, width * 0.42, width * 0.02, dark, 0.6);
    img.rect(width / 2, height * 0.72, width / 2 - m * 2, height * 0.012, height * 0.006, dark, 0.7);
    img.rect(width / 2, height * 0.76, width / 2 - m * 3, height * 0.01, height * 0.005, dark, 0.4);
    img.rect(width / 2, height * 0.87, width * 0.3, height * 0.032, height * 0.032, tint, 1);
  }
  return img.png();
}
