ALTER TABLE "ai_accounts" ADD COLUMN "scans_used" integer DEFAULT 0 NOT NULL;--> statement-breakpoint
ALTER TABLE "ai_accounts" ADD COLUMN "regular_log_count" integer DEFAULT 0 NOT NULL;--> statement-breakpoint
ALTER TABLE "ai_uploads" ADD COLUMN "scan_reserved_until" timestamp with time zone;