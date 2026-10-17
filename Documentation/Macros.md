# Macros

Macro tracking is on by default and can be hidden in You → Track macros. Optional daily gram goals live in You → Macro goals. Calories remain independent: changing a macro does not recalculate calories or a calorie goal.

- Store protein, total carbohydrates, dietary fiber, and fat in grams. Total carbohydrates include fiber (US/Canada definition). The daily summary and goals use Protein / Carbs / Fat. Food editors expose all four stored fields and read-only net carbs = total carbohydrates − fiber; we do not subtract sugar alcohols. Missing carbs or fiber leaves net carbs unknown. Fiber greater than total carbs is rejected.
- Quick Add and all search-result rows hide macros, but their add actions preserve the full nutrition payload. The pencil opens the editable nutrition fields. All 5,904 bundled foods (including 904 brand-name and restaurant-chain items) supply the four nutrients for their stated portions; see [Food catalog](FoodCatalog/README.md).
- Blank means unknown, not zero. Partial totals have a `+`; estimates have `≈`. Unknown historical entries remain unchanged until edited.
- Each entry stores optional per-serving nutrition and independent estimate flags in `macrosPerServingData`. EntryDraft JSON has an optional `macrosPerServing` object, so existing saved meals, barcode overrides, common-food defaults, and cached scan results still decode. Serving/calorie quantity changes and saved-meal multipliers scale macros with the same portion.
- Daily macro goals are optional grams. They use dated DailyGoal snapshots, preserving past goals. Disabling tracking hides macro controls/totals without deleting nutrition or goals. A calculated plan can fill them with suggested targets (protein at least, carbs and fat up to), in setup, plan revisions, or Macro goals → **Use suggested targets**; see [Onboarding](Onboarding.md#suggested-macro-targets-october-6-2026). Changing the calorie goal by hand doesn't change macro goals.
- FatSecret Premier v5 preserves protein, total carbs, fiber, and fat for the same selected serving as calories. Basic search preserves protein, total carbs, and fat when present; missing fiber stays unknown. Contradictory provider fiber is discarded without losing valid total carbs. Attribution follows the existing FatSecret food IDs.
- Open Food Facts `carbohydrates-total` includes fiber and is preferred. Otherwise add `fiber` to its available `carbohydrates` value. Both must be known to reconstruct total carbohydrates. Nutrients use the same serving/100 g basis as calories. Unknown values remain unknown.
- Photo, voice, and website meal imports request full-portion grams, then divide by the normalized serving count once. Their values are marked estimated. Existing photo/voice allowance and paid website-import rules stay intact.
- Manual/common/older foods can request **Estimate values using AI**. Only that entry’s name, portion and calories are sent; populated nutrient fields are preserved. Edits to the food/portion during the request prevent a stale estimate from being applied. A calorie-only shortcut (a bare number) never gets macros invented.

## Automatic fill-in (October 17, 2026)

While **Track macros** is on, `MacroAutoFill` (`App/Macros.swift`, unit-tested in `ECCTests`) fills blank macros on named foods without a button:

- **When:** right after any food is added or edited (`AppStore.add`/`update` call `consider`), and on every opening/return to the app over the last 30 days (`sweep`, which is also the one-time backfill). Turning Track macros on runs a sweep. A food qualifies when it has a name of at least two characters, calories above zero, and a blank protein, carbs, or fat.
- **Sources, in order, per blank nutrient:** (1) the same food logged before with macros (same Quick Add identity, or the same name without its amount), the most complete recent one, scaled by calories, keeping its estimate marks; (2) the built-in food list when the name, or the name without a leading amount ("2 oz", "a large", "two"), or its singular, exactly matches a food or alias (`CommonFoods.matching`), scaled by calories and marked ≈; (3) an AI estimate (`food/macros` with `automatic: true`), marked ≈.
- Local sources are applied synchronously in one save. AI estimates queue behind each other (App Attest needs one request at a time); fresh foods go to the front, backfill items are spaced 2.5 s apart to stay under the server's 30-requests-a-minute cap. A `macro_autofill_limit` reply (the 100-a-day safeguard) stops AI fill-ins until midnight UTC; a `usage_limit` reply (the per-minute cap) pauses 65 s (an hour after three in a row); three other failures in a row pause ten minutes or until the next opening.
- Never replaces a typed or existing amount (`AppStore.fillMissingMacros`, not counted as an edit; a filled fiber that would exceed typed carbs is dropped). Each entry is tried once per name/calories/servings (`macroAutoFillTried.v1`, pruned to the last 30 days), so a box someone empties stays empty until the food itself changes.
- Off under `--uitesting`/`--screenshots` unless a DEBUG test adds `--macro-autofill` (UI test `testMacrosFillInAutomaticallyAfterLogging` uses it with `--macro-estimate-fixture`).
- Stats counts: `macroAutoFill.history`, `macroAutoFill.builtIn`, `macroAutoFill.ai`; errors under `macroEstimate` (once per session).

Backend deployed October 17, 2026 as `dpl_4utW6jUoXVgVpqL7X6pyqtg6jt3w` (source `22a2fd7` plus only `api.ts`, `food-search.ts`, and the privacy page). The automatic path needs App Attest, so it's unit-tested rather than verified live; it needs a signed iPhone check.

## Barcodes (October 17, 2026)

The scanner asks our backend's `POST /api/v1/foods/barcode` first (FatSecret Premier's `food/barcode/find-by-id/v2`, curated label data, default serving with macros), then Open Food Facts when FatSecret doesn't know the product or can't be reached. Barcodes are sent to FatSecret as GTIN-13 (UPC-A gains a leading zero, EAN-8 is zero-padded). The lookup uses its own OAuth token with the `barcode` scope, so search keeps working if the account lacks it (the barcode call then fails and Open Food Facts answers). Any blanks left either way are filled by `MacroAutoFill`.

## Resetting saved food nutrition

Settings → **Saved food nutrition** → **Reset Saved Nutrition** removes the custom calories, serving sizes, and macros explicitly saved with **Save as default** on this device. A confirmation explains the scope and offers Cancel or Reset; the action is disabled when there are no saved overrides.

Affected foods use the current bundled catalog for future search, Quick Add, Siri, and meal-picker adds. Reset food IDs are retained locally so old diary snapshots cannot silently restore the removed values. Saving a new explicit default replaces that reset marker.

Existing diary entries (including their calories and macros), saved meals, barcode foods, goals, weigh-ins, and pins remain unchanged. The reset performs no SwiftData writes or Apple Health updates and does not sync to other devices. Tests and previews isolate these defaults in memory.

## Backend

`POST /api/v1/food/macros` requires the same signed device authentication as other private endpoints. Input: name, calories (whole amount), servingSize, servings. Output: protein/totalCarbs/fiber/fat, each a required number or null. No subscription is required and no successful-scan counter is incremented. Requests from the editor and macro sheet consume the existing account/day/month and global AI budgets, plus `MACRO_ESTIMATE_DAILY_LIMIT` (default 10 per account/day). Requests with `automatic: true` (the app's background fill-in, since October 17, 2026) skip all of those and the scan allowance; they only count toward a safeguard, `MACRO_AUTOFILL_DAILY_LIMIT` (default 100 per account/day, the owner's choice) and `MACRO_AUTOFILL_GLOBAL_DAILY_LIMIT` (default 50,000/day), plus the general 30-requests-a-minute account cap. Reaching either safeguard answers `macro_autofill_limit` (429), and the app stops automatic estimates until the server's day turns over (midnight UTC), keeping the waiting foods queued. Invalid requests fail before any reservation. Neither kind changes the ten-scan introductory allowance or when the upgrade appears.

Use `FATSECRET_API_TIER=premier` only after approval. Keep credentials and Fixie configuration server-side. No additional database migration is needed for the backend.

## September 23 nutrition contract

The app and backend now exchange `totalCarbs` and `fiber`; net carbs are derived and never encoded. Deploy the backend changes together with the next native release so online search, photo/voice, website imports, and estimates supply the new fields. The native search cache version is bumped to avoid stale nutrition. No historical data backfill or migration of old net-carb-only values is performed. Existing SwiftData attributes are unchanged; the new fields live inside the existing encoded nutrition data.

## Native release

The additive SwiftData fields are:

- UserProfile: `tracksMacros` (default true), `macroGoalsData` (optional Data).
- DailyGoal: `macroGoalsData` (optional Data).
- CalorieEntry: `macrosPerServingData` (optional Data).

Before an App Store/TestFlight release, deploy the corresponding CloudKit development schema additions to production and verify sync on physical devices. Simulator migration tests verify the older local schema upgrades without losing entries, goals, saved meals, or barcode overrides; they do not prove CloudKit production sync. This feature does not export nutrition to Apple Health.

## Provider references

- [FatSecret foods.search v5](https://platform.fatsecret.com/docs/v5/foods.search): selected-serving protein, total carbohydrate, fiber, and fat.
- [Open Food Facts nutrition schema](https://openfoodfacts.github.io/documentation/docs/Product-Opener/schemas/schemas/product_nutrition/): normalized carbohydrate excludes fiber; per-serving and per-100 g units.
