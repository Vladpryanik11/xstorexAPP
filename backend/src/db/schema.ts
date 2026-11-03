import {
  bigint,
  boolean,
  doublePrecision,
  index,
  integer,
  jsonb,
  pgTable,
  serial,
  text,
  timestamp,
  uniqueIndex,
} from 'drizzle-orm/pg-core';

const ts = (name: string) => timestamp(name, { withTimezone: true, mode: 'date' });
const createdAt = () => ts('created_at').notNull().defaultNow();
const updatedAt = () => ts('updated_at').notNull().defaultNow();

/** Localized text stored as JSON: `en` is the fallback language. */
export interface LocalizedText {
  en: string;
  ru?: string | null;
}

// ---------------------------------------------------------------------------
// Accounts & auth
// ---------------------------------------------------------------------------

export const plans = pgTable('plans', {
  id: text('id').primaryKey(),
  nameEn: text('name_en').notNull(),
  nameRu: text('name_ru'),
  periodMonths: integer('period_months').notNull(),
  durationDays: integer('duration_days').notNull(),
  createdAt: createdAt(),
});

export const accounts = pgTable('accounts', {
  id: text('id').primaryKey(),
  displayName: text('display_name'),
  planId: text('plan_id')
    .notNull()
    .references(() => plans.id),
  /** Stored status; "expired" is derived from expires_at. */
  status: text('status', { enum: ['active', 'suspended'] })
    .notNull()
    .default('active'),
  expiresAt: ts('expires_at'),
  createdAt: createdAt(),
  updatedAt: updatedAt(),
});

export const devices = pgTable(
  'devices',
  {
    id: text('id').primaryKey(),
    accountId: text('account_id')
      .notNull()
      .references(() => accounts.id, { onDelete: 'cascade' }),
    installId: text('install_id').notNull(),
    model: text('model'),
    osVersion: text('os_version'),
    locale: text('locale'),
    appBuild: text('app_build'),
    lastSeenAt: ts('last_seen_at'),
    createdAt: createdAt(),
  },
  (t) => [uniqueIndex('devices_account_install_uq').on(t.accountId, t.installId)],
);

export const activationCodes = pgTable(
  'activation_codes',
  {
    id: text('id').primaryKey(),
    /** SHA-256 (hex) of the normalized code; the plain code is never stored. */
    codeHash: text('code_hash').notNull(),
    /** Last 4 characters of the normalized code, for support lookups. */
    codeHint: text('code_hint').notNull(),
    planId: text('plan_id')
      .notNull()
      .references(() => plans.id),
    /** Overrides plan.duration_days when set. */
    durationDays: integer('duration_days'),
    accountId: text('account_id').references(() => accounts.id, { onDelete: 'set null' }),
    deviceId: text('device_id').references(() => devices.id, { onDelete: 'set null' }),
    usedAt: ts('used_at'),
    createdAt: createdAt(),
  },
  (t) => [uniqueIndex('activation_codes_hash_uq').on(t.codeHash)],
);

export const tokens = pgTable(
  'tokens',
  {
    id: text('id').primaryKey(),
    /** SHA-256 (hex) of the bearer token. */
    tokenHash: text('token_hash').notNull(),
    accountId: text('account_id')
      .notNull()
      .references(() => accounts.id, { onDelete: 'cascade' }),
    deviceId: text('device_id')
      .notNull()
      .references(() => devices.id, { onDelete: 'cascade' }),
    createdAt: createdAt(),
    revokedAt: ts('revoked_at'),
  },
  (t) => [uniqueIndex('tokens_hash_uq').on(t.tokenHash), index('tokens_device_idx').on(t.deviceId)],
);

// ---------------------------------------------------------------------------
// Catalog
// ---------------------------------------------------------------------------

export const categories = pgTable('categories', {
  id: text('id').primaryKey(),
  kind: text('kind', { enum: ['apps', 'games'] }).notNull(),
  nameEn: text('name_en').notNull(),
  nameRu: text('name_ru'),
  sfSymbol: text('sf_symbol').notNull(),
  position: integer('position').notNull().default(0),
  createdAt: createdAt(),
  updatedAt: updatedAt(),
});

export const apps = pgTable(
  'apps',
  {
    id: text('id').primaryKey(),
    bundleId: text('bundle_id'),
    developer: text('developer').notNull(),
    categoryId: text('category_id')
      .notNull()
      .references(() => categories.id),
    nameEn: text('name_en').notNull(),
    nameRu: text('name_ru'),
    subtitleEn: text('subtitle_en'),
    subtitleRu: text('subtitle_ru'),
    descriptionEn: text('description_en').notNull().default(''),
    descriptionRu: text('description_ru'),
    whatsNewEn: text('whats_new_en'),
    whatsNewRu: text('whats_new_ru'),
    /** Absolute http(s) URL or a storage key relative to `static/`. */
    iconUrl: text('icon_url').notNull(),
    /** Small (57×57) icon for the OTA manifest; falls back to icon_url. */
    iconSmallUrl: text('icon_small_url'),
    rating: doublePrecision('rating'),
    ratingCount: integer('rating_count'),
    version: text('version').notNull().default('1.0.0'),
    sizeBytes: bigint('size_bytes', { mode: 'number' }).notNull().default(0),
    minOs: text('min_os').notNull().default('15.0'),
    tintLight: text('tint_light').notNull(),
    tintDark: text('tint_dark').notNull(),
    bgColor: text('bg_color').notNull(),
    badge: text('badge', { enum: ['new', 'updated'] }),
    availability: text('availability', { enum: ['available', 'unavailable'] })
      .notNull()
      .default('available'),
    ageRating: text('age_rating').notNull().default('4+'),
    languages: jsonb('languages').$type<string[]>().notNull().default([]),
    /**
     * Case-folded name/subtitle/developer in both languages, maintained by the app.
     * Folding in JS keeps search case-insensitive for Cyrillic regardless of DB locale.
     */
    searchText: text('search_text').notNull().default(''),
    published: boolean('published').notNull().default(true),
    releasedAt: ts('released_at').notNull().defaultNow(),
    createdAt: createdAt(),
    updatedAt: updatedAt(),
  },
  (t) => [index('apps_category_idx').on(t.categoryId), index('apps_published_idx').on(t.published)],
);

export const appBuilds = pgTable(
  'app_builds',
  {
    id: text('id').primaryKey(),
    appId: text('app_id')
      .notNull()
      .references(() => apps.id, { onDelete: 'cascade' }),
    version: text('version').notNull(),
    build: text('build').notNull(),
    bundleId: text('bundle_id'),
    minOs: text('min_os'),
    sha256: text('sha256'),
    sizeBytes: bigint('size_bytes', { mode: 'number' }).notNull().default(0),
    /** Storage key of the IPA. null → history-only entry, nothing to install. */
    blobKey: text('blob_key'),
    notesEn: text('notes_en'),
    notesRu: text('notes_ru'),
    releasedAt: ts('released_at').notNull().defaultNow(),
    createdAt: createdAt(),
  },
  (t) => [index('app_builds_app_idx').on(t.appId, t.releasedAt)],
);

export const screenshots = pgTable(
  'screenshots',
  {
    id: serial('id').primaryKey(),
    appId: text('app_id')
      .notNull()
      .references(() => apps.id, { onDelete: 'cascade' }),
    position: integer('position').notNull(),
    url: text('url').notNull(),
    width: integer('width').notNull(),
    height: integer('height').notNull(),
  },
  (t) => [index('screenshots_app_idx').on(t.appId, t.position)],
);

export const rooms = pgTable(
  'rooms',
  {
    id: text('id').primaryKey(),
    tab: text('tab', { enum: ['today', 'games', 'apps'] }).notNull(),
    position: integer('position').notNull(),
    style: text('style', { enum: ['hero_carousel', 'shelf_one', 'shelf_two', 'chips'] }).notNull(),
    titleEn: text('title_en'),
    titleRu: text('title_ru'),
    subtitleEn: text('subtitle_en'),
    subtitleRu: text('subtitle_ru'),
    createdAt: createdAt(),
    updatedAt: updatedAt(),
  },
  (t) => [index('rooms_tab_idx').on(t.tab, t.position)],
);

export const roomItems = pgTable(
  'room_items',
  {
    id: serial('id').primaryKey(),
    roomId: text('room_id')
      .notNull()
      .references(() => rooms.id, { onDelete: 'cascade' }),
    position: integer('position').notNull(),
    kind: text('kind', { enum: ['app', 'hero', 'category'] }).notNull(),
    appId: text('app_id').references(() => apps.id, { onDelete: 'cascade' }),
    categoryId: text('category_id').references(() => categories.id, { onDelete: 'cascade' }),
    headlineEn: text('headline_en'),
    headlineRu: text('headline_ru'),
    titleEn: text('title_en'),
    titleRu: text('title_ru'),
    imageUrl: text('image_url'),
    gradient: jsonb('gradient').$type<string[]>(),
  },
  (t) => [index('room_items_room_idx').on(t.roomId, t.position)],
);

/** Append-only journal; revision is assigned from store_state.catalog_revision. */
export const catalogChanges = pgTable('catalog_changes', {
  revision: integer('revision').primaryKey(),
  kind: text('kind', { enum: ['app_upsert', 'app_removed', 'rooms_changed'] }).notNull(),
  appId: text('app_id'),
  createdAt: createdAt(),
});

// ---------------------------------------------------------------------------
// Installs, telemetry, search requests
// ---------------------------------------------------------------------------

export const installs = pgTable(
  'installs',
  {
    id: text('id').primaryKey(),
    accountId: text('account_id')
      .notNull()
      .references(() => accounts.id, { onDelete: 'cascade' }),
    deviceId: text('device_id')
      .notNull()
      .references(() => devices.id, { onDelete: 'cascade' }),
    appId: text('app_id')
      .notNull()
      .references(() => apps.id, { onDelete: 'cascade' }),
    buildId: text('build_id')
      .notNull()
      .references(() => appBuilds.id, { onDelete: 'cascade' }),
    version: text('version').notNull(),
    status: text('status', { enum: ['preparing', 'ready', 'failed'] }).notNull(),
    errorCode: text('error_code'),
    signer: text('signer').notNull(),
    /** SHA-256 (hex) of the grant token used in manifest/IPA URLs. */
    tokenHash: text('token_hash').notNull(),
    blobKey: text('blob_key'),
    sizeBytes: bigint('size_bytes', { mode: 'number' }),
    sha256: text('sha256'),
    locale: text('locale', { enum: ['ru', 'en'] })
      .notNull()
      .default('en'),
    clientStage: text('client_stage'),
    clientErrorCode: text('client_error_code'),
    expiresAt: ts('expires_at').notNull(),
    createdAt: createdAt(),
    updatedAt: updatedAt(),
  },
  (t) => [index('installs_account_idx').on(t.accountId, t.createdAt)],
);

export const searchRequests = pgTable('search_requests', {
  id: serial('id').primaryKey(),
  accountId: text('account_id').references(() => accounts.id, { onDelete: 'set null' }),
  deviceId: text('device_id').references(() => devices.id, { onDelete: 'set null' }),
  query: text('query').notNull(),
  note: text('note'),
  createdAt: createdAt(),
});

export const clientEvents = pgTable(
  'client_events',
  {
    id: bigint('id', { mode: 'number' }).primaryKey().generatedAlwaysAsIdentity(),
    accountId: text('account_id').references(() => accounts.id, { onDelete: 'set null' }),
    deviceId: text('device_id').references(() => devices.id, { onDelete: 'set null' }),
    kind: text('kind').notNull(),
    ts: ts('ts').notNull(),
    props: jsonb('props').$type<Record<string, unknown>>().notNull().default({}),
    receivedAt: ts('received_at').notNull().defaultNow(),
  },
  (t) => [index('client_events_kind_idx').on(t.kind, t.ts)],
);

export const pushTokens = pgTable('push_tokens', {
  id: serial('id').primaryKey(),
  deviceId: text('device_id')
    .notNull()
    .unique()
    .references(() => devices.id, { onDelete: 'cascade' }),
  apnsToken: text('apns_token').notNull(),
  apnsEnv: text('apns_env', { enum: ['sandbox', 'production'] }).notNull(),
  locale: text('locale'),
  tzOffsetMinutes: integer('tz_offset_minutes'),
  updatedAt: updatedAt(),
});

// ---------------------------------------------------------------------------
// Singletons (id = 1)
// ---------------------------------------------------------------------------

export interface StoreClosedInfo {
  title: LocalizedText;
  message: LocalizedText;
  reopens_at: string | null;
  links: { title: LocalizedText; url: string }[];
}

export const storeState = pgTable('store_state', {
  id: integer('id').primaryKey().default(1),
  state: text('state', { enum: ['open', 'closed'] })
    .notNull()
    .default('open'),
  closed: jsonb('closed').$type<StoreClosedInfo>(),
  /** Monotonic catalog revision; bumped in the same transaction that writes catalog_changes. */
  catalogRevision: integer('catalog_revision').notNull().default(0),
  /** Changes with revision <= journal_floor were pruned. */
  journalFloor: integer('journal_floor').notNull().default(0),
  updatedAt: updatedAt(),
});

export const clientVersion = pgTable('client_version', {
  id: integer('id').primaryKey().default(1),
  latestVersion: text('latest_version').notNull().default('1.0.0'),
  latestBuild: integer('latest_build').notNull().default(1),
  minSupportedBuild: integer('min_supported_build').notNull().default(1),
  releaseNotesEn: text('release_notes_en'),
  releaseNotesRu: text('release_notes_ru'),
  updateUrl: text('update_url'),
  updatedAt: updatedAt(),
});

export type AppRow = typeof apps.$inferSelect;
export type CategoryRow = typeof categories.$inferSelect;
export type AccountRow = typeof accounts.$inferSelect;
export type PlanRow = typeof plans.$inferSelect;
export type DeviceRow = typeof devices.$inferSelect;
export type BuildRow = typeof appBuilds.$inferSelect;
export type InstallRow = typeof installs.$inferSelect;
export type RoomRow = typeof rooms.$inferSelect;
export type RoomItemRow = typeof roomItems.$inferSelect;
