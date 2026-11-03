import { and, asc, eq, gt, lte, sql } from 'drizzle-orm';
import type { Db } from '../../db/index.js';
import { catalogChanges, storeState } from '../../db/schema.js';

export type ChangeKind = 'app_upsert' | 'app_removed' | 'rooms_changed';

export interface ChangeRow {
  revision: number;
  kind: ChangeKind;
  appId: string | null;
}

/**
 * Appends changes to the journal inside the caller's transaction.
 * The counter lives in the store_state row: the row lock serializes writers, so
 * revisions are gap-free and become visible in commit order.
 */
export async function recordChanges(
  tx: Db,
  changes: { kind: ChangeKind; appId: string | null }[],
  journalLimit: number,
): Promise<number> {
  if (changes.length === 0) return (await getRevisionInfo(tx)).revision;
  const [row] = await tx
    .update(storeState)
    .set({ catalogRevision: sql`${storeState.catalogRevision} + ${changes.length}` })
    .where(eq(storeState.id, 1))
    .returning({ revision: storeState.catalogRevision, floor: storeState.journalFloor });
  if (!row) throw new Error('store_state singleton is missing');
  const first = row.revision - changes.length + 1;
  await tx.insert(catalogChanges).values(changes.map((c, i) => ({ revision: first + i, kind: c.kind, appId: c.appId })));
  if (row.revision - row.floor > journalLimit) {
    const floor = row.revision - journalLimit;
    await tx.delete(catalogChanges).where(lte(catalogChanges.revision, floor));
    await tx.update(storeState).set({ journalFloor: floor }).where(eq(storeState.id, 1));
  }
  return row.revision;
}

export async function getRevisionInfo(db: Db): Promise<{ revision: number; floor: number }> {
  const [row] = await db
    .select({ revision: storeState.catalogRevision, floor: storeState.journalFloor })
    .from(storeState)
    .where(eq(storeState.id, 1));
  return row ?? { revision: 0, floor: 0 };
}

export async function getRevision(db: Db): Promise<number> {
  return (await getRevisionInfo(db)).revision;
}

export async function listChanges(db: Db, since: number, upTo: number | null, limit: number): Promise<ChangeRow[]> {
  const where = upTo === null ? gt(catalogChanges.revision, since) : and(gt(catalogChanges.revision, since), lte(catalogChanges.revision, upTo));
  return db
    .select({ revision: catalogChanges.revision, kind: catalogChanges.kind, appId: catalogChanges.appId })
    .from(catalogChanges)
    .where(where)
    .orderBy(asc(catalogChanges.revision))
    .limit(limit);
}
