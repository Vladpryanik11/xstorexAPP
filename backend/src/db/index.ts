import { mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import type { ExtractTablesWithRelations } from 'drizzle-orm';
import type { PgDatabase, PgQueryResultHKT } from 'drizzle-orm/pg-core';
import * as schema from './schema.js';

export type Schema = typeof schema;
export type Db = PgDatabase<PgQueryResultHKT, Schema, ExtractTablesWithRelations<Schema>>;

export interface Database {
  db: Db;
  driver: 'pglite' | 'pg';
  close(): Promise<void>;
}

export interface DatabaseOptions {
  databaseUrl: string | null;
  /** null → in-memory PGlite */
  pgliteDir: string | null;
}

export const migrationsFolder = fileURLToPath(new URL('../../drizzle', import.meta.url));

/** Opens the database and applies pending migrations. */
export async function openDatabase(opts: DatabaseOptions): Promise<Database> {
  let database: Database;
  if (opts.databaseUrl) {
    const { default: pg } = await import('pg');
    const { drizzle } = await import('drizzle-orm/node-postgres');
    const { migrate } = await import('drizzle-orm/node-postgres/migrator');
    const pool = new pg.Pool({ connectionString: opts.databaseUrl, max: 10 });
    const db = drizzle(pool, { schema });
    await migrate(db, { migrationsFolder });
    database = { db: db as unknown as Db, driver: 'pg', close: () => pool.end() };
  } else {
    const { PGlite } = await import('@electric-sql/pglite');
    const { drizzle } = await import('drizzle-orm/pglite');
    const { migrate } = await import('drizzle-orm/pglite/migrator');
    if (opts.pgliteDir) mkdirSync(opts.pgliteDir, { recursive: true });
    const client = opts.pgliteDir ? new PGlite(opts.pgliteDir) : new PGlite();
    await client.waitReady;
    const db = drizzle({ client, schema });
    await migrate(db, { migrationsFolder });
    database = { db: db as unknown as Db, driver: 'pglite', close: () => client.close() };
  }
  await ensureSingletons(database.db);
  return database;
}

export async function ensureSingletons(db: Db): Promise<void> {
  await db.insert(schema.storeState).values({ id: 1 }).onConflictDoNothing();
  await db.insert(schema.clientVersion).values({ id: 1 }).onConflictDoNothing();
}

export { schema };
