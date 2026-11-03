/**
 * Сравнивает версии вида `3.2.0` по числовым частям: `1.10` > `1.9`, `2.0` == `2`.
 * Нечисловая часть считается нулём. Возвращает -1, 0 или 1.
 */
export function compareVersions(a: string, b: string): number {
  const pa = a.split('.').map(toPart);
  const pb = b.split('.').map(toPart);
  for (let i = 0; i < Math.max(pa.length, pb.length); i += 1) {
    const x = pa[i] ?? 0;
    const y = pb[i] ?? 0;
    if (x !== y) return x > y ? 1 : -1;
  }
  return 0;
}

function toPart(part: string): number {
  const n = Number.parseInt(part, 10);
  return Number.isFinite(n) && n >= 0 ? n : 0;
}
