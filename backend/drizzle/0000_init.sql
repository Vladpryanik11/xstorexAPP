CREATE TABLE "accounts" (
	"id" text PRIMARY KEY NOT NULL,
	"display_name" text,
	"plan_id" text NOT NULL,
	"status" text DEFAULT 'active' NOT NULL,
	"expires_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "activation_codes" (
	"id" text PRIMARY KEY NOT NULL,
	"code_hash" text NOT NULL,
	"code_hint" text NOT NULL,
	"plan_id" text NOT NULL,
	"duration_days" integer,
	"account_id" text,
	"device_id" text,
	"used_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "app_builds" (
	"id" text PRIMARY KEY NOT NULL,
	"app_id" text NOT NULL,
	"version" text NOT NULL,
	"build" text NOT NULL,
	"bundle_id" text,
	"min_os" text,
	"sha256" text,
	"size_bytes" bigint DEFAULT 0 NOT NULL,
	"blob_key" text,
	"notes_en" text,
	"notes_ru" text,
	"released_at" timestamp with time zone DEFAULT now() NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "apps" (
	"id" text PRIMARY KEY NOT NULL,
	"bundle_id" text,
	"developer" text NOT NULL,
	"category_id" text NOT NULL,
	"name_en" text NOT NULL,
	"name_ru" text,
	"subtitle_en" text,
	"subtitle_ru" text,
	"description_en" text DEFAULT '' NOT NULL,
	"description_ru" text,
	"whats_new_en" text,
	"whats_new_ru" text,
	"icon_url" text NOT NULL,
	"icon_small_url" text,
	"rating" double precision,
	"rating_count" integer,
	"version" text DEFAULT '1.0.0' NOT NULL,
	"size_bytes" bigint DEFAULT 0 NOT NULL,
	"min_os" text DEFAULT '15.0' NOT NULL,
	"tint_light" text NOT NULL,
	"tint_dark" text NOT NULL,
	"bg_color" text NOT NULL,
	"badge" text,
	"availability" text DEFAULT 'available' NOT NULL,
	"age_rating" text DEFAULT '4+' NOT NULL,
	"languages" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"search_text" text DEFAULT '' NOT NULL,
	"published" boolean DEFAULT true NOT NULL,
	"released_at" timestamp with time zone DEFAULT now() NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "catalog_changes" (
	"revision" integer PRIMARY KEY NOT NULL,
	"kind" text NOT NULL,
	"app_id" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "categories" (
	"id" text PRIMARY KEY NOT NULL,
	"kind" text NOT NULL,
	"name_en" text NOT NULL,
	"name_ru" text,
	"sf_symbol" text NOT NULL,
	"position" integer DEFAULT 0 NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "client_events" (
	"id" bigint PRIMARY KEY GENERATED ALWAYS AS IDENTITY (sequence name "client_events_id_seq" INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START WITH 1 CACHE 1),
	"account_id" text,
	"device_id" text,
	"kind" text NOT NULL,
	"ts" timestamp with time zone NOT NULL,
	"props" jsonb DEFAULT '{}'::jsonb NOT NULL,
	"received_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "client_version" (
	"id" integer PRIMARY KEY DEFAULT 1 NOT NULL,
	"latest_version" text DEFAULT '1.0.0' NOT NULL,
	"latest_build" integer DEFAULT 1 NOT NULL,
	"min_supported_build" integer DEFAULT 1 NOT NULL,
	"release_notes_en" text,
	"release_notes_ru" text,
	"update_url" text,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "devices" (
	"id" text PRIMARY KEY NOT NULL,
	"account_id" text NOT NULL,
	"install_id" text NOT NULL,
	"model" text,
	"os_version" text,
	"locale" text,
	"app_build" text,
	"last_seen_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "installs" (
	"id" text PRIMARY KEY NOT NULL,
	"account_id" text NOT NULL,
	"device_id" text NOT NULL,
	"app_id" text NOT NULL,
	"build_id" text NOT NULL,
	"version" text NOT NULL,
	"status" text NOT NULL,
	"error_code" text,
	"signer" text NOT NULL,
	"token_hash" text NOT NULL,
	"blob_key" text,
	"size_bytes" bigint,
	"sha256" text,
	"locale" text DEFAULT 'en' NOT NULL,
	"client_stage" text,
	"client_error_code" text,
	"expires_at" timestamp with time zone NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "plans" (
	"id" text PRIMARY KEY NOT NULL,
	"name_en" text NOT NULL,
	"name_ru" text,
	"period_months" integer NOT NULL,
	"duration_days" integer NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "push_tokens" (
	"id" serial PRIMARY KEY NOT NULL,
	"device_id" text NOT NULL,
	"apns_token" text NOT NULL,
	"apns_env" text NOT NULL,
	"locale" text,
	"tz_offset_minutes" integer,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "push_tokens_device_id_unique" UNIQUE("device_id")
);
--> statement-breakpoint
CREATE TABLE "room_items" (
	"id" serial PRIMARY KEY NOT NULL,
	"room_id" text NOT NULL,
	"position" integer NOT NULL,
	"kind" text NOT NULL,
	"app_id" text,
	"category_id" text,
	"headline_en" text,
	"headline_ru" text,
	"title_en" text,
	"title_ru" text,
	"image_url" text,
	"gradient" jsonb
);
--> statement-breakpoint
CREATE TABLE "rooms" (
	"id" text PRIMARY KEY NOT NULL,
	"tab" text NOT NULL,
	"position" integer NOT NULL,
	"style" text NOT NULL,
	"title_en" text,
	"title_ru" text,
	"subtitle_en" text,
	"subtitle_ru" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "screenshots" (
	"id" serial PRIMARY KEY NOT NULL,
	"app_id" text NOT NULL,
	"position" integer NOT NULL,
	"url" text NOT NULL,
	"width" integer NOT NULL,
	"height" integer NOT NULL
);
--> statement-breakpoint
CREATE TABLE "search_requests" (
	"id" serial PRIMARY KEY NOT NULL,
	"account_id" text,
	"device_id" text,
	"query" text NOT NULL,
	"note" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "store_state" (
	"id" integer PRIMARY KEY DEFAULT 1 NOT NULL,
	"state" text DEFAULT 'open' NOT NULL,
	"closed" jsonb,
	"catalog_revision" integer DEFAULT 0 NOT NULL,
	"journal_floor" integer DEFAULT 0 NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "tokens" (
	"id" text PRIMARY KEY NOT NULL,
	"token_hash" text NOT NULL,
	"account_id" text NOT NULL,
	"device_id" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"revoked_at" timestamp with time zone
);
--> statement-breakpoint
ALTER TABLE "accounts" ADD CONSTRAINT "accounts_plan_id_plans_id_fk" FOREIGN KEY ("plan_id") REFERENCES "public"."plans"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "activation_codes" ADD CONSTRAINT "activation_codes_plan_id_plans_id_fk" FOREIGN KEY ("plan_id") REFERENCES "public"."plans"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "activation_codes" ADD CONSTRAINT "activation_codes_account_id_accounts_id_fk" FOREIGN KEY ("account_id") REFERENCES "public"."accounts"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "activation_codes" ADD CONSTRAINT "activation_codes_device_id_devices_id_fk" FOREIGN KEY ("device_id") REFERENCES "public"."devices"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "app_builds" ADD CONSTRAINT "app_builds_app_id_apps_id_fk" FOREIGN KEY ("app_id") REFERENCES "public"."apps"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "apps" ADD CONSTRAINT "apps_category_id_categories_id_fk" FOREIGN KEY ("category_id") REFERENCES "public"."categories"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "client_events" ADD CONSTRAINT "client_events_account_id_accounts_id_fk" FOREIGN KEY ("account_id") REFERENCES "public"."accounts"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "client_events" ADD CONSTRAINT "client_events_device_id_devices_id_fk" FOREIGN KEY ("device_id") REFERENCES "public"."devices"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "devices" ADD CONSTRAINT "devices_account_id_accounts_id_fk" FOREIGN KEY ("account_id") REFERENCES "public"."accounts"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "installs" ADD CONSTRAINT "installs_account_id_accounts_id_fk" FOREIGN KEY ("account_id") REFERENCES "public"."accounts"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "installs" ADD CONSTRAINT "installs_device_id_devices_id_fk" FOREIGN KEY ("device_id") REFERENCES "public"."devices"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "installs" ADD CONSTRAINT "installs_app_id_apps_id_fk" FOREIGN KEY ("app_id") REFERENCES "public"."apps"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "installs" ADD CONSTRAINT "installs_build_id_app_builds_id_fk" FOREIGN KEY ("build_id") REFERENCES "public"."app_builds"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "push_tokens" ADD CONSTRAINT "push_tokens_device_id_devices_id_fk" FOREIGN KEY ("device_id") REFERENCES "public"."devices"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "room_items" ADD CONSTRAINT "room_items_room_id_rooms_id_fk" FOREIGN KEY ("room_id") REFERENCES "public"."rooms"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "room_items" ADD CONSTRAINT "room_items_app_id_apps_id_fk" FOREIGN KEY ("app_id") REFERENCES "public"."apps"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "room_items" ADD CONSTRAINT "room_items_category_id_categories_id_fk" FOREIGN KEY ("category_id") REFERENCES "public"."categories"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "screenshots" ADD CONSTRAINT "screenshots_app_id_apps_id_fk" FOREIGN KEY ("app_id") REFERENCES "public"."apps"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "search_requests" ADD CONSTRAINT "search_requests_account_id_accounts_id_fk" FOREIGN KEY ("account_id") REFERENCES "public"."accounts"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "search_requests" ADD CONSTRAINT "search_requests_device_id_devices_id_fk" FOREIGN KEY ("device_id") REFERENCES "public"."devices"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "tokens" ADD CONSTRAINT "tokens_account_id_accounts_id_fk" FOREIGN KEY ("account_id") REFERENCES "public"."accounts"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "tokens" ADD CONSTRAINT "tokens_device_id_devices_id_fk" FOREIGN KEY ("device_id") REFERENCES "public"."devices"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "activation_codes_hash_uq" ON "activation_codes" USING btree ("code_hash");--> statement-breakpoint
CREATE INDEX "app_builds_app_idx" ON "app_builds" USING btree ("app_id","released_at");--> statement-breakpoint
CREATE INDEX "apps_category_idx" ON "apps" USING btree ("category_id");--> statement-breakpoint
CREATE INDEX "apps_published_idx" ON "apps" USING btree ("published");--> statement-breakpoint
CREATE INDEX "client_events_kind_idx" ON "client_events" USING btree ("kind","ts");--> statement-breakpoint
CREATE UNIQUE INDEX "devices_account_install_uq" ON "devices" USING btree ("account_id","install_id");--> statement-breakpoint
CREATE INDEX "installs_account_idx" ON "installs" USING btree ("account_id","created_at");--> statement-breakpoint
CREATE INDEX "room_items_room_idx" ON "room_items" USING btree ("room_id","position");--> statement-breakpoint
CREATE INDEX "rooms_tab_idx" ON "rooms" USING btree ("tab","position");--> statement-breakpoint
CREATE INDEX "screenshots_app_idx" ON "screenshots" USING btree ("app_id","position");--> statement-breakpoint
CREATE UNIQUE INDEX "tokens_hash_uq" ON "tokens" USING btree ("token_hash");--> statement-breakpoint
CREATE INDEX "tokens_device_idx" ON "tokens" USING btree ("device_id");