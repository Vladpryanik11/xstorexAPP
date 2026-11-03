import { z } from 'zod';
import { invalidRequest } from './errors.js';

/** Parses input with a zod schema; failures become `400 invalid_request`. */
export function parseInput<T extends z.ZodType>(schema: T, data: unknown, where: 'body' | 'query' | 'params'): z.infer<T> {
  const result = schema.safeParse(data ?? {});
  if (result.success) return result.data;
  const detail = result.error.issues
    .slice(0, 3)
    .map((i) => `${[where, ...i.path].join('.')}: ${i.message}`)
    .join('; ');
  throw invalidRequest(detail);
}

export const hexColor = z.string().regex(/^#[0-9A-Fa-f]{6}$/, 'expected #RRGGBB');

export const appIdSchema = z.string().regex(/^app_[a-z0-9_]{2,48}$/, 'expected app id');

/** Plain string, or `{en, ru}` with at least one language. */
export function localizedInput(max: number) {
  return z.union([
    z.string().trim().min(1).max(max),
    z
      .object({
        en: z.string().trim().min(1).max(max).optional(),
        ru: z.string().trim().min(1).max(max).optional(),
      })
      .strict()
      .refine((v) => Boolean(v.en || v.ru), 'en or ru is required'),
  ]);
}

export type LocalizedInput = string | { en?: string | undefined; ru?: string | undefined };

/** Normalizes localized input to `{en, ru}` where `en` is always set. */
export function toLocalized(v: LocalizedInput): { en: string; ru: string | null } {
  if (typeof v === 'string') return { en: v, ru: null };
  const en = v.en ?? v.ru ?? '';
  return { en, ru: v.ru ?? null };
}

export function toLocalizedOpt(v: LocalizedInput | null | undefined): { en: string | null; ru: string | null } {
  if (v === null || v === undefined) return { en: null, ru: null };
  return toLocalized(v);
}
