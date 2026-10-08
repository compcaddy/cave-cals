CREATE TABLE "discount_code_daily" (
	"code" text NOT NULL,
	"day" date NOT NULL,
	"visits" integer DEFAULT 0 NOT NULL,
	"store_taps" integer DEFAULT 0 NOT NULL,
	"applies" integer DEFAULT 0 NOT NULL,
	CONSTRAINT "discount_code_daily_code_day_pk" PRIMARY KEY("code","day")
);
--> statement-breakpoint
CREATE TABLE "discount_codes" (
	"code" text PRIMARY KEY NOT NULL,
	"name" text NOT NULL,
	"campaign" text NOT NULL,
	"offering" text DEFAULT 'discount' NOT NULL,
	"active" boolean DEFAULT true NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "discount_code_daily" ADD CONSTRAINT "discount_code_daily_code_discount_codes_code_fk" FOREIGN KEY ("code") REFERENCES "public"."discount_codes"("code") ON DELETE cascade ON UPDATE no action;