import type { AppContext } from '../../context.js';
import type { AccountRow, PlanRow } from '../../db/schema.js';
import { pick, type Lang } from '../../lib/i18n.js';
import { iso } from '../catalog/present.js';

export type AccountStatus = 'active' | 'expired' | 'suspended';

export interface AccountView {
  id: string;
  display_name: string | null;
  plan: { id: string; name: string; period_months: number };
  status: AccountStatus;
  expires_at: string | null;
  renew_url: string | null;
  created_at: string;
}

export function accountStatus(account: AccountRow, now: Date): AccountStatus {
  if (account.status === 'suspended') return 'suspended';
  if (account.expiresAt && account.expiresAt.getTime() <= now.getTime()) return 'expired';
  return 'active';
}

export function accountView(ctx: AppContext, account: AccountRow, plan: PlanRow, lang: Lang): AccountView {
  const renew = ctx.config.renewUrl;
  return {
    id: account.id,
    display_name: account.displayName,
    plan: { id: plan.id, name: pick(plan.nameEn, plan.nameRu, lang), period_months: plan.periodMonths },
    status: accountStatus(account, ctx.now()),
    expires_at: account.expiresAt ? iso(account.expiresAt) : null,
    renew_url: renew ? `${renew}${renew.includes('?') ? '&' : '?'}acc=${encodeURIComponent(account.id)}` : null,
    created_at: iso(account.createdAt),
  };
}
