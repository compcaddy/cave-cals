# Macros

Macro tracking is on by default and can be hidden in You → Track macros. Optional daily gram goals live in You → Macro goals. Calories remain independent: changing a macro does not recalculate calories or a calorie goal.

- Protein, net carbs, and fat are grams. Net carbs means total carbohydrate minus fiber; we do not subtract sugar alcohols.
- Blank means unknown, not zero. Partial totals have a `+`; estimates have `≈`. Unknown historical entries remain unchanged until edited.
- Each entry stores optional per-serving nutrition and independent estimate flags in `macrosPerServingData`. EntryDraft JSON has an optional `macrosPerServing` object, so existing saved meals, barcode overrides, common-food defaults, and cached scan results still decode. Serving/calorie quantity changes and saved-meal multipliers scale macros with the same portion.
- Daily macro goals are optional, user-entered grams. They use dated DailyGoal snapshots, preserving past goals. Disabling tracking hides macro controls/totals without deleting nutrition or goals.
- FatSecret Premier v5 supplies nutrition for the same selected serving as calories. Missing fiber leaves net carbs unknown unless total carbs are zero. Basic search can supply protein/fat but generally lacks fiber. Attribution follows the existing FatSecret food IDs.
- Open Food Facts `carbohydrates` already excludes fiber; do not subtract it again. Nutrients use the same serving/100 g basis as calories. Unknown values remain unknown.
- Photo, voice, and website meal imports request full-portion grams, then divide by the normalized serving count once. Their values are marked estimated. Existing photo/voice allowance and paid website-import rules stay intact.
- Manual/common/older foods can request **Estimate missing**. Only that entry’s name, portion and calories are sent; populated nutrient fields are preserved. Edits to the food/portion during the request prevent a stale estimate from being applied. Nothing automatically backfills historical entries or invents macros for a calorie-only shortcut.

## Backend

`POST /api/v1/food/macros` requires the same signed device authentication as other private endpoints. Input: name, calories (whole amount), servingSize, servings. Output: protein/netCarbs/fat, each a number or null. No subscription is required and no successful-scan counter is incremented. The endpoint consumes existing account/day/month and global AI budgets, plus `MACRO_ESTIMATE_DAILY_LIMIT` (default 10 per account/day). Invalid requests fail before AI reservation. This limits free AI cost without changing the ten-scan introductory allowance.

Use `FATSECRET_API_TIER=premier` only after approval. Keep credentials and Fixie configuration server-side. No additional database migration is needed for the backend.

## Native release

The additive SwiftData fields are:

- UserProfile: `tracksMacros` (default true), `macroGoalsData` (optional Data).
- DailyGoal: `macroGoalsData` (optional Data).
- CalorieEntry: `macrosPerServingData` (optional Data).

Before an App Store/TestFlight release, deploy the corresponding CloudKit development schema additions to production and verify sync on physical devices. Simulator migration tests verify the older local schema upgrades without losing entries, goals, saved meals, or barcode overrides; they do not prove CloudKit production sync. This feature does not export nutrition to Apple Health.

## Provider references

- [FatSecret foods.search v5](https://platform.fatsecret.com/docs/v5/foods.search): selected-serving protein, total carbohydrate, fiber, and fat.
- [Open Food Facts nutrition schema](https://openfoodfacts.github.io/documentation/docs/Product-Opener/schemas/schemas/product_nutrition/): normalized carbohydrate excludes fiber; per-serving and per-100 g units.
