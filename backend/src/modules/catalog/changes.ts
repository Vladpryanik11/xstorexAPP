import type { AppContext } from '../../context.js';
import type { Lang } from '../../lib/i18n.js';
import { loadSummaries, type AppSummary } from './present.js';
import type { ChangeKind, ChangeRow } from './revision.js';

export interface ChangeView {
  revision: number;
  kind: ChangeKind;
  app_id: string | null;
  app: AppSummary | null;
}

/**
 * Renders journal rows with the *current* app state. An upsert of an app that is no
 * longer published is reported as `app_removed`, so replaying converges to the truth.
 */
export async function presentChanges(ctx: AppContext, rows: ChangeRow[], lang: Lang): Promise<ChangeView[]> {
  const upsertIds = rows.flatMap((r) => (r.kind === 'app_upsert' && r.appId ? [r.appId] : []));
  const summaries = await loadSummaries(ctx, upsertIds, lang);
  return rows.map((r) => {
    if (r.kind === 'app_upsert' && r.appId) {
      const app = summaries.get(r.appId);
      return app
        ? { revision: r.revision, kind: 'app_upsert', app_id: r.appId, app }
        : { revision: r.revision, kind: 'app_removed', app_id: r.appId, app: null };
    }
    return { revision: r.revision, kind: r.kind, app_id: r.appId, app: null };
  });
}
