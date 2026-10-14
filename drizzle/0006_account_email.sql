CREATE TABLE "email_campaigns" (
	"id" uuid PRIMARY KEY NOT NULL,
	"subject" text NOT NULL,
	"body" text NOT NULL,
	"status" text DEFAULT 'sending' NOT NULL,
	"recipients" integer DEFAULT 0 NOT NULL,
	"sent" integer DEFAULT 0 NOT NULL,
	"failed" integer DEFAULT 0 NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"finished_at" timestamp with time zone
);
--> statement-breakpoint
ALTER TABLE "clan_people" ADD COLUMN "email" text;--> statement-breakpoint
ALTER TABLE "clan_people" ADD COLUMN "email_private" boolean DEFAULT false NOT NULL;--> statement-breakpoint
ALTER TABLE "clan_people" ADD COLUMN "news_opt_in" boolean DEFAULT false NOT NULL;--> statement-breakpoint
ALTER TABLE "clan_people" ADD COLUMN "news_opt_in_at" timestamp with time zone;--> statement-breakpoint
ALTER TABLE "clan_people" ADD COLUMN "news_opt_out_at" timestamp with time zone;