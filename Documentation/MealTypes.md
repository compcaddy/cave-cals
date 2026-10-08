# Meal types

Optional sorting of the food log into meals (Breakfast, Lunch, …). Off by default: with it off, nothing about logging or Home changes, which was the point of Cave Cals never asking for a meal. Added October 6, 2026 (local source work; not in a build yet).

## Settings

Settings → **Meal types** (`MealTypeSettingsSection`, `App/MealTypeViews.swift`):

- **Track meal type** (`trackMealTypes`). Off: no meal types anywhere (Home, editors, scans, context menus).
- **Set meal by time of day** (`mealTypesByTime`), shown only while tracking. On by default when tracking is turned on.
- **Meal types** (`editMealTypes`) opens the list: rename, retime, reorder (Edit), add, or delete. A 24-hour strip shows each meal's time and any part of the day no meal covers ("No meal: 4:00 AM – 5:00 AM").

Every meal type has **one** block of time, or none. Snacks at different times are separate types. The defaults:

| Meal | Time |
| --- | --- |
| Breakfast | 5:00 AM – 9:00 AM |
| Morning Snack | 9:00 AM – 11:00 AM |
| Lunch | 11:00 AM – 2:00 PM |
| Afternoon Snack | 2:00 PM – 4:00 PM |
| Dinner | 4:00 PM – 8:00 PM |
| Dessert | no set time |
| Evening Snack | 8:00 PM – 4:00 AM (past midnight) |

A block includes its start minute, not its end, so 9:00 AM is Morning Snack. 4:00–5:00 AM is uncovered by default, so food logged then has no meal.

The type editor (`MealTypeEditorSheet`) requires a unique name (30 characters max) and rejects a time that overlaps another type ("Overlaps Afternoon Snack (2:00 PM – 4:00 PM)"). When the overlap is only at one end, it offers **Shorten Afternoon Snack to 3:00 PM – 4:00 PM** (`shortenMealType`); the neighbor's new time is saved together with this type. A new type starts in the first uncovered part of the day (or without a time if the day is fully covered). Deleting a type food was logged under hides it instead (`removed`), so those days keep their labels; it's no longer offered or used for new food.

## How food gets its meal

`AppStore.add` assigns every new entry's meal through `MealSettings.assignedMeal(chosen:at:)`:

- Tracking off: no meal.
- A meal picked in this add (editor chips, Add Meal, Review Scan): that meal.
- Otherwise, set by time of day: the visible type whose time covers the entry's time; outside every time, no meal.
- Otherwise (adding asks): no meal.

Copies made to log again never carry the original's meal, so coffee first logged at breakfast lands in Afternoon Snack at 3 PM: Quick Add/history drafts (`FoodHistory`), Duplicate and add mode's Today list (`MainView.add`), Siri's foods logged before, cached barcodes (`cacheBarcode` strips it), and saved meals (`saveMeal` strips it; `addMeal` takes the picked meal). Undoing a delete restores the food's meal.

**Set by time of day** leaves adding unchanged: one tap still logs. **Asking** (tracking on, time of day off) turns each one-tap add into the filled-in editor with the meal choice showing (`.chooseMeal` sheet, `EntryEditorSheet(choosesMeal:)`): Quick Start, Quick Add, add mode's Today list, search results and typed "pizza 300" rows, Duplicate, and known barcodes. The editor scrolls (only as far as needed, before the sheet finishes opening) so the chips show without the keyboard. A saved meal's + opens **Add Meal** with the chips; Review Scan shows one choice for all its foods above the list. Not picking leaves the food unspecified. Siri logs without a meal while asking.

The editor's **meal type** row sits above Time: for logged food in both modes (collapsed; tap to show chips, including **None**), and for new food only while asking (expanded, "Choose"). Editing logged food's time, by time of day, moves its meal along when the meal matched the old time.

## Home

With tracking on and anything that day filed under a meal, the day's log is grouped (`MealSections.group`) in the order of the meal list, each with an orange label and its calories lined up over the rows' calories (`mealSection-<id>`, "Lunch, 610 calories" for VoiceOver). Food with no meal (or a meal no longer in the list) goes last under **Other**. Labels are section headers, so the current meal's label stays at the top while scrolling through it. A day with no meals at all (every day before meal types were turned on) shows as before under "Today"/the date. Long-press → **Move to** files a food under another meal or **No meal** (`AppStore.setMealType`). Add mode's Today list stays a flat list.

New saved meals default to the current meal type's name while tracking ("Morning Snack"), else the usual time-of-day name.

## Storage and sync

- `CalorieEntry.mealType: String?` holds the type's id; nil is unspecified. Existing entries are never rewritten (that would re-upload the diary to iCloud and, since Apple Health sharing versions samples by `updatedAt`, rewrite every Health sample).
- `UserProfile.mealSettingsData: Data?` holds `MealSettings` (switches and the list) as JSON, synced with the diary so every iPhone on the account sorts the same way. Nil means meal types were never set up (off, with the defaults). Built-in types have fixed ids (`breakfast`, `morningSnack`, `lunch`, `afternoonSnack`, `dinner`, `dessert`, `eveningSnack`); added ones use a UUID. Renaming keeps the id. Every field except a type's id and name decodes when missing, so a list saved by a newer version still loads.
- `EntryDraft.mealType` is optional, so saved meals, barcode payloads, and drafts saved by older versions still decode; older app versions ignore it.
- Both new attributes are additive, optional SwiftData attributes: a lightweight migration, tested from the pre-meal-types store (`MealTypeTests.testUpgradeFromStoreBeforeMealTypesKeepsEverything`).

### CloudKit schema (must be done before release)

The production CloudKit schema for `iCloud.com.philstarkovich.cavecals` needs the two new fields, plus `CD_progressSettingsData` (Bytes) on `CD_UserProfile` for synced Progress settings (added October 8, 2026), or sync fails for records that use them (anyone who turns meal types on or changes a Progress setting). Not done yet: it needs a signed-in CloudKit Console session. Either:

1. **From a development build:** run a Debug build from Xcode on a test device signed in to iCloud (it syncs with the *development* database), turn on meal types, log a food, and wait for it to sync. CloudKit creates `CD_mealType` on `CD_CalorieEntry` and `CD_mealSettingsData` on `CD_UserProfile` in Development.
2. **Or by hand:** in CloudKit Console → the container → Development → Schema → Record Types, add `CD_mealType` (String) to `CD_CalorieEntry`, and `CD_mealSettingsData` and `CD_progressSettingsData` (Bytes) to `CD_UserProfile`. Match what the existing `CD_macroGoalsData` field looks like (if it has a `CD_macroGoalsData_ckAsset` Asset companion, add `CD_mealSettingsData_ckAsset` the same way).

Then **Deploy Schema Changes…** to Production and confirm only these additions are listed. Deployed fields can't be removed, but unused fields are harmless to every app version. Afterwards, check sync between two signed devices, including an older build editing a food that has a meal (it should keep its meal).

## Usage stats

`mealMoves` counts foods moved to another meal (Move to, or the editor's meal row on logged food). Events: `mealTypes.mode` {mode: off/time/ask} when the switches change, `mealTypes.edit` {action: add/change/delete, time, shortened}. Trait `mealTypes` (off/time/ask). The admin page shows "Foods moved to another meal" and the share of iPhones using each mode.

## Tests

- `Tests/MealTypeTests.swift` (unit): times across midnight, overlaps and shortening, the defaults and gaps, assigning by mode, copies dropping meals, editing while off, settings decoding and sync storage, sections, new meal names, and the store upgrade.
- `UITests/MealTypeUITests.swift`: Settings and the list (add, duplicate names, shorten a neighbor, delete), Home sections and Move to, the editor's None, asking from a typed food and from Duplicate, and Review Scan in both modes.
- DEBUG launch flags: `--meal-types time|ask` (meal types on at launch), simulator-only `--meal-types-sample` (a day of food yesterday and today at set times), and `--review-scan-fixture` (Meal Scan/Voice Log open straight to a two-food Review Scan).
