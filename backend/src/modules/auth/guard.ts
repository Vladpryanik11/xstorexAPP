import { and, eq, isNull } from 'drizzle-orm';
import type { FastifyReply, FastifyRequest } from 'fastify';
import type { AppContext } from '../../context.js';
import { accounts, devices, plans, tokens, type AccountRow, type DeviceRow, type PlanRow } from '../../db/schema.js';
import { sha256Hex } from '../../lib/crypto.js';
import { accountInactive, unauthorized } from '../../lib/errors.js';
import { accountStatus } from './account.js';

export interface AuthContext {
  tokenId: string;
  account: AccountRow;
  plan: PlanRow;
  device: DeviceRow;
}

declare module 'fastify' {
  interface FastifyRequest {
    auth: AuthContext | null;
  }
}

const BEARER_RE = /^Bearer\s+([A-Za-z0-9_-]{20,128})\s*$/i;
const TOUCH_INTERVAL_MS = 60_000;

export type Guard = (req: FastifyRequest, reply: FastifyReply) => Promise<void>;

export function createGuards(ctx: AppContext): { requireAuth: Guard; requireActive: Guard } {
  async function authenticate(req: FastifyRequest): Promise<AuthContext> {
    const header = req.headers.authorization;
    const match = typeof header === 'string' ? BEARER_RE.exec(header) : null;
    if (!match?.[1]) throw unauthorized();
    const [row] = await ctx.db
      .select({ tokenId: tokens.id, account: accounts, plan: plans, device: devices })
      .from(tokens)
      .innerJoin(accounts, eq(tokens.accountId, accounts.id))
      .innerJoin(plans, eq(accounts.planId, plans.id))
      .innerJoin(devices, eq(tokens.deviceId, devices.id))
      .where(and(eq(tokens.tokenHash, sha256Hex(match[1])), isNull(tokens.revokedAt)))
      .limit(1);
    if (!row) throw unauthorized();

    // Remember the device's last activity and client build, at most once a minute.
    const now = ctx.now();
    const buildHeader = req.headers['x-client-build'];
    const build = typeof buildHeader === 'string' && /^[0-9A-Za-z.\-]{1,32}$/.test(buildHeader) ? buildHeader : null;
    const stale = !row.device.lastSeenAt || now.getTime() - row.device.lastSeenAt.getTime() > TOUCH_INTERVAL_MS;
    if (stale || (build && build !== row.device.appBuild)) {
      const patch = { lastSeenAt: now, ...(build ? { appBuild: build } : {}) };
      await ctx.db.update(devices).set(patch).where(eq(devices.id, row.device.id));
      Object.assign(row.device, patch);
    }

    req.auth = row;
    return row;
  }

  return {
    requireAuth: async (req) => {
      await authenticate(req);
    },
    requireActive: async (req) => {
      const auth = await authenticate(req);
      if (accountStatus(auth.account, ctx.now()) !== 'active') throw accountInactive();
    },
  };
}

/** Narrow helper for handlers behind a guard. */
export function authOf(req: FastifyRequest): AuthContext {
  if (!req.auth) throw unauthorized();
  return req.auth;
}
