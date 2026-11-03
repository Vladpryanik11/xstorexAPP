import { and, eq, isNull } from 'drizzle-orm';
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import type { AppContext } from '../../context.js';
import { accounts, activationCodes, devices, plans, tokens } from '../../db/schema.js';
import { newId, randomToken, sha256Hex } from '../../lib/crypto.js';
import { AppError, accountInactive, conflict } from '../../lib/errors.js';
import { resolveLang } from '../../lib/i18n.js';
import { parseInput } from '../../lib/validation.js';
import { accountStatus, accountView } from './account.js';
import { hashCode, normalizeCode } from './codes.js';
import { authOf, type Guard } from './guard.js';

const activateSchema = z.object({
  activation_code: z.string().min(1).max(64),
  device: z.object({
    install_id: z.uuid(),
    model: z.string().trim().max(64).optional(),
    os_version: z.string().trim().max(32).optional(),
    locale: z.string().trim().max(35).optional(),
  }),
});

const invalidCode = () =>
  new AppError(404, 'invalid_code', {
    en: 'This activation code was not found. Check it and try again.',
    ru: 'Такой код активации не найден. Проверьте его и попробуйте снова.',
  });

const codeUsed = () =>
  conflict('code_used', {
    en: 'This code is already activated on another device.',
    ru: 'Этот код уже активирован на другом устройстве.',
  });

const DAY_MS = 24 * 60 * 60 * 1000;

export async function authRoutes(app: FastifyInstance, opts: { ctx: AppContext; guards: { requireAuth: Guard } }) {
  const { ctx, guards } = opts;

  app.post(
    '/app/activate',
    {
      config: {
        rateLimit: { max: ctx.config.activateRateLimit.max, timeWindow: ctx.config.activateRateLimit.timeWindowMs },
      },
    },
    async (req) => {
      const body = parseInput(activateSchema, req.body, 'body');
      const lang = resolveLang(req.headers['accept-language']);
      const normalized = normalizeCode(body.activation_code);
      if (!normalized) throw invalidCode();
      const installId = body.device.install_id.toLowerCase();
      const deviceInfo = {
        model: body.device.model ?? null,
        osVersion: body.device.os_version ?? null,
        locale: body.device.locale ?? null,
      };

      const result = await ctx.db.transaction(async (tx) => {
        const now = ctx.now();
        const [code] = await tx
          .select()
          .from(activationCodes)
          .where(eq(activationCodes.codeHash, hashCode(normalized)))
          .for('update');
        if (!code) throw invalidCode();

        let accountId: string;
        let deviceId: string;
        if (code.usedAt === null) {
          const [plan] = await tx.select().from(plans).where(eq(plans.id, code.planId));
          if (!plan) throw invalidCode();
          accountId = newId('acc');
          deviceId = newId('dev');
          const days = code.durationDays ?? plan.durationDays;
          await tx.insert(accounts).values({
            id: accountId,
            planId: plan.id,
            status: 'active',
            expiresAt: new Date(now.getTime() + days * DAY_MS),
          });
          await tx.insert(devices).values({ id: deviceId, accountId, installId, ...deviceInfo, lastSeenAt: now });
          await tx
            .update(activationCodes)
            .set({ usedAt: now, accountId, deviceId })
            .where(eq(activationCodes.id, code.id));
        } else {
          // One code — one device. The same install_id may re-activate (new token).
          if (!code.deviceId || !code.accountId) throw codeUsed();
          const [device] = await tx.select().from(devices).where(eq(devices.id, code.deviceId));
          if (!device || device.installId !== installId) throw codeUsed();
          const [account] = await tx.select().from(accounts).where(eq(accounts.id, code.accountId));
          if (!account) throw codeUsed();
          if (accountStatus(account, now) !== 'active') throw accountInactive();
          accountId = account.id;
          deviceId = device.id;
          await tx
            .update(devices)
            .set({ ...deviceInfo, lastSeenAt: now })
            .where(eq(devices.id, deviceId));
          await tx
            .update(tokens)
            .set({ revokedAt: now })
            .where(and(eq(tokens.deviceId, deviceId), isNull(tokens.revokedAt)));
        }

        const token = randomToken();
        await tx.insert(tokens).values({ id: newId('tok'), tokenHash: sha256Hex(token), accountId, deviceId });
        const [row] = await tx
          .select({ account: accounts, plan: plans })
          .from(accounts)
          .innerJoin(plans, eq(accounts.planId, plans.id))
          .where(eq(accounts.id, accountId));
        if (!row) throw new Error('account vanished during activation');
        return { token, ...row };
      });

      req.log.info({ accountId: result.account.id }, 'device activated');
      return { token: result.token, account: accountView(ctx, result.account, result.plan, lang) };
    },
  );

  app.post('/app/sign-out', { onRequest: guards.requireAuth }, async (req, reply) => {
    const auth = authOf(req);
    await ctx.db.update(tokens).set({ revokedAt: ctx.now() }).where(eq(tokens.id, auth.tokenId));
    return reply.code(204).send();
  });
}
