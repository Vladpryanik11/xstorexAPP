CREATE TABLE "follows" (
	"account_id" text NOT NULL,
	"app_id" text NOT NULL,
	"muted" boolean DEFAULT false NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "follows_account_id_app_id_pk" PRIMARY KEY("account_id","app_id")
);
--> statement-breakpoint
ALTER TABLE "follows" ADD CONSTRAINT "follows_account_id_accounts_id_fk" FOREIGN KEY ("account_id") REFERENCES "public"."accounts"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "follows" ADD CONSTRAINT "follows_app_id_apps_id_fk" FOREIGN KEY ("app_id") REFERENCES "public"."apps"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "follows_app_idx" ON "follows" USING btree ("app_id");