CREATE TABLE "ai_accounts" (
	"id" uuid PRIMARY KEY NOT NULL,
	"original_transaction_id" text,
	"environment" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "ai_accounts_original_transaction_id_unique" UNIQUE("original_transaction_id")
);
--> statement-breakpoint
CREATE TABLE "ai_challenges" (
	"nonce" text PRIMARY KEY NOT NULL,
	"key_id" text NOT NULL,
	"purpose" text NOT NULL,
	"expires_at" timestamp with time zone NOT NULL
);
--> statement-breakpoint
CREATE TABLE "ai_devices" (
	"key_id" text PRIMARY KEY NOT NULL,
	"account_id" uuid NOT NULL,
	"public_key" text NOT NULL,
	"sign_count" integer DEFAULT 0 NOT NULL,
	"last_seen" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "ai_limits" (
	"bucket" text PRIMARY KEY NOT NULL,
	"count" integer NOT NULL,
	"expires_at" timestamp with time zone NOT NULL
);
--> statement-breakpoint
CREATE TABLE "ai_uploads" (
	"id" uuid PRIMARY KEY NOT NULL,
	"account_id" uuid NOT NULL,
	"pathname" text NOT NULL,
	"kind" text NOT NULL,
	"mime" text NOT NULL,
	"byte_length" integer NOT NULL,
	"sha256" text NOT NULL,
	"storage" text NOT NULL,
	"state" text DEFAULT 'pending' NOT NULL,
	"result" jsonb,
	"expires_at" timestamp with time zone NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "ai_devices" ADD CONSTRAINT "ai_devices_account_id_ai_accounts_id_fk" FOREIGN KEY ("account_id") REFERENCES "public"."ai_accounts"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "ai_uploads" ADD CONSTRAINT "ai_uploads_account_id_ai_accounts_id_fk" FOREIGN KEY ("account_id") REFERENCES "public"."ai_accounts"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "ai_devices_account_idx" ON "ai_devices" USING btree ("account_id");--> statement-breakpoint
CREATE INDEX "ai_uploads_expiry_idx" ON "ai_uploads" USING btree ("expires_at");