CREATE TABLE "clan_alerts" (
	"id" uuid PRIMARY KEY NOT NULL,
	"person_id" uuid NOT NULL,
	"clan_id" uuid,
	"kind" text NOT NULL,
	"payload" jsonb DEFAULT '{}'::jsonb NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"read_at" timestamp with time zone
);
--> statement-breakpoint
CREATE TABLE "clan_blocks" (
	"blocker_id" uuid NOT NULL,
	"blocked_id" uuid NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "clan_blocks_blocker_id_blocked_id_pk" PRIMARY KEY("blocker_id","blocked_id")
);
--> statement-breakpoint
CREATE TABLE "clan_challenges" (
	"id" uuid PRIMARY KEY NOT NULL,
	"clan_id" uuid NOT NULL,
	"kind" text NOT NULL,
	"settings" jsonb DEFAULT '{}'::jsonb NOT NULL,
	"saves_count" integer DEFAULT 0 NOT NULL,
	"saves_period" text DEFAULT 'challenge' NOT NULL,
	"starts_on" date NOT NULL,
	"ends_on" date,
	"status" text DEFAULT 'upcoming' NOT NULL,
	"result" jsonb,
	"evaluated_at" timestamp with time zone,
	"created_by" uuid,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"ended_at" timestamp with time zone
);
--> statement-breakpoint
CREATE TABLE "clan_days" (
	"person_id" uuid NOT NULL,
	"day" date NOT NULL,
	"logged" boolean NOT NULL,
	"full_day" boolean NOT NULL,
	"percent_of_goal" integer,
	"goal_ok" boolean NOT NULL,
	"done_eating" boolean DEFAULT false NOT NULL,
	"reported_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "clan_days_person_id_day_pk" PRIMARY KEY("person_id","day")
);
--> statement-breakpoint
CREATE TABLE "clan_entrants" (
	"challenge_id" uuid NOT NULL,
	"person_id" uuid NOT NULL,
	"status" text DEFAULT 'in' NOT NULL,
	"joined_at" timestamp with time zone DEFAULT now() NOT NULL,
	"left_on" date,
	"out_on" date,
	"points" integer DEFAULT 0 NOT NULL,
	"lives_left" integer,
	"rank" integer,
	"weight" jsonb,
	CONSTRAINT "clan_entrants_challenge_id_person_id_pk" PRIMARY KEY("challenge_id","person_id")
);
--> statement-breakpoint
CREATE TABLE "clan_identities" (
	"provider" text NOT NULL,
	"subject" text NOT NULL,
	"person_id" uuid NOT NULL,
	"apple_refresh_token" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "clan_identities_provider_subject_pk" PRIMARY KEY("provider","subject")
);
--> statement-breakpoint
CREATE TABLE "clan_members" (
	"id" uuid PRIMARY KEY NOT NULL,
	"clan_id" uuid NOT NULL,
	"person_id" uuid NOT NULL,
	"role" text DEFAULT 'member' NOT NULL,
	"anonymous" boolean DEFAULT false NOT NULL,
	"anon_number" integer,
	"muted" boolean DEFAULT false NOT NULL,
	"rule" jsonb,
	"joined_at" timestamp with time zone DEFAULT now() NOT NULL,
	"left_at" timestamp with time zone,
	"removed_by" uuid
);
--> statement-breakpoint
CREATE TABLE "clan_nudges" (
	"from_id" uuid NOT NULL,
	"to_id" uuid NOT NULL,
	"clan_id" uuid NOT NULL,
	"day" date NOT NULL,
	"kind" text NOT NULL,
	CONSTRAINT "clan_nudges_from_id_to_id_day_kind_pk" PRIMARY KEY("from_id","to_id","day","kind")
);
--> statement-breakpoint
CREATE TABLE "clan_people" (
	"id" uuid PRIMARY KEY NOT NULL,
	"display_name" text NOT NULL,
	"photo_id" uuid,
	"birth_year" integer,
	"birth_month" integer,
	"time_zone" text DEFAULT 'America/Los_Angeles' NOT NULL,
	"alert_prefs" jsonb DEFAULT '{}'::jsonb NOT NULL,
	"evening_alert_on" date,
	"terms_accepted_at" timestamp with time zone NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "clan_push_tokens" (
	"token" text PRIMARY KEY NOT NULL,
	"person_id" uuid NOT NULL,
	"environment" text NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "clan_reports" (
	"id" uuid PRIMARY KEY NOT NULL,
	"reporter_id" uuid,
	"kind" text NOT NULL,
	"target_person_id" uuid,
	"target_clan_id" uuid,
	"snapshot" text NOT NULL,
	"reason" text DEFAULT '' NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"resolved_at" timestamp with time zone,
	"resolution" text
);
--> statement-breakpoint
CREATE TABLE "clan_sessions" (
	"token_hash" text PRIMARY KEY NOT NULL,
	"person_id" uuid NOT NULL,
	"account_id" uuid,
	"membership_override" boolean,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"last_used_at" timestamp with time zone DEFAULT now() NOT NULL,
	"expires_at" timestamp with time zone NOT NULL
);
--> statement-breakpoint
CREATE TABLE "clans" (
	"id" uuid PRIMARY KEY NOT NULL,
	"name" text NOT NULL,
	"invite_code" text NOT NULL,
	"accountability" text DEFAULT 'off' NOT NULL,
	"rule" jsonb DEFAULT '{"kind":"atOrUnder","percent":5}'::jsonb NOT NULL,
	"rule_choice" text DEFAULT 'clan' NOT NULL,
	"best_streak" integer DEFAULT 0 NOT NULL,
	"created_by" uuid,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "clans_invite_code_unique" UNIQUE("invite_code")
);
--> statement-breakpoint
ALTER TABLE "clan_alerts" ADD CONSTRAINT "clan_alerts_person_id_clan_people_id_fk" FOREIGN KEY ("person_id") REFERENCES "public"."clan_people"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "clan_alerts" ADD CONSTRAINT "clan_alerts_clan_id_clans_id_fk" FOREIGN KEY ("clan_id") REFERENCES "public"."clans"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "clan_blocks" ADD CONSTRAINT "clan_blocks_blocker_id_clan_people_id_fk" FOREIGN KEY ("blocker_id") REFERENCES "public"."clan_people"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "clan_blocks" ADD CONSTRAINT "clan_blocks_blocked_id_clan_people_id_fk" FOREIGN KEY ("blocked_id") REFERENCES "public"."clan_people"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "clan_challenges" ADD CONSTRAINT "clan_challenges_clan_id_clans_id_fk" FOREIGN KEY ("clan_id") REFERENCES "public"."clans"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "clan_challenges" ADD CONSTRAINT "clan_challenges_created_by_clan_people_id_fk" FOREIGN KEY ("created_by") REFERENCES "public"."clan_people"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "clan_days" ADD CONSTRAINT "clan_days_person_id_clan_people_id_fk" FOREIGN KEY ("person_id") REFERENCES "public"."clan_people"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "clan_entrants" ADD CONSTRAINT "clan_entrants_challenge_id_clan_challenges_id_fk" FOREIGN KEY ("challenge_id") REFERENCES "public"."clan_challenges"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "clan_entrants" ADD CONSTRAINT "clan_entrants_person_id_clan_people_id_fk" FOREIGN KEY ("person_id") REFERENCES "public"."clan_people"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "clan_identities" ADD CONSTRAINT "clan_identities_person_id_clan_people_id_fk" FOREIGN KEY ("person_id") REFERENCES "public"."clan_people"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "clan_members" ADD CONSTRAINT "clan_members_clan_id_clans_id_fk" FOREIGN KEY ("clan_id") REFERENCES "public"."clans"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "clan_members" ADD CONSTRAINT "clan_members_person_id_clan_people_id_fk" FOREIGN KEY ("person_id") REFERENCES "public"."clan_people"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "clan_nudges" ADD CONSTRAINT "clan_nudges_from_id_clan_people_id_fk" FOREIGN KEY ("from_id") REFERENCES "public"."clan_people"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "clan_nudges" ADD CONSTRAINT "clan_nudges_to_id_clan_people_id_fk" FOREIGN KEY ("to_id") REFERENCES "public"."clan_people"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "clan_nudges" ADD CONSTRAINT "clan_nudges_clan_id_clans_id_fk" FOREIGN KEY ("clan_id") REFERENCES "public"."clans"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "clan_push_tokens" ADD CONSTRAINT "clan_push_tokens_person_id_clan_people_id_fk" FOREIGN KEY ("person_id") REFERENCES "public"."clan_people"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "clan_reports" ADD CONSTRAINT "clan_reports_reporter_id_clan_people_id_fk" FOREIGN KEY ("reporter_id") REFERENCES "public"."clan_people"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "clan_reports" ADD CONSTRAINT "clan_reports_target_person_id_clan_people_id_fk" FOREIGN KEY ("target_person_id") REFERENCES "public"."clan_people"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "clan_reports" ADD CONSTRAINT "clan_reports_target_clan_id_clans_id_fk" FOREIGN KEY ("target_clan_id") REFERENCES "public"."clans"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "clan_sessions" ADD CONSTRAINT "clan_sessions_person_id_clan_people_id_fk" FOREIGN KEY ("person_id") REFERENCES "public"."clan_people"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "clans" ADD CONSTRAINT "clans_created_by_clan_people_id_fk" FOREIGN KEY ("created_by") REFERENCES "public"."clan_people"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "clan_alerts_person_idx" ON "clan_alerts" USING btree ("person_id","read_at");--> statement-breakpoint
CREATE INDEX "clan_challenges_clan_idx" ON "clan_challenges" USING btree ("clan_id","status");--> statement-breakpoint
CREATE INDEX "clan_entrants_person_idx" ON "clan_entrants" USING btree ("person_id");--> statement-breakpoint
CREATE INDEX "clan_identities_person_idx" ON "clan_identities" USING btree ("person_id");--> statement-breakpoint
CREATE INDEX "clan_members_clan_idx" ON "clan_members" USING btree ("clan_id");--> statement-breakpoint
CREATE INDEX "clan_members_person_idx" ON "clan_members" USING btree ("person_id");--> statement-breakpoint
CREATE UNIQUE INDEX "clan_members_active_idx" ON "clan_members" USING btree ("clan_id","person_id") WHERE "clan_members"."left_at" is null;--> statement-breakpoint
CREATE INDEX "clan_push_tokens_person_idx" ON "clan_push_tokens" USING btree ("person_id");--> statement-breakpoint
CREATE INDEX "clan_reports_open_idx" ON "clan_reports" USING btree ("resolved_at","created_at");--> statement-breakpoint
CREATE INDEX "clan_sessions_person_idx" ON "clan_sessions" USING btree ("person_id");