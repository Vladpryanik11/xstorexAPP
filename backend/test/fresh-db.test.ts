import { mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import type { FastifyInstance } from 'fastify';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.js';
import { loadConfig } from '../src/config.js';
import { openDatabase, type Database } from '../src/db/index.js';
import { ADMIN_TOKEN, BASE_URL, activate, admin, json } from './helpers.js';

// Продакшен стартует с пустой базы, без seed.
describe('fresh database without seed', () => {
  let app: FastifyInstance;
  let database: Database;
  let storageDir: string;

  beforeAll(async () => {
    storageDir = await mkdtemp(path.join(os.tmpdir(), 'istore-fresh-'));
    database = await openDatabase({ databaseUrl: null, pgliteDir: null });
    app = await buildApp(
      {
        ...loadConfig({}, storageDir),
        publicBaseUrl: BASE_URL,
        adminToken: ADMIN_TOKEN,
        pgliteDir: null,
        storageDir,
        uploadTmpDir: path.join(storageDir, '.tmp'),
        logLevel: 'silent',
        catalogPollMs: 0,
      },
      { database },
    );
  });

  afterAll(async () => {
    await app.close();
    await database.close();
    await rm(storageDir, { recursive: true, force: true });
  });

  it('has default plans, so admin can issue a working activation code', async () => {
    const res = await app.inject({ method: 'POST', url: '/admin/v1/activation-codes', headers: admin(), payload: { count: 1, plan_id: 'month' } });
    expect(res.statusCode).toBe(201);
    const [code] = json<{ codes: string[] }>(res).codes;
    const act = await activate(app, code!, 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee');
    expect(act.statusCode).toBe(200);
    expect(json(act).account.plan).toMatchObject({ id: 'month', period_months: 1 });
  });

  it('serves an empty but valid storefront', async () => {
    const act = await app.inject({ method: 'POST', url: '/admin/v1/activation-codes', headers: admin(), payload: { count: 1, plan_id: 'year' } });
    const [code] = json<{ codes: string[] }>(act).codes;
    const { token } = json(await activate(app, code!, 'bbbbbbbb-cccc-4ddd-8eee-ffffffffffff'));
    const res = await app.inject({ method: 'GET', url: '/api/v1/groupings?tab=today', headers: { authorization: `Bearer ${token}` } });
    expect(res.statusCode).toBe(200);
    expect(json(res).rooms).toEqual([]);
  });
});
