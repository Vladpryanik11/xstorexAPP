export type Lang = 'ru' | 'en';

const SUPPORTED: readonly Lang[] = ['ru', 'en'];

/**
 * Picks the best supported language from an Accept-Language header.
 * `ru-RU,ru;q=0.9,en;q=0.8` → `ru`; anything unknown → `en`.
 */
export function resolveLang(header: string | string[] | undefined): Lang {
  const raw = Array.isArray(header) ? header.join(',') : header;
  if (!raw) return 'en';
  const candidates = raw
    .split(',')
    .slice(0, 20)
    .map((part, index) => {
      const [tag = '', ...params] = part.trim().split(';');
      let q = 1;
      for (const p of params) {
        const m = /^\s*q\s*=\s*([0-9.]+)\s*$/i.exec(p);
        if (m) q = Number.parseFloat(m[1] ?? '1');
      }
      return { tag: tag.trim().toLowerCase(), q: Number.isFinite(q) ? q : 0, index };
    })
    .filter((c) => c.tag && c.q > 0)
    .sort((a, b) => b.q - a.q || a.index - b.index);
  for (const c of candidates) {
    const base = c.tag.split(/[-_]/)[0] as Lang;
    if (SUPPORTED.includes(base)) return base;
  }
  return 'en';
}

/** Localized value with `en` fallback. */
export function pick(en: string, ru: string | null | undefined, lang: Lang): string {
  return lang === 'ru' && ru ? ru : en;
}

/** Same as pick() for optional fields: falls back to whichever language exists. */
export function pickOpt(en: string | null | undefined, ru: string | null | undefined, lang: Lang): string | null {
  if (lang === 'ru') return ru || en || null;
  return en || ru || null;
}

const LANGUAGE_NAMES: Record<string, { en: string; ru: string }> = {
  EN: { en: 'English', ru: 'Английский' },
  RU: { en: 'Russian', ru: 'Русский' },
  DE: { en: 'German', ru: 'Немецкий' },
  FR: { en: 'French', ru: 'Французский' },
  ES: { en: 'Spanish', ru: 'Испанский' },
  IT: { en: 'Italian', ru: 'Итальянский' },
  PT: { en: 'Portuguese', ru: 'Португальский' },
  TR: { en: 'Turkish', ru: 'Турецкий' },
  UK: { en: 'Ukrainian', ru: 'Украинский' },
  KK: { en: 'Kazakh', ru: 'Казахский' },
  ZH: { en: 'Chinese', ru: 'Китайский' },
  JA: { en: 'Japanese', ru: 'Японский' },
  KO: { en: 'Korean', ru: 'Корейский' },
  AR: { en: 'Arabic', ru: 'Арабский' },
};

export function languageName(code: string, lang: Lang): string {
  return LANGUAGE_NAMES[code.toUpperCase()]?.[lang] ?? code.toUpperCase();
}

/** Human-readable size in decimal megabytes, the way App Store shows it. */
export function formatSize(bytes: number, lang: Lang): string {
  const units = lang === 'ru' ? ['Б', 'КБ', 'МБ', 'ГБ'] : ['B', 'KB', 'MB', 'GB'];
  let value = bytes;
  let unit = 0;
  while (value >= 1000 && unit < units.length - 1) {
    value /= 1000;
    unit += 1;
  }
  const digits = unit === 0 || value >= 100 ? 0 : 1;
  const text = value.toFixed(digits);
  return `${lang === 'ru' ? text.replace('.', ',') : text} ${units[unit]}`;
}
