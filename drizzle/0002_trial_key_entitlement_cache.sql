ALTER TABLE "ai_accounts" ADD COLUMN "trial_key_hash" text;--> statement-breakpoint
ALTER TABLE "ai_accounts" ADD COLUMN "subscription_expires_at" timestamp with time zone;--> statement-breakpoint
ALTER TABLE "ai_accounts" ADD COLUMN "subscription_checked_at" timestamp with time zone;--> statement-breakpoint
ALTER TABLE "ai_devices" ADD COLUMN "trial_key_hash" text;--> statement-breakpoint
CREATE INDEX "ai_accounts_trial_key_idx" ON "ai_accounts" USING btree ("trial_key_hash");