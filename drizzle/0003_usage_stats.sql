CREATE TABLE "app_errors" (
	"id" uuid PRIMARY KEY NOT NULL,
	"install_id" uuid,
	"source" text NOT NULL,
	"area" text NOT NULL,
	"code" text NOT NULL,
	"message" text NOT NULL,
	"location" text DEFAULT '' NOT NULL,
	"detail" text DEFAULT '' NOT NULL,
	"fingerprint" text NOT NULL,
	"app_version" text DEFAULT '' NOT NULL,
	"os_version" text DEFAULT '' NOT NULL,
	"at" timestamp with time zone NOT NULL
);
--> statement-breakpoint
CREATE TABLE "error_resolutions" (
	"fingerprint" text PRIMARY KEY NOT NULL,
	"resolved_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "usage_batches" (
	"id" uuid PRIMARY KEY NOT NULL,
	"received_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "usage_daily" (
	"install_id" uuid NOT NULL,
	"day" date NOT NULL,
	"metric" text NOT NULL,
	"count" integer NOT NULL,
	CONSTRAINT "usage_daily_install_id_day_metric_pk" PRIMARY KEY("install_id","day","metric")
);
--> statement-breakpoint
CREATE TABLE "usage_events" (
	"id" uuid PRIMARY KEY NOT NULL,
	"install_id" uuid NOT NULL,
	"name" text NOT NULL,
	"at" timestamp with time zone NOT NULL,
	"props" jsonb DEFAULT '{}'::jsonb NOT NULL,
	"app_version" text NOT NULL
);
--> statement-breakpoint
CREATE TABLE "usage_installs" (
	"id" uuid PRIMARY KEY NOT NULL,
	"first_seen_at" timestamp with time zone DEFAULT now() NOT NULL,
	"started_at" timestamp with time zone NOT NULL,
	"started_day" date NOT NULL,
	"existing_user" boolean DEFAULT false NOT NULL,
	"last_seen_at" timestamp with time zone DEFAULT now() NOT NULL,
	"environment" text NOT NULL,
	"app_version" text NOT NULL,
	"os_version" text NOT NULL,
	"device" text NOT NULL,
	"country" text,
	"traits" jsonb DEFAULT '{}'::jsonb NOT NULL,
	"backfilled_at" timestamp with time zone
);
--> statement-breakpoint
ALTER TABLE "app_errors" ADD CONSTRAINT "app_errors_install_id_usage_installs_id_fk" FOREIGN KEY ("install_id") REFERENCES "public"."usage_installs"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "usage_daily" ADD CONSTRAINT "usage_daily_install_id_usage_installs_id_fk" FOREIGN KEY ("install_id") REFERENCES "public"."usage_installs"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "usage_events" ADD CONSTRAINT "usage_events_install_id_usage_installs_id_fk" FOREIGN KEY ("install_id") REFERENCES "public"."usage_installs"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "app_errors_fingerprint_at_idx" ON "app_errors" USING btree ("fingerprint","at");--> statement-breakpoint
CREATE INDEX "app_errors_at_idx" ON "app_errors" USING btree ("at");--> statement-breakpoint
CREATE INDEX "usage_batches_received_idx" ON "usage_batches" USING btree ("received_at");--> statement-breakpoint
CREATE INDEX "usage_daily_day_idx" ON "usage_daily" USING btree ("day");--> statement-breakpoint
CREATE INDEX "usage_events_name_at_idx" ON "usage_events" USING btree ("name","at");--> statement-breakpoint
CREATE INDEX "usage_events_install_at_idx" ON "usage_events" USING btree ("install_id","at");--> statement-breakpoint
CREATE INDEX "usage_installs_started_idx" ON "usage_installs" USING btree ("started_at");