# Usage stats and error reports

Added October 3, 2026, for version 1.0.5. The app sends anonymous counts and error reports to the backend; the owner reads them at **https://cavecals.vercel.app/admin** (stats) and **/admin/errors** (errors, with Copy for AI).

## What the app sends

`App/UsageStats.swift` records everything. Counts are kept per local calendar day in `Application Support/UsageStats/state-v1.json` (excluded from backup) and sent as one small JSON batch to `POST /api/v1/stats` when the app goes to the background, or on opening if nothing has gone out for 6 hours. Recording is a dictionary increment; the file is written at most every 2 seconds on a background queue, so it never touches the typing or logging path.

- **Install ID:** a random UUID in the Keychain (`stats.install`), so reinstalling isn't a new person. It is never linked to the AI account, purchases, or RevenueCat.
- **Daily counts** (`usage_daily`): `opens`, `items.<method>`, `scans.<kind>`, `searches`, `searchesAbandoned`, `edits`, `deletes`, `undos`, `doneEating`, `progressViews`, `weighIns`, `progressPhotos`, `photoCompares`, `mealMoves`, `feedbackTaps`, `reminderTaps`, `barcodesNotFound`.
  - Methods (`LogMethod`): `quickAdd`, `searchHistory`, `searchBuiltIn`, `searchOnline`, `manual`, `meal`, `barcode`, `mealScan`, `voice`, `siri`, `copy` (Duplicate and add mode's Today list), `other`. They come from the entry's stored source unless the call site passes one (`AppStore.add(_:message:method:)`). Undo on the "added" banner subtracts.
  - Scan kinds: `mealScan`, `voice`, `barcode`, `recipe` (link import), `recipePhoto`, `recipeText` (pasted recipe text), `siri`, `voiceTyped` (Voice Log's **Type instead**). A scan is one capture that returned a result.
- **Events** (`usage_events`): `onboarding.step` {step}, `onboarding.choice` {buildPlan, justStart, skipConfirmed, skipDeclined}, `onboarding.finished` {goal: plan/manual/none, intent, weight, macros, macroTargets}, `macroTargets.saved` {from: setup/plan/goals} (suggested macro targets saved), `paywall.shown` {trigger, code}, `paywall.result` {trigger, result: closed/trial/purchased/restored/unavailable, product, code} (`code` only while a discount code is applied), `onboarding.source` {source: trainer/social/friend/appStore/google/ai/other, other} (`skipped` only from builds before October 7, 2026), `discount.code` {result: applied/notFound/error, code (applied only), from: setup/paywall} (see [Discount codes](DiscountCodes.md)), `rating` {answer: yes/no}, `notifications` {allowed}, `search.missing` {query}, `progressPhoto.saved` {source: frontCamera/backCamera/library, timer, ghost, angle: standard/custom; typed labels are never sent}, `mealTypes.mode` {mode: off/time/ask}, `mealTypes.edit` {action: add/change/delete, time, shortened; meal names are never sent}, `voice.typeInstead` (Voice Log switched to typing; what's typed is never sent to stats), `macros.breakdown` {kind: protein/totalCarbs/fat} (Home's macro breakdown opened; edits there count as `edits`), `macros.estimate` {scope: row/all, foods} (AI estimates asked for from that sheet), `progress.trends` {range: 30/90/all, or hours: calories/share} (Progress → Trends toggles), `progress.habits` {range} (Good Days vs. Over Days range changed), `coach.asked` {range, again} (Cave Coach asked for tips; again is true for Get new tips), `progress.onTarget` {rule: atOrUnder/withinPercent/overBy} (what counts as on target changed).
- **Paywall triggers** (`PaywallTrigger`): `onboarding`, `settings`, `aboutYou`, `mealScanOpen`, `mealScanAnalyze`, `voiceOpen`, `voiceAnalyze`, `newMealPhotoOpen`/`Analyze`, `newMealVoiceOpen`/`Analyze`, `recipeImportOpen`, `recipeImport`, `siri` (out of scans; spoken, no screen), `progressPhotos` (a second progress photo on one day).
- **Traits** (latest state, sent with every batch): goal, tracksWeight, tracksMacros, intent, plus, healthCalories, healthWeights, reminders, widget, iCloud, quickStart, doneEatingButton, mealTypes (off/time/ask), timeZone, model.
- **Errors** (`app_errors`): `UsageStats.shared.error(area, error)` with the Swift file and line filled in automatically. Areas (`StatsErrorArea`): `mealScan`, `voice`, `barcode`, `recipe`, `siri`, `search`, `macroEstimate`, `subscription`, `save`, `iCloud`, `appleHealth`, `weights`, `progressPhotos`, `discountCode` (a code check that failed, not a code that doesn't work), `coach` (Cave Coach couldn't write insights). Cancellations, the paywall's own `subscription_required`, and HealthKit's locked-device refusal are skipped; the same error from the same line is reported at most once a minute. URL errors keep only the path, never the query.
- **Never sent:** diary entries, logged food names, calories, macros, weights, calorie goals, or Health data. The only typed text is a search that found nothing in past foods, saved meals, built-in foods, or online (`search.missing`), the Other answer to “Where did you hear about Cave Cals?” (60 characters at most), and a discount code that worked (codes that don't work aren't sent).
- **Backfill:** the first report from an iPhone that already had diary entries includes daily item counts by method for entries created before stats started (the server accepts it once per install). People who had the app before stats are marked `existing_user` and started from their earliest entry, so they never count as new users.
- **Opt-out:** Settings → Usage stats → **Share anonymous usage stats** (`shareUsageStats.v1`, on by default). Turning it off discards anything unsent and stops recording, errors included.
- UI tests, screenshots, previews, and unit tests never record (`UsageStats.recordingAllowed`).

New features should count their key action and report the errors people see, the same way they add haptics.

## Backend

- `backend/src/server/stats.ts`: validation (`statsInput`), rate limits in their own buckets (never the device-registration budget), and one transaction per batch. `usage_batches` makes retries idempotent; counts are summed with `on conflict`.
- Unexpected backend errors (not `APIError`/validation) are stored as `source = 'server'` errors with the error type, code, and stack frames only, never the message, since messages can echo request content or upstream responses.
- Retention (daily cron): batch IDs 60 days, errors and `search.missing` 180 days, other events 400 days. Daily counts are kept.
- Migration `drizzle/0003_usage_stats.sql`.

## Admin pages

`/admin`, `/admin/errors`, and `/admin/codes` ([discount codes](DiscountCodes.md)) use HTTP Basic authentication: any user name, `ADMIN_PASSWORD` from the deployment's environment (no length rule, at the owner's choice). Without that variable both are a 404. `backend/src/proxy.ts` prompts and enforces the lockout (ten wrong passwords from one IP within an hour lock it out for an hour, even with the right password; counted in `ai_limits`); the pages and the Mark fixed action check the password again.

Days and weeks follow Pacific time (`America/Los_Angeles`), weeks start Monday. App Store installs only by default; **All builds** includes TestFlight and Xcode builds. Definitions:

- **New user:** first launch with stats, on an iPhone that had no diary before, by Pacific day.
- **Active:** opened the app or logged food that day. **Logging day:** a day with at least one item.
- **Items per day:** items ÷ logging days. **Active loggers:** people averaging more than 5 items per logging day over 30 days.
- **Retention by start week:** share of each week's new users who logged in their week 0 (first 7 days), 1, 2… measured from their own start day.
- **Went quiet:** active before, nothing for 7–60 days; sorted by the most telling last thing (left setup at a step, never logged, closed the paywall, hit an error, said "Not really", or how much they had logged).
- **Errors:** grouped by a fingerprint of source, area, code, message (numbers and IDs removed), and file. Mark fixed hides a group until it happens again. **Copy for AI** gives a Markdown report to paste into a coding session; the database can also be queried directly through the Neon tools.

## Testing

- Backend: `npx tsx --test backend-tests/stats.test.ts`. App: `UsageStatsTests` in the unit test bundle.
- Local end to end: `npm run dev` (uses the `backend-dev` Neon branch from `.env.development.local`, which also holds a local `ADMIN_PASSWORD`), then launch a Debug simulator build with `--stats-url http://127.0.0.1:3000` and background the app. Debug builds report `environment = debug`; without `--stats-url` they send to production, where they're hidden unless All builds is chosen.

## Release checklist

1. Run `npm run db:migrate` against production (`DATABASE_URL_UNPOOLED` for the production branch).
2. Set `ADMIN_PASSWORD` in Vercel (Production), then deploy the backend; changing it later needs a redeploy. Deploy before any 1.0.5 build reaches people; until then the app keeps its batches and retries.
3. App Store Connect → App Privacy was updated and published October 4, 2026: Other Diagnostic Data (Analytics, App Functionality), Coarse Location (Analytics; the country derived from each report's connection), and Analytics added to Search History, all not linked and not used for tracking. Product Interaction was already declared (linked, Analytics and App Functionality) because of the AI usage counters. `App/PrivacyInfo.xcprivacy` matches.
4. The privacy policy (`/privacy`, effective October 3, 2026) describes the stats; it goes live with the deploy.
