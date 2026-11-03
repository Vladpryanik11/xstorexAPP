import { eq } from 'drizzle-orm';
import type { AppContext } from '../../context.js';
import { activationCodes, plans } from '../../db/schema.js';
import { newId } from '../../lib/crypto.js';
import { invalidRequest } from '../../lib/errors.js';
import { generateCode, hashCode, normalizeCode } from '../auth/codes.js';

/** Stores a code (hash only). Returns false when the same code already exists. */
export async function insertActivationCode(
  ctx: AppContext,
  plain: string,
  planId: string,
  durationDays: number | null = null,
): Promise<boolean> {
  const normalized = normalizeCode(plain);
  if (!normalized) throw invalidRequest('activation code has an invalid format');
  const rows = await ctx.db
    .insert(activationCodes)
    .values({
      id: newId('code'),
      codeHash: hashCode(normalized),
      codeHint: normalized.slice(-4),
      planId,
      durationDays,
    })
    .onConflictDoNothing()
    .returning({ id: activationCodes.id });
  return rows.length > 0;
}

export async function createActivationCodes(
  ctx: AppContext,
  count: number,
  planId: string,
  durationDays: number | null = null,
): Promise<string[]> {
  const [plan] = await ctx.db.select({ id: plans.id }).from(plans).where(eq(plans.id, planId));
  if (!plan) throw invalidRequest(`unknown plan_id "${planId}"`);
  const codes: string[] = [];
  while (codes.length < count) {
    const code = generateCode();
    if (await insertActivationCode(ctx, code, planId, durationDays)) codes.push(code);
  }
  return codes;
}
