CREATE TABLE "clan_join_requests" (
	"clan_id" uuid NOT NULL,
	"person_id" uuid NOT NULL,
	"anonymous" boolean DEFAULT false NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "clan_join_requests_clan_id_person_id_pk" PRIMARY KEY("clan_id","person_id")
);
--> statement-breakpoint
ALTER TABLE "clans" ADD COLUMN "join_mode" text DEFAULT 'approval' NOT NULL;--> statement-breakpoint
ALTER TABLE "clan_join_requests" ADD CONSTRAINT "clan_join_requests_clan_id_clans_id_fk" FOREIGN KEY ("clan_id") REFERENCES "public"."clans"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "clan_join_requests" ADD CONSTRAINT "clan_join_requests_person_id_clan_people_id_fk" FOREIGN KEY ("person_id") REFERENCES "public"."clan_people"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "clan_join_requests_person_idx" ON "clan_join_requests" USING btree ("person_id");