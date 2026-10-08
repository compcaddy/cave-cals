# Cave Coach tips, On-Target vs. Over Days, synced Progress settings — October 8, 2026 (backend live; app local)

- **Backend deployed to production** `cavecals-anmiv9noh-phils-projects-e15f8e11.vercel.app` (aliased to cavecals.com, www, cavecals.vercel.app) from the previous live tree (`/private/tmp/cavecals-coach-release`, deployment `i5kvcl4rs`) plus only `coach.ts` and `api.ts`: `insights/coach` with `format: "tips"` returns exactly 3 tips (title + detail) and takes `previousTips` so **Get new tips** brings different ones; requests without `format` still get the earlier write-up. The summary may carry the person's on-target `definition` and `underDays`; prompts say "on-target days". The unpublished Siri instruction change in local `ai.ts` was again excluded. The new live tree is kept at `/private/tmp/cavecals-tips-release`. Verified live: `/` 200, `/privacy` effective October 8, unsigned `insights/coach` 401. Backend typecheck and 57 unit tests passed beforehand.
- **App (local):** Cave Coach shows only three numbered tips under an app-written intro ("Based on your last 90 days, here are 3 tips for healthier eating habits:"); Get new tips replaces them; the disclaimer is just "AI suggestions, not medical advice." "Good Days" is now **On-Target vs. Over Days**, with three on-target choices (at or under the goal; within a percentage, editable; up to some calories over, editable), and days under a within-percent range are counted, not compared. Progress completeness is now 70% of that day's goal (70% of the 28-day average without a goal). Progress settings (week start, on-target rule, chart ranges) sync on the profile in the new `UserProfile.progressSettingsData` (**CloudKit production field still to deploy**, with the meal-type fields). Setting macros on a food fills the same food's other entries (blanks, AI estimates, and earlier shared values only).
- **Verification (iPhone 17 Pro simulator, iOS 26):** all 216 unit tests passed (1 skipped as before); all 10 Progress UI tests passed, including the on-target choices and Cave Coach with a stand-in; macro sharing UI test passed. Not verified: a real signed coach request (App Attest, Cave Cals+), real model tips, or iCloud sync of the new field between devices (needs the CloudKit schema and signed devices). No app upload.

---

# Cave Coach backend — October 8, 2026 (backend live; app local)

- **Deployed to production** `cavecals-i5kvcl4rs-phils-projects-e15f8e11.vercel.app`, aliased to cavecals.com, www, and cavecals.vercel.app. Source: the previous live release tree (`/private/tmp/cavecals-schoolbell-release`, deployment `rd3powske`) plus only `backend/src/server/coach.ts` (new), the `insights/coach` route in `api.ts`, and the privacy page's Cave Coach sentences with effective date October 8. The unpublished Siri instruction change in local `backend/src/server/ai.ts` was excluded. The deployed tree is kept at `/private/tmp/cavecals-coach-release` as the base for the next deploy.
- `insights/coach`: Cave Cals+ only (`subscription_required` otherwise), `COACH_DAILY_LIMIT` (default 3 a day, not set in Vercel) plus the shared AI budget; structured OpenAI output; input is the app's summary only. No migration.
- Verified live: `/` returns 200; `/privacy` shows the Cave Coach sentences and “Effective date: October 8, 2026”; unsigned `insights/coach` is refused with 401 (device verification runs before routing). Backend typecheck and 55 unit tests passed beforehand. Not verified: a real signed coach request from an iPhone (needs App Attest and a Cave Cals+ account) or the quality of real model write-ups. The app side (Progress → Good Days vs. Over Days) is local only; no app upload. App Store privacy details may need Cave Coach summaries added.

---

# Cave Cals Dev reset permission fix — October 7, 2026 (local)

- Owner reported that reopening Dev after Reset Test Data stopped at “Unable to open your data” because “Caches” could not be removed. The reset incorrectly removed the standard sandbox directories themselves; iOS can protect those roots even though the app can delete their contents.
- Changed reset to enumerate and delete child items, including hidden files and nested directories, while preserving Application Support, Caches, and Documents. Missing directories from a partially completed older reset are accepted; other errors still propagate and retain the pending reset. Existing Dev identity and cloud/Health isolation guards are unchanged. Building the updated Dev scheme over the installed app lets its pending reset finish on launch; no uninstall is required.
- Verification: Dev Debug build and all five focused tests passed on iPad Air 11-inch (M3), iOS 26: two new filesystem regressions (protected roots and retry after partial reset), two existing isolation tests, and the full persistent-diary reset UI test. The permission regression uses a FileManager that refuses root deletion so it reproduces the device restriction on a simulator. Physical-iPad recovery needs the owner to run the updated build; no device install or upload was performed here.

---

# Website Schoolbell typography — October 7, 2026 (live)

- Replaced every Lacquer font use with the app's Schoolbell in the homepage wordmark, hero headline, Cave Cals+ label, and discount-code pages. Removed the unused Lacquer font and license assets. Existing screenshot artwork is unchanged.
- Published production deployment `dpl_HRQDURGC66YWevC9CktDVUszGexX` (`cavecals-rd3powske-phils-projects-e15f8e11.vercel.app`), aliased to `cavecals.com`. Release source was reconstructed and SHA-1 checked against the previous live deployment `dpl_FuymNhShdYSLZEh6b7tybX4z9txh`; only the four typography files and two removed font assets differ. The unpublished Siri AI instructions in local `backend/src/server/ai.ts` were excluded.
- Verification: local and Vercel production builds passed. Desktop and phone homepage layouts checked; live computed font is Schoolbell for the wordmark, headline, and Cave Cals+ label. `/` and `/AppleReview` return 200 with Schoolbell CSS and no Lacquer or `--font-cave` references (discount verification used a bot user agent to avoid visit counts). No native app upload.

---

# Influencer pricing configuration — October 7, 2026 (RevenueCat/backend live; app fixes local)

- **Apple rechecked live:** regular monthly `6809209344` remains $5.99 and regular yearly `6809209211` remains $29.99. Discount monthly `6819868378` is $4.99 and discount yearly `6819868267` is $29.99; both are **Ready to Submit**, with completed review screenshots and APPLEREVIEW instructions. All four are level 1 in group `22363962`; each monthly has a 3-day trial and each yearly a 7-day trial across 175 territories. App Store **1.0.4** is still live. No new app version/build, submission, release, price increase, or storefront-availability change was made.
- **RevenueCat completed:** imported both Apple discount products, attached both to `ai`, created `discount` (`ofrngd808b229da`), mapped annual/monthly packages to the corresponding `.discount` products, copied the published standard paywall, and published **Cave Cals+ — Influencer discount** (`wf49ce05ac0ae84ff8`). Saved package mappings and Published status verified in the dashboard. The regular default offering remains unchanged. The editor’s sample prices are placeholders; actual app prices come from StoreKit.
- **Campaign attribution completed:** retrieved public provider token `967948` from Apple’s Campaign Link generator, added `APP_STORE_PROVIDER_TOKEN` to Vercel production, and rebuilt the existing live deployment (not the dirty local source). New deployment `dpl_FuymNhShdYSLZEh6b7tybX4z9txh`, URL `cavecals-ne46xjqni`, is Ready and aliased to cavecals.com/www/cavecals.vercel.app. Live APPLEREVIEW redirect verified with `pt=967948&ct=applereview&mt=8`; code check verified without counting. All four `APPLE_PRODUCT_IDS` reverified. The redirect check contributed one App Store tap to APPLEREVIEW.
- **Admin checked:** `/admin/codes` is accessible through the owner's existing session and contains APPLEREVIEW only. Creator names/codes have not been supplied; Sarah was an example and was not created.
- **Privacy completed:** Other User Content now includes Analytics, reflecting the optional discovery-source free-text answer. Apple shows the change as published; existing App Functionality, linked identity and no tracking answers retained. Local `App/PrivacyInfo.xcprivacy` updated to match and plist validation passed. Product Interaction and Purchase History already include Analytics.
- **Local app fixes:** a saved code no longer falls back to regular prices when its offering is missing; the unavailable screen explains that the code is saved, offers retry and code editing, and Settings allows access to that recovery screen. A purchase callback from an obsolete offering is rejected. Code entry keeps the text intact while typing and normalizes on Apply, avoiding dropped characters from asynchronous uppercase rewrites. Added a missing-offering regression and expanded the existing UI test to reopen/apply the code sheet from the unavailable screen.
- **Verification:** final focused run passed all 8 tests on iPhone 17 Pro and all 8 on iPad Air 11-inch (M3), iOS 26.0.1, in the normal CaveCals scheme (7 discount-code unit tests + code-entry/paywall-sheet UI test per device). Result `/tmp/CaveCals-Referral-Verified-20261007.xcresult`; summary retained in the evidence folder. Earlier runs exposed a test-runner interruption and dropped characters during uppercase rewrites; the final input behavior and assertions were corrected and both devices passed. Plist validation and diff whitespace checks passed. Real sandbox purchases and restores remain unverified.
- **Release gates:** include the discount subscriptions with the app update; verify real purchase, trial eligibility, cancel and restore on signed iPhone/iPad using the normal app, not Cave Cals Dev; raise regular prices to $9.99/$59.99 when code entry is live, preserving all existing subscriber prices; add the actual creator codes. A release date is not yet specified, so no price increase is scheduled. The full local app also has unrelated unreleased features and CloudKit schema gates described below. See `Documentation/DiscountCodes.md` for the current checklist and `Documentation/Release/ReferralPricing/` for setup evidence.

---

# Cave Cals Dev — October 7, 2026 (local only; no device install or upload)

- Added a shared-source **Cave Cals Dev** scheme and **Dev Debug / Dev Release** configurations to the existing app/widget/test targets. App ID `com.philstarkovich.cavecals.dev`; widget ID `com.philstarkovich.cavecals.dev.QuickLogWidget`; separate widget group, Keychain service, and `cavecals-dev://` links. Normal Debug/Release identities remain unchanged. The project-generation script includes the extra configurations without a source fork.
- Dev's SwiftData store explicitly stays in its own app sandbox with CloudKit off. Its app/widget entitlement files contain only the Dev App Group; no production iCloud container, HealthKit, push, or App Attest. Health writes/deletes are also blocked in code. No Dev cloud container was created. Dev does not report usage stats or perform StoreKit purchases/restores/RevenueCat setup; existing authorized private AI test access remains available without weakening backend verification.
- **Settings → Cave Cals Dev → Reset Test Data** confirms a Dev-only wipe on the next cold launch, before any store opens. It clears Dev app data/preferences and the widget snapshot, preserving developer connection/access settings, credentials, server quotas, and system permissions. The reset checks both build flavor and exact app ID, retains its pending flag on failure, and prevents stores from opening after a failed reset. The screen explains closing/reopening the app. README includes physical-iPad build/signing steps and the AI/subscription limitations.
- Verified: Dev Debug simulator build/run on iPhone 17 Pro and iPad Air 11-inch (M3), iOS 26; 10 targeted identity/link/Health/purchase-blocking unit tests passed on each; the persistent-diary UI test passed on each (cancel reset, cold-launch persistence, reset, fresh setup, empty diary). The iPad check uses the existing iPhone compatibility layout. Initial UI harness failures were corrected for welcome-animation timing, reset-label lookup, and iPad window bounds; the final runs passed. A stalled first iPad simulator boot recovered after restarting that simulator. Normal CaveCals Debug simulator build and unsigned Dev Release physical-device build passed. Built app/widget IDs, display names, URL/shortcut definitions, and emitted simulator entitlement files were inspected; normal app identity is unchanged.
- Not verified: Apple registration/provisioning of the new Dev IDs/App Group, installation on the owner's physical iPad, hardware camera/microphone, or real private-key AI requests from Dev. Real subscription testing remains disabled for this initial local-only Dev flavor. No App Store/TestFlight upload, backend deployment, CloudKit modification, or real diary reset was performed.

---

# Siri food recognition — October 7, 2026 (local backend change, not deployed)

- Investigated a reported Siri failure for “naval orange” (intended “navel orange”). The existing local-first path already falls back to `food/describe`; a recent production request returned HTTP 200, but logs do not retain its text or result. Direct live OpenAI checks of both spellings succeeded before the change, so the original failure was not reproduced.
- Strengthened the shared spoken/typed food instructions to interpret obvious speech-recognition mistakes, accept recognizable food names without a database match, and assume one medium item or a typical serving when quantity is omitted. The instructions also apply to transcribed Voice Log. Local/history matching and server-verified scan access are unchanged. AI estimates remain separate from FatSecret food search.
- Verification: backend typecheck, production build, and all 52 backend unit tests passed. Focused `SpokenLoggingTests` passed on iPhone 17 Pro (iOS 26), including a new regression for unmatched speech reaching AI, saving all returned macros and serving counts, and reusing that nutrition from history. A mocked Responses SDK test covers corrected names and nutrition. Live OpenAI checks with the updated instructions passed for “navel orange”, “naval orange”, and “two naval oranges”. These direct model checks do not verify Siri recognition, App Attest, or a signed iPhone round trip. No backend deployment or app upload was performed.

---

# Voice Log “Type instead” — October 7, 2026 (backend live; app local)

- **App:** Voice Log has a small centered orange **Type instead** link under the card. It stops listening and shows a typed description box (Return adds a line; up to 2,000 characters) with **Analyze**; **Record voice instead** switches back and starts listening. Typed text uses the existing `food/describe` endpoint (one scan, paywall enforced). Also in this build: Home's first-days guide (labeled arrows to search and the capture buttons until food is logged on two days) and Quick Start limited to foods for the current time of day.
- **Backend:** `food/describe` accepts up to 2,000 characters (was 500) and allows line breaks and tabs (other control characters still refused); older apps are unaffected. The admin page names the `voiceTyped` scan kind. Privacy policy covers typed Voice Log descriptions (effective October 7). **Deployed to production** October 7 (`cavecals-1kf7ttohv`, aliased to cavecals.com, www, and cavecals.vercel.app); no migration. Verified live: `/privacy` shows the new sentence and date, `/` returns 200, `/admin` asks for a password, unsigned `food/describe` is refused.
- **Verification:** backend typecheck, production build, and 51 unit tests passed (the describe-input test now covers multi-line, 2,000-character, and control-character cases). Simulator (iPhone 17 Pro): build passed; UI test `testVoiceLogSwitchesBetweenTypingAndSpeaking` (new) and the two existing Voice Log link tests passed; unit tests for the Quick Start window and first-days guide passed. Not checked: a real typed analysis (needs App Attest and a signed device), the microphone restarting on **Record voice instead** on hardware, and iPad.

---

# “Where did you hear about Cave Cals?” and discount codes — October 6, 2026 (backend live; app local)

- **App:** after setup, before the offer, one question with seven answers and a discount code box (Trainer or coach and Social media open it; the rest get **Have a code?**), the system Paste button, and Apply. A code that works is kept in the Keychain for good and switches every paywall to its RevenueCat offering; other paywalls get **Have a code?**. Developer → Preview onboarding ends with the question. See `Documentation/DiscountCodes.md`.
- **Backend:** `POST /api/v1/discount/check` (unsigned, rate-limited in its own buckets), code pages at CaveCals.com/<code> with a counting App Store redirect (`APP_STORE_PROVIDER_TOKEN` adds the campaign token), `/admin/codes` to add, edit, and pause codes and see their counts and the question’s answers, and a privacy policy section on discount codes. Migration `0004_discount_codes` (two new tables) **applied to production** (5 migrations) and the backend **deployed to production** on October 6 (`cavecals-52me0eq63`, aliased to cavecals.com and www); this deploy also carried the other undeployed local backend work above (recipe photo/text imports, progress-photo and meal-type admin tiles, privacy sections). Verified live: CaveCals.com/AppleReview, the App Store redirect, home redirect for unknown codes, favicon 404, `discount/check` (APPLEREVIEW works, unknown is `code_not_found`), `/admin/codes` asks for the password, privacy shows Discount codes. Production has one code, **APPLEREVIEW** (“App Review”), named in the subscriptions’ review note; pause it after approval if you like.
- **Store setup:** App Store Connect (via `asc`, October 6): **Cave Cals+ Yearly - Discount** (`com.philstarkovich.cavecals.ai.yearly.discount`, ID 6819868267, $29.99, 7-day free trial) and **Cave Cals+ Monthly - Discount** (`com.philstarkovich.cavecals.ai.monthly.discount`, ID 6819868378, $4.99, 3-day free trial), both level 1 in the Cave Cals AI group, the same 175 territories with Apple-equalized prices, display names “Cave Cals AI Yearly/Monthly Discount”, review note with code APPLEREVIEW, and a review screenshot of the question with a code applied; both **Ready to Submit** (attach them when submitting 1.0.5). Vercel production `APPLE_PRODUCT_IDS` lists all four products (live with the deploy). Still open: the RevenueCat `discount` offering and paywall, `APP_STORE_PROVIDER_TOKEN` (until then code pages link to the plain listing), and on release day the regular prices raised to $9.99/month and $59.99/year keeping existing subscribers’ prices.
- **Verification:** backend typecheck, production build, and 51 unit tests passed (9 new). Against a temporary Neon branch copied from production (`discount-codes-test`, expires October 8; production untouched, since the `backend-dev` branch has expired): pages in any capitalization, the 404 for non-code paths, home redirects for unknown and paused codes, the App Store redirect with `pt`/`ct`, the code check (counted, preview not counted), bot visits not counted, and adding, pausing, and refusing a reserved code on `/admin/codes`. Simulator (iPhone 17 Pro): Debug build with no new warnings; 6 new unit tests (`DiscountCodeTests`) and UI tests `testDiscoveryQuestionAppliesADiscountCode`, `testDeveloperOnboardingPreviewEndsWithTheDiscoveryQuestion`, plus the existing onboarding-offer and both onboarding-preview tests passed. Not checked: the paywall’s **Have a code?** sheet and code prices (need RevenueCat offerings and a signed device), a real Paste, iPad, dark mode, and the largest text sizes.

---

# Meal types — October 6, 2026 (local)

- **App:** optional meal types (see `Documentation/MealTypes.md`), off by default so nothing changes until someone turns them on. Settings → Meal types: Track meal type, Set meal by time of day, and an editable list (one time block per type; defaults Breakfast, Morning Snack, Lunch, Afternoon Snack, Dinner, Dessert, Evening Snack; overlap check with a one-tap shorten-the-neighbor fix; a 24-hour strip shows uncovered times). By time of day, adding stays one tap; with it off, every one-tap add opens the filled-in editor with meal chips (saved meals in Add Meal, one choice per Review Scan). Home groups days that have meals under orange meal labels with calorie subtotals, Other last; long-press Move to. Usage stats add `mealMoves`, `mealTypes.mode`, `mealTypes.edit`, and the `mealTypes` trait.
- **Schema:** two additive optional SwiftData attributes, `CalorieEntry.mealType` and `UserProfile.mealSettingsData`; existing entries are untouched. **CloudKit production schema not yet deployed**: `CD_mealType` (String, `CD_CalorieEntry`) and `CD_mealSettingsData` (Bytes, `CD_UserProfile`) must be created in Development and deployed to Production before any build with this ships (steps in `Documentation/MealTypes.md`). Not done here: no CloudKit management token, and the CloudKit Console needs the owner's signed-in session.
- **Backend:** no API change. The admin page shows “Foods moved to another meal” and the share of iPhones using each meal type mode. Not deployed.
- **Verification:** simulator (iPhone 17, iOS 26) Debug build and a generic iOS device build; no new warnings. 19 new unit tests (`MealTypeTests`, including an on-disk upgrade from the pre-meal-types store) and the full unit suite (181) passed. 5 new UI tests (`MealTypeUITests`) passed, plus 12 existing Home, search, editor, and saved-meal UI tests. Home sections, the ask-mode editor, Settings, the list, the type editor, and Review Scan were checked by hand on iPhone 17 (light) and iPhone SE (iOS 18, dark). Backend typecheck passed. Not checked: CloudKit sync between devices (including an older build editing a food with a meal), iPad compatibility mode, largest text sizes, VoiceOver, and haptics on hardware.

---

# Progress Photos, Weekday Start label — October 6, 2026 (local)

- **App:** Progress gets a **Progress Photos** card below Weight history: a full-screen camera (Front/Back/Left Side/Right Side or a typed angle, a ghost of the last photo at that angle with an opacity slider, a 10-second timer, front/back cameras), library imports dated by when the photo was taken, an All photos browser with a week strip and Photo days list, a viewer with Edit/Share/Delete, and Compare (side by side or slider, with the time and weigh-in change, shareable). One photo a day is free; a second that day shows the Cave Cals+ paywall (new trigger `progressPhotos`). Photos are stored only on the iPhone (`Application Support/ProgressPhotos`, complete file protection, metadata stripped), included in iPhone backups, never uploaded or synced. The week-start row now reads **Weekday Start** with the day right-aligned, and “How averages work” is hidden. Camera permission text now mentions progress photos. Usage stats add `progressPhotos`, `photoCompares`, the `progressPhoto.saved` event, and error area `progressPhotos`.
- **Backend:** no API change; the app works without deploying it. The admin page names the `progressPhotos` paywall trigger and shows “Progress photos saved” and “Photo comparisons opened” tiles. The privacy policy gains a **Progress photos** section (on-iPhone only, metadata removed, in iPhone backups, never uploaded; effective date October 6). Not deployed: deploy before a build with this feature ships so the policy matches.
- **Verification:** simulator (iPhone 17) Debug build and a generic iOS device build with no new warnings. 13 new unit tests (`ProgressPhotoTests`) plus `ProgressTests` and `UsageStatsTests` passed; all 7 `ProgressUITests` passed, including new camera/timer/ghost/Compare/edit, library import (a real simulator library photo, dated from its metadata), and free-limit paywall tests. Backend typecheck and 42 unit tests passed. First device try (owner, October 6): the camera view was rotated 90° counterclockwise. Fixed in source the same day (rotation from `AVCaptureDevice.RotationCoordinator`, applied to the live view and to each photo just before capture); the fix compiles for device but is not yet rechecked on hardware. Not checked: the real camera on hardware (front/back switching, mirroring, the timer's tick sounds), the RevenueCat paywall and purchase continuing to the camera, StoreKit's offline membership fallback, restoring photos from a backup, VoiceOver, and iPad.

---

# Recipe import from photos and clipboard, recipe servings — October 5, 2026 (local)

- **App:** New Meal → Import a recipe now offers From link, From photo (up to 5 pages from Photos or the camera), and From clipboard (pasted recipe text, a picture, or a link). Imports bring the whole recipe and its serving count into the meal editor, whose new Servings row (also on Build it yourself, Snap, and Say) saves one serving's share; adding the meal logs 1 serving. No SwiftData/CloudKit schema change: the count is stored inside the existing meal components, and older app versions still log one correct serving. Camera permission text now mentions recipe photos.
- **Backend:** `meal/import` also accepts pasted `text` (20 to 20,000 characters) or 1 to 5 uploaded `uploadIds`, members only, one AI request per import; a `wholeRecipe` flag returns the full recipe plus `recipeServings`. Released apps (no flag) keep one-serving link imports. Usage stats add `scans.recipePhoto` and `scans.recipeText`; the admin page names them. Privacy policy text updated for recipe photos and pasted text (effective date October 5). Not deployed: deploy the backend before any build with this app change ships, or photo and clipboard imports fail with “Some request fields are invalid.”
- **Verification:** backend typecheck and 42 unit tests passed (including new link/text/photo import and input tests). The backend integration suite could not run: the local dev database password in `.env.development.local` is rejected, so the new multi-page upload integration test is unrun. Simulator (iPhone 17): build with no new warnings; 3 new unit tests plus the existing meal tests passed; UI tests `testRecipeImportChoicesAndServingsSplitAMeal` (new) and `testMealFromScratchAndScaledAdd` passed. Chooser, photo page strip (pick, number, remove), clipboard paste of text and of a link, and the editor's split totals were checked by hand. Not checked: a real AI import (needs App Attest and a deployed backend), the camera on hardware, pasting a picture, and iPad.

---

# Usage stats backend live, App Privacy updated — October 4, 2026

- **Source:** commit `a09c402` (usage stats, error reports, admin pages; see `Documentation/UsageStats.md`), on `main`. The app side ships with **1.0.5**; no 1.0.5 build exists yet. App Store Connect shows **1.0.4 Ready for Distribution**.
- **Database:** migration `0003_usage_stats` applied to production Neon (`ep-weathered-sun`, 4 migrations); six new tables, existing tables untouched.
- **Backend:** deployed to Vercel production (aliased to cavecals.com and cavecals.vercel.app), then redeployed after the owner set `ADMIN_PASSWORD`. Verified live: `/admin` and `/admin/errors` prompt for a password and refuse a wrong one; `/privacy` shows the October 3 usage-stats section; food search returns 200; unsigned `account/status` returns 401. A `debug` test report to `POST /api/v1/stats` was stored (country captured, retry not double-counted) and then deleted, so production stats tables are empty.
- **Admin password:** the owner set their own short value (a Sensitive variable, so `vercel env pull` shows only a placeholder). At the owner's request there is no length rule; instead ten wrong passwords from one IP lock it out for an hour.
- **App Privacy:** published in App Store Connect: Other Diagnostic Data (Analytics, App Functionality), Coarse Location (Analytics), and Analytics added to Search History, each not linked and not used for tracking (12 data types). `App/PrivacyInfo.xcprivacy` updated to match, including Product Interaction as linked.

---

# 1.0.4 (2) uploaded and version prepared — October 1, 2026

- **Source:** all 1.0.4 work was committed and `main` fast-forwarded to it (it had stayed at the 1.0.3 commit `dfb7839`). The build comes from commit `23f8407`, tagged `v1.0.4-build2`, on `main`. Release builds come from `main` from now on.
- **Fixes before upload:** the privacy manifest now declares the system boot time API (`NSPrivacyAccessedAPICategorySystemBootTime`, reason `35F9.1`) for the welcome animation's `ProcessInfo.systemUptime` clock. The search-cache unit test now waits for the background cache write; it had failed since writes moved off the main thread (the app behavior was correct).
- **Build:** **1.0.4 (2)**, build ID `1e18c7b3-4b02-405d-97c2-c48fd7483a0c`, uploaded with the asc CLI and processed **VALID**. It is explicitly in Internal Testers with What to Test notes. TestFlight's internal state was still PROCESSING when this was recorded. App and widget are both 1.0.4 (2). The exported IPA passed strict signature verification with production `aps-environment` and App Attest and `get-task-allow` false.
- **App Store version 1.0.4:** build 2 is attached. What's New (`1.0.4/AppStore-WhatsNew.txt`: “Build Plan” instead of the old “Me Build Plan”, plus a Meals bullet) and the new reviewer notes (`1.0.4/ReviewNotes.txt`, covering Health food sharing, Siri, notifications, the post-setup offer, and Developer settings) were saved and read back unchanged. The description and the seven new iPhone 6.5" screenshots (`AppStore/`, uploaded by the owner) match the local files. Release type is now **automatic after approval** (owner's choice), with phased release on. `asc validate`: 0 errors, 0 blocking (2 optional subscription promotional-image warnings). `asc review doctor`: no public-API blockers.
- **Not done:** the version was **not submitted for review**; the owner presses Submit for Review. App Privacy and Regulations and Permits can't be checked through the API. All production backend endpoints, including `food/describe`, respond, and the live privacy policy is the September 30 version.
- **Verification:** all 135 native unit tests passed on iPhone 17 (iOS 26). The signed Release archive and App Store export succeeded. Per the owner, device testing was already done; no UI suite or physical-device checks were run here.

---

# Welcome intro, logo first — September 30, 2026 (local)

- Follow-up: the welcome uses the new logo with CAVE CALS on one line (launch screen unchanged), capped at 250 pt, with more room between “Weight Drop.” and the buttons (about 76 pt on iPhone 17 Pro, up from 33). Checked on iPhone 17 Pro and iPhone SE.

- The logo now sits above the words and drops in first from the top (slight overshoot, then settles); the lines and button panel follow as before, and the whole intro runs about 50% slower (~2.5 s). The logo sizes to the free space above the buttons (about 290 pt on iPhone 17 Pro, 140 pt on iPhone SE) so the words never touch the buttons.
- Verification: simulator build passed; intro filmed frame by frame on iPhone 17 Pro and the resting layout inspected there and on iPhone SE (3rd generation). In dark mode the logo's dark lettering and outlines are hard to see on the dark background (not yet addressed).

---

# Welcome intro animation — September 30, 2026 (local)

- The welcome drops the app icon and starts blank, then slides in “You Eat.” (left), “App Track.” (right), “Weight Drop.” (left), springs the Cave Cals logo up from the bottom (slight overshoot, then settles), and slides the button panel up, about 1.6 s in all. Reduce Motion fades in place; revisions, returning to the welcome, and UI tests skip the intro.
- Verification: simulator build passed; the intro was captured frame by frame on iPhone 17 Pro and the final screen inspected; the largest-text welcome was inspected (same-size lines, no wrapping). Three focused onboarding UI tests passed on iPhone 17 Pro Max (`/tmp/cavecals-intro.xcresult`). Motion feel should be judged on a device.
- Local source only; no build uploaded.

---

# New launch logo — September 30, 2026 (local)

- The launch screen now shows the user-supplied Cave Cals logo (portrait caveman with phone above CAVE CALS lettering) instead of the square caveman artwork. The asset is renamed `LaunchLogo`; the image is flattened onto the launch cream and sized 850×1062, since the transparent 1122×1402 original produced a blank launch snapshot. The storyboard frame now follows the logo's portrait proportions at 72% width.
- Verification: simulator build passed; on iPhone 17 Pro the launch snapshot and the launch-to-welcome transition were captured and inspected after restarting the simulator. Before the restart the simulator kept drawing the previous launch image (and then a blank one) from a stale launch-screen cache. Physical iPhones may also keep an old launch screen until the app is updated or the phone restarts; not checked on hardware.
- Local source only; not in TestFlight **1.0.4 (1)**. No build uploaded.

---

# Me Info copy, age dial flick, and Quick Add removal label — September 29, 2026 (local)

- Follow-ups the same afternoon: step 2 is **Measurements** (weights keep one decimal, placeholder “0.0”), step 3 is **Usual Week**, **Set Goal** puts Lose/Maintain on the title row with “Current:” beside goal weight and a **Rate** label, and the welcome headline is much larger (fits on three lines even at the largest text size). Activity, pace, target, and splash art are still pending as files.

- Setup step 1 is **Me Info** with **Type** / **Age** headers; the third card reads **No Say** (VoiceOver: “Prefer not to say”). Dial numbers can no longer truncate (e.g. “1…” for 15), and a flick now carries across many ages before snapping instead of stopping after about one screenful. Quick Add's long-press **Hide for 2 weeks** now reads **Remove, No Add Often** (same 2-week snooze).

---

# Onboarding step redesign — September 29, 2026 (local)

- **Me info**: **Me type** picture cards (Man / Woman / Prefer not to say, user-supplied art resized into `SetupMan`/`SetupWoman`/`SetupPreferNotToSay`; stored raw values unchanged) and a swipeable **Me age** dial (13–100, default 40, top-center caret, selection haptics, VoiceOver adjustable). The reference-values note is gone. **You start**: imperial height accepts feet 3–7 and inches 0–11 only, jumping feet → inches → weight once a value is finished (a lone 1 inch waits for 10/11). **Usual Day** drops its subheader. **Set Goal** uses Lose / Maintain and shows the current weight beside the goal-weight label. **Your target** drops the starting-weight note, shows a grouped number, selects it on any tap of the card, and has tighter padding.
- Pending: art for the activity rows, pace rows, and target card (received only as chat previews, not files).
- Verification: simulator build passed. 22 focused checks passed on iPhone 17 Pro Max (all 18 onboarding UI tests, including both largest-text routes and a new feet/inches jump test; the three no-goal setup paths in other suites; and a new `ImperialHeightInput` unit test). Screenshots of each changed step were inspected; an early dial build opened off-center and then with hidden neighbors, and both were fixed and re-inspected. Results: `/tmp/cavecals-onboarding-steps-iphone.xcresult`. No iPad compatibility or physical-device check was run.
- Local source only; not included in TestFlight **1.0.4 (1)**. No build uploaded.

---

# Onboarding skip confirmation and tracking step — September 29, 2026 (local)

- **What do you want to track?** moved off the welcome screen to its own step just before the calorie target (after goal/pace; manual-only results also pass through it). The per-switch explanations were removed. Plan revisions skip the step. The welcome now shows only the artwork, headline, **Me Build Plan**, and **Just start tracking**.
- **Just start tracking** now asks **Skip plan?** (“Cave Cals help you pick daily calorie target to reach your goal. Take less than one minute.”). **No, me build plan** starts the plan; **Yes, skip plan** shows the tracking step (no progress bar, **Let’s go**, back returns to the welcome) and then finishes without a goal.
- Verification: simulator build passed. 20 focused iPhone 17 Pro Max UI checks passed: all 17 onboarding tests plus the no-goal setup paths in the weight-tracking, logging-link, and settings-goal suites. The alert, welcome, and both tracking-step screenshots were inspected; the alert's default-action emphasis was dropped because it rendered orange text on a blue fill, then the confirmation test passed again. Results: `/tmp/cavecals-skip-plan-iphone.xcresult`, `/tmp/cavecals-skip-plan-alert.xcresult`. No iPad compatibility or physical-device check was run for this change.
- Local source only; not included in TestFlight **1.0.4 (1)**. No build uploaded.

---

# Annual trial and optional onboarding offer — September 29, 2026

- **Live store configuration:** ASC CLI created and read back 175 introductory offers for yearly subscription `6809209211` / `com.philstarkovich.cavecals.ai.yearly`: `FREE_TRIAL`, `ONE_WEEK`, one period, start September 29, 2026, no end date. Creation reported 175 successful, zero failed. Only the subscription's existing territories were used; prices and availability were not changed. U.S. yearly price remains $29.99. Monthly's existing 3-day trial remains. Both subscription review notes now describe the yearly trial accurately.
- **Live RevenueCat configuration:** published “Cave Cals+ — Smarter logging”, paywall `wf1b822385543c4708`, default offering, project `783afc8e`. Introductory CTA is `Try for {{ product.offer_price_with_zero }}`; annual introductory copy shows the offer period free, then the full yearly price. The default preview retains standard annual/monthly pricing and **Continue**. Editor preview prices are samples, not the live App Store prices. The Published listing confirms September 29's edit. Older SDKs fall back to “Try for free”; SDK 5.90.0 supports localized zero amounts.
- **Local app:** new-user calculated, manual-target, and no-goal completion save setup, then show the optional RevenueCat offer. **Skip for now** remains available during loading and service failures; Close/Skip and successful purchase/restore enter Home. Confirmed active members bypass it. Existing profiles, revisions, and developer previews do not trigger it. RevenueCat/RevenueCatUI is pinned and resolved to 5.90.0; purchases still require backend verification.
- Verification: simulator build passed. Seven focused iPhone checks passed, including the dismissal gate, all three setup routes, existing profiles, preview isolation, and closing an unavailable offer before logging food. UI tests use fresh ad-hoc signatures and isolate live App Attest/StoreKit; they do not validate a real trial purchase. The iPhone unavailable-state screenshot was inspected. Three matching checks also passed on iPad Air 11-inch (M3) in iPhone compatibility mode (manual setup, no-goal setup, and closing an unavailable offer then logging). Results: `/tmp/cavecals-onboarding-trial-iphone.xcresult` and `/tmp/cavecals-onboarding-trial-ipad.xcresult`.
- The App Store offer and RevenueCat configuration are published; the onboarding implementation and SDK upgrade are **local source only**, not in TestFlight **1.0.4 (1)**. No app build uploaded. A signed-device sandbox check of eligibility, purchase, restore, and the actual remote paywall remains necessary before release. Updated local App Store description copy has not been submitted.

---

# Footer placement and search order — September 28, 2026 (local)

- The logging footer now occupies its own fixed-height row below a clipped list, keeping food rows above the reminders and search/capture controls. Keyboard avoidance remains enabled. Each changed search query recreates only the list so results start at the top; subsequent API responses preserve the current scroll position. History matches resolve synchronously and precede saved meals, built-in foods, and API matches.
- Verification: simulator build passed. Six focused iPhone checks passed across the initial run and a corrected search-fixture rerun: footer geometry across scrolling/keyboard/reminder/sheet transitions, search scroll reset and history-first ordering, Done eating/Reopen, unified search restoration, search-add/Undo, and brief background tab preservation. The initial search test used a broad term whose built-in matches pushed its API fixture outside the visible list; a unique fixture term corrected the test setup. All three footer/search/Done eating checks also passed on iPad Air 11-inch (M3) in iPhone compatibility mode. UI tests used fresh ad-hoc signatures and isolated diary/API fixtures.
- Results: `/tmp/cavecals-footer-search-iphone.xcresult`, `/tmp/cavecals-footer-search-iphone-rerun.xcresult`, and `/tmp/cavecals-footer-search-ipad.xcresult`. The intermittent physical-iPhone trigger was not reproduced on hardware. No camera, App Attest, production CloudKit, or subscription checks were performed for this layout change.
- Local source only; not included in TestFlight **1.0.4 (1)**. No build uploaded.

---

# Developer onboarding preview — September 27, 2026 (local)

- Added Settings → Developer settings → **Preview onboarding**. Reuses the new-user screens with blank answers and fresh in-memory diary/weight stores. **Close Preview** exits; calculated-plan, manual-target, and no-goal completion return to Developer settings. Real history, goals, macros, saved plan, weights, widgets, iCloud, and Health state are not changed.
- Verification: simulator build passed; one native isolation check and two iPhone UI walkthroughs passed, covering existing diary/weight/goal preservation, cancellation, fresh repeat sessions, and all completion routes. The manual-target replay also passed in iPad iPhone compatibility mode. Early iPad attempts hit test setup issues (home-transition timing and scrolling to Developer settings); unsigned incremental runs reused an old runner. The refreshed, ad-hoc-signed runner passed with the updated navigation helper.
- Results: `/tmp/cavecals-onboarding-preview-tests.xcresult` (3 passed) and `/tmp/cavecals-onboarding-preview-ipad-signed.xcresult` (1 passed). No physical-device or subscription verification was performed for this local preview change.
- Local source only; not yet in TestFlight **1.0.4 (1)**. No build uploaded.

---

# Onboarding tracking choices — September 27, 2026 (local)

- Welcome now asks **What do you want to track?** with explanatory **Track my weight** and **Track macros** switches, both enabled for new users. Calculated plans, manual targets, and no-goal setup all save the choices; later calorie-goal edits retain existing macro preferences. Calculated plans only add the starting weigh-in when weight tracking is selected.
- Verification: simulator build passed; 8 focused iPhone checks passed (2 persistence checks and 6 onboarding UI checks, including default-on, opt-out, calculated/manual/no-goal completion, and largest text). The iPhone welcome screenshot was inspected. Both iPad compatibility checks pass across the initial run and focused rerun: the initial opt-out test tapped the fixed footer while its switch was below it; the test now scrolls controls above the footer before tapping.
- Results: `/tmp/cavecals-onboarding-tests.xcresult`, `/tmp/cavecals-onboarding-ipad-tests.xcresult`, and `/tmp/cavecals-onboarding-ipad-rerun.xcresult`. No new subscription, Health, or physical-device verification was performed for this onboarding change.
- Local source only; not included in TestFlight **1.0.4 (1)**. No build uploaded.

---

# Weekly Recap chart labels — September 27, 2026 (local)

- Both metric cards now prefix their numeric ranges with **Range:**. Mini charts have compact weekday labels, a right-side value scale, and subtle axes/gridlines. More horizontal space separates the metric details from the narrower plots; calorie bars are slimmer and weight lines use smooth monotone curves through the recorded points, preserving missing-day gaps.
- Verification: iPhone build and the existing current-week navigation/PDF and largest-text UI checks passed (2/2). The normal-size screenshot was inspected; a follow-up centered day labels under their points/bars and passed the current-week check again (1/1). No new tests or iPad runs.
- Results: `test_sim_2026-09-27T17-07-38-772Z_pid86754_25b3a218.xcresult`, then `test_sim_2026-09-27T17-09-07-004Z_pid86754_9a7398b8.xcresult`. The initial test command used the wrong target name and was corrected before testing.
- Local source only; not yet included in TestFlight **1.0.4 (1)**.

---

# Current-week recap — September 27, 2026 (local)

- Weekly Recap now opens on the current calendar week, labeled **In progress**. The back arrow selects prior weeks. Export uses the selected week instead of silently substituting the last completed week, and labels current-week PDFs **In progress**.
- Weight averages/ranges remain independent of previous-week comparisons and calorie completeness. Verified the reported September 21–27 example: 7 weigh-ins average **193.3 lb**, min **192.0**, max **194.8**, with **No comparison yet** when there are no earlier weights. Today’s food remains excluded from completed calorie averages under the existing rule.
- Verification: 12 Progress calculation/PDF tests and the current-week/back/forward/PDF iPhone UI test pass across the initial run and focused rerun. An initial PDF assertion expected duplicate spaces that PDFKit normalizes; assertions now verify the actual min/max content. The current-week PDF was rendered and visually checked as one page.
- Results: `test_sim_2026-09-27T16-56-00-663Z_pid86754_8b77f62c.xcresult` (12 passed plus the PDF whitespace assertion failure); `test_sim_2026-09-27T16-57-24-331Z_pid86754_efa51b5c.xcresult` (first-week average/range/PDF regression passed). No new iPad testing.
- Local source only; not included in TestFlight **1.0.4 (1)**. No new upload or print job was sent.

---

# UI refinements — September 27, 2026 (local)

- Right-aligned the orange Help me decide link beneath the daily calorie goal in About You.
- About You now groups Track weight, Weight unit, and Today’s weight in one section, with Today’s weight at the bottom. Conditional visibility and editing behavior are unchanged.
- Made the Progress glyph's decline more gradual; the right endpoint is about halfway up the plot height. Preserved the hand-drawn axes, stroke weight, and template rendering.
- SVG preview inspected and iPhone simulator build passed. Cosmetic asset change only; no new behavioral tests. Not yet uploaded to TestFlight.

---

# Reset saved food nutrition — September 27, 2026 (local)

- Added Settings → Saved food nutrition → **Reset Saved Nutrition**, with a Cancel/Reset confirmation and a clear explanation of the scope. Removes custom calories, portions, and macros saved with **Save as default** on this device; affected foods return to current catalog nutrition for future adds.
- Local reset markers prevent Quick Add/search/Siri and new meal-picker selections from restoring removed defaults from older diary snapshots. Existing diary records, saved meals, barcode foods, goals, weights, pins, usage counters, and Health records are retained. No SwiftData schema or backend change is required. Test/preview food defaults are now isolated in memory.
- Verification: the iPhone confirmation/cancel/reset walkthrough passed and demonstrated an unchanged 250-calorie original log followed by a 110-calorie catalog add. All existing native tests passed. The new preference-isolation test initially expected an absent key instead of the pre-existing empty array; its assertion was corrected, and all three new reset tests passed on the focused rerun. Across these runs, all 123 selected tests pass. Confirmation screenshot reviewed on iPhone 17, iOS 26.0.1.
- Result bundles: `test_sim_2026-09-27T16-43-01-788Z_pid61538_0806e106.xcresult` (122 passed plus the assertion failure above); `test_sim_2026-09-27T16-44-50-752Z_pid61538_445e4875.xcresult` (3/3 reset tests passed). No additional iPad tests were run.
- Local source only. **TestFlight 1.0.4 (1) does not include this reset action**; no new build was uploaded for this change.

---

# Weekly Recap refinements — September 27, 2026 (TestFlight available)

- **1.0.4 (1)** is verified **VALID / IN_BETA_TESTING**, explicitly assigned to Internal Testers with the owner’s tester access confirmed. Build ID: `c6ae0929-55c7-45af-a63e-3cd6b30b1a44`. App/widget/project-generator versions match. The signed archive and App Store export succeeded; nothing was submitted for App Store review or publicly released.
- Weekly Recap now has individual weight/calorie cards, mini weekly charts, bold prior-week changes, and number-only ranges. Daily breakdown starts collapsed and resets when changing weeks; no incomplete-day count is displayed.
- The one-page PDF is titled **Weekly Recap**, shows full completed-week dates, highlights weight versus the previous week and average daily calories versus the current goal, and separates **Six-Week Trends** with a horizontal rule. The table includes small signed prior-week changes beside each average, with the latest row highlighted tan. Calculation/footer notes are removed.
- Verification: **120 tests passed, zero failures** on iPhone 17, iOS 26.0.1 (native suite plus the Progress UI walkthrough). The recap cards and rendered PDF were visually reviewed; PDFKit confirms one page. Test result: `test_sim_2026-09-27T16-21-52-927Z_pid61538_e4f76708.xcresult`.
- Strict recursive IPA signature verification passed. Production App Attest/CloudKit/push, HealthKit, App Groups, the production backend, and `get-task-allow=false` were verified in the exported package. Evidence and TestFlight notes are in [1.0.4](1.0.4/).
- A new additional distribution identity and matching app/widget profiles were created because this Mac lacked an existing distribution private key. No certificates were revoked. The private key is in the login Keychain; repository signing settings remain Automatic.
- No further iPad testing was run, at the owner's request. Physical printing, camera/microphone, App Attest, CloudKit production sync, Health export, and purchases are not established by the simulator results. No print job or App Store review submission was sent.

---

# Progress charts and trainer report — September 27, 2026 (local)

- Added the Progress header icon between About You and Settings; moved weight graphs/history here. Calendar week/month/year calorie charts support stacked approximate macros, calories only, and individual grams. Year views average complete calorie days by calendar week. Week start is locally configurable.
- The review defaults to the last completed week and emphasizes weight/calorie changes vs the prior week, with min/max, daily details, and independent coverage. Past calorie days below 60% of the preceding 28-day completed-day average are incomplete; missing/today/incomplete calorie data do not skew completed averages. See [Progress](../Progress.md) for exact rules.
- One-page four-week PDF preview, native AirPrint options, and PDF sharing are implemented. Synthetic PDF rendering was inspected and populated/empty reports are verified as one page.
- Verification: 10 new Progress calculation/PDF tests and the updated weight aggregation test passed. The iPhone chart/history/print-options walkthrough passed on iPhone 17, iOS 26 (`test_sim_2026-09-27T15-51-32-628Z_pid61538_c576171c.xcresult`). Week-start selection, large-text entry/print preview, and weight add/edit/delete and graph-refresh flows passed across focused iPhone runs. Visual review corrected zero-width bars; tap selection allows vertical page scrolling. Final simulator build passed and the isolated sample Progress page is open on iPhone 17.
- iPad verification is incomplete: an initial runtime-selection/compatibility test-gesture issue was investigated, and the final iOS 26 run was stopped at the owner's request. Do not claim an iPad pass. Physical printer discovery/output is unverified. No print job was sent. No TestFlight/App Store build was uploaded.

---

# Widget action routing — September 26, 2026 (local)

- Both widget sizes now use foreground App Intent buttons for the four logging actions. Search/Add opens today’s add mode with the search field focused; an existing sheet is dismissed before keyboard focus is applied. Widget background/summary/gaps use an explicit `cavecals://home` link to open today’s Home without a keyboard or capture sheet.
- The shared pending router retains widget requests through cold launch/onboarding. Existing logging URLs and Home Screen quick actions remain supported.
- Verification: app and widget simulator build passed; four focused routing/intent unit tests and two UI regressions passed on iPhone 17 Pro (iOS 26). Both UI regressions also passed on iPad Air 11-inch (M3), iOS 26, in iPhone compatibility mode. Tests cover cold search launch with usable keyboard, search replacing About You, and the background URL returning to Home. Physical Home Screen widget taps still need a signed-device check; these tests exercise the intent handler and app URL routing, not SpringBoard hit testing.
- Local source only. No TestFlight/App Store build was uploaded.

---

# Backward-compatible carbohydrate API — September 25, 2026

- Production backend now serves both macro shapes. Food search, photo/voice analysis, recipe import, and text macro estimates return `totalCarbs` and `fiber` for the upcoming app plus a derived `netCarbs` for released apps through 1.0.3. Unknown fiber still yields no net carbs (a known zero-carb food stays zero); results stored by the previous backend pass through unchanged. The OpenAI schema and stored data are unchanged.
- Source `d63cb63` deployed to Vercel production (`cavecals-agmsqa8eq-phils-projects-e15f8e11.vercel.app`, aliased to https://cavecals.vercel.app); an identical deploy a minute earlier was superseded. The deploy also carries the previously undeployed `dad3bc0` website copy (home-page App Store link fallback, privacy section on plans/weigh-ins).
- Verification: 29 backend unit tests, 13 integration tests on Neon `backend-dev`, TypeScript, and the production build passed. Live "Fuji apple" search returned e.g. 19.06 g total carbs, 3.3 g fiber, 15.76 g net carbs; `/` and `/privacy` 200, `/test` 404, unsigned account request rejected. The current simulator build showed carbohydrates and fiber on an online result. The app caches search results for up to an hour, so earlier queries can show stale blanks until then. No TestFlight/App Store build was uploaded.

---

# Bundled nutrition and total carbohydrates — September 23, 2026

- September 23, 2026 (local, not yet in a TestFlight build): the bundled catalog expanded to 5,904 foods — the unchanged original 1,000, 4,000 generic USDA FNDDS 2021-2023 / SR Legacy 2018 additions, and 904 brand-name and restaurant-chain foods. Generation, `--check`, the independent validator and ECCTests pass; see `Documentation/FoodCatalog/validation-report.json`.
- All 1,000 bundled foods now include protein, total carbohydrates, fiber, and fat per existing serving. The generator uses the checksum-verified USDA FNDDS archive for 990 entries and the FDA fruit poster for ten retained fruits. Every original ID, name, alias, serving, category, and calorie value is unchanged; generation and `--check` pass. Nutrient densities remain in component provenance.
- The native app stores `totalCarbs` and `fiber` separately. Daily summaries/goals use Protein / Carbs / Fat; food editors expose carbohydrates and fiber plus read-only net carbs (carbohydrates minus fiber). Unknown values stay unknown, and fiber exceeding total carbs is rejected. Search and Quick Add rows hide macros while preserving them on add. Populated nutrition fields select their values for replacement like the serving fields.
- FatSecret Basic/Premier, barcode lookup, and the shared AI schema use the new fields. Barcode normalization prefers explicit total carbohydrates or reconstructs them from available carbohydrates plus known fiber. Photo, voice, website imports, and text estimates share the four-field contract. No historical macro backfill is performed.
- Verification: 97 native unit tests passed on iPhone; the final 97-test suite also passed on iPad Air 11-inch (M3), iOS 26.0.1. The two focused nutrition UI tests passed on both iPhone 17 Pro and iPad iPhone compatibility mode. They verify hidden search/Quick Add macros, logged totals, populated pencil editing, persistence, goals, and optional display. The existing serving-field replacement UI test passed after narrowing its ambiguous row/pencil selector. Editor/home screenshots were visually reviewed. All 28 backend unit tests, TypeScript validation, and the backend production build passed.
- Final native result: `test_sim_2026-09-23T23-35-07-888Z_pid78903_9d79dec9.xcresult`; iPad UI result: `test_sim_2026-09-23T23-33-08-531Z_pid78903_48c82880.xcresult` under the local XcodeBuildMCP CaveCals workspace.
- Local source work only: backend changes have not been deployed, and no TestFlight/App Store build was uploaded. Deploy the backend with the next native release so online results and AI estimates supply total carbs and fiber. These changes use existing encoded SwiftData attributes; physical-device CloudKit, camera, App Attest, and purchase verification remain separate release checks.

---

# Short onboarding — September 22, 2026

- Fresh branch `codex/onboarding-and-launch` starts from fully pushed `35b5286`; no earlier changes were left uncommitted.
- Optional five-step setup plus welcome estimates an editable calorie target, with direct manual/no-goal routes. Existing profiles are not forced through it. Body details, activity, goal and pace stay in the protected local weight file; accepted calorie goals retain existing diary/iCloud behavior. See [Onboarding.md](../Onboarding.md) for primary sources and calculation limits.
- Verification: all 94 native unit tests passed after adding plan-detail deletion. Ten onboarding UI scenarios pass across focused iPhone runs, including metric/imperial conversion, manual-only cases, edited-target validation, keeping the goal/weight after forgetting details, back navigation, canceling revised answers, and both manual/calculated routes at the largest accessibility text size. The calculated-plan and minor/manual flows also pass in iPad iPhone compatibility mode. Manual-goal editing/cancel and a pending voice shortcut through setup pass. The voice shortcut test was updated from the old title to the current “Speak Food.” Visual review caught and fixed retained scrolling between steps and a truncated large-text button. The centered numeric field test now places the cursor at the trailing edge before replacing text.
- Follow-up: You can forget locally saved plan details without deleting the current calorie goal or weigh-ins. Revised plans offer Cancel at every step. The website privacy source describes plan storage, weight storage and Health export; it has not been deployed in this task. Backend TypeScript validation passes.
- Small-screen review: calculated setup and the largest accessibility text route pass on iPhone SE (3rd generation), iOS 26. Visual inspection found that the large-text fixed footer obscured the question; at accessibility sizes the actions now scroll with the content. The revised large-text route was retested successfully.
- Walkthrough review: a scripted iPhone simulator recording is included in the launch packet. It exposed metric pace labels rounding 0.25/0.75 kg to 0.2/0.8; labels now show the actual metric choices, and the calculated flow passed again. The recording uses synthetic test data.
- Older OS: calculated plan/weight integration and the minor/manual route pass on iPhone SE (3rd generation), iOS 17.2. Result bundle `test_sim_2026-09-22T19-43-49-958Z_pid70570_72b9ad13.xcresult` confirms the runtime; target and manual-route screenshots were inspected.
- Launch-path follow-up: the public website still showed “Coming to the App Store” despite the verified public listing. Source now falls back to the app's real download URL and includes a privacy link. Backend production build and TypeScript pass; a local production-server request with `APP_STORE_URL` empty confirms the correct anchor and no coming-soon text. The website changes remain undeployed.
- Input recovery: switching an oversized pasted height to feet/inches now uses checked integer conversion. A UI regression confirms no crash, a clear correction prompt, and successful continuation after correcting the height.
- Build follow-up: resolved the existing LoggingActionRouter Swift 6 isolation warning by resolving the shared router inside its main-actor method instead of in a default argument. Seven focused routing/shortcut tests pass, and the follow-up build reports no warnings.
- This is source work only, not an uploaded build or App Store release. Physical Health export, CloudKit production sync and App Attest remain separate release checks.

---

# Macros implementation — September 22, 2026

- Previous work was clean and synchronized with `origin/main` at `dfb7839` before creating `codex/macros-tracking`. This feature is a separate changeset.
- Optional macro tracking defaults on. Protein, net carbs, and fat flow through daily totals, food editors, logged/search/Quick Add rows, barcode results, photo/voice review, website imports, saved meals and serving multipliers. Optional daily gram goals live in You. Unknown values stay unknown; partial totals and AI estimates are marked. Old history is not backfilled.
- Added authenticated free `food/macros` estimates with a 10/day account cap and existing AI budgets. They preserve populated fields and do not spend the shared photo/voice allowance. Updated privacy text and provider mappings. See [Macros.md](../Macros.md).
- Verification: 84 native unit tests pass, including real on-disk upgrade from the pre-macro SwiftData schema; macro add/edit/goals/disable/re-enable UI passes on iPhone and iPad compatibility mode. Search title-edit/plus-add/Undo and unified search restoration also pass. Backend production build passes, with 28 unit and 13 isolated development-database integration tests passing. The integration route test verifies free macro access, rate limits, and unchanged scan counters. A pre-existing LoggingActionRouter actor-isolation warning remains.
- Live FatSecret Premier access through Fixie was verified: Urbane Cafe returned 25 results; Crunchy Peanut Salad returned 560 calories, 37 g protein, 38 g net carbs and 25 g fat for one salad. Production `FATSECRET_API_TIER=premier` is enabled. Backend source `809e972` deployed successfully as `dpl_5gBnK9MkrWpv16ib1Y5ZczZxXtzs`, aliased to https://cavecals.vercel.app. Live search returned the same restaurant macros with a 3,600-second cache lifetime. A real free-account estimate for two boiled eggs returned 12.6 g protein, 1.2 g net carbs and 10.6 g fat; successful-scan and regular-log counters were unchanged. An unauthenticated macro request returned 401. The current native app builds and launches in the iPhone simulator.
- This is not an App Store/TestFlight upload. App/widget versions remain 1.0.3 (3). Before releasing the native feature, deploy the additive CloudKit fields described in Macros.md and verify physical-device sync. Physical camera/microphone, App Attest and purchase behavior are not proven by simulator tests.

---

# Attribution update — September 21, 2026

- Owner received FatSecret Premier Free access. Added the required `Powered by fatsecret nutrition API (www.fatsecret.com)` to App Store 1.0.3’s description and verified it by reading the saved localization. Preserved the owner’s other listing edits. The live website already contains the exact approved attribution link.
- Native attribution now follows FatSecret-backed foods into local search/history, Quick Add, saved meals, food editors and meal editors/add screens, using a reusable approved text link and the stored `fatsecret:` identifier. Existing You/About attribution remains.
- Prepared **1.0.3 (3)** with matching app/widget/generator versions. Simulator build, both focused search editing/add/Undo UI checks on iPad, Release archive, App Store export, and strict signature verification passed. Exported app retains production App Attest/CloudKit, HealthKit, and App Groups entitlements.
- App Store version 1.0.3 was observed as WAITING_FOR_REVIEW with build 2 during this follow-up. The owner had submitted it after the earlier preparation below. Build 3 (`d04f0d9a-5913-4a54-8a4e-a87bebdf5612`) processed as VALID and was explicitly added to Internal Testers. Replacing the queued build requires withdrawal and resubmission, so the existing review is unchanged pending the owner’s choice.
- Source commit: `fffbfe9`, pushed to `origin/main`. Premier API-tier configuration is separate and was not changed in this attribution task.

---

# Current release preparation — September 21, 2026

- Live Apple status was rechecked: App Store version 1.0 is READY_FOR_DISTRIBUTION and its review submission is COMPLETE. The September 17 rejection/signing notes below are historical, not current blockers.
- Prepared app, Quick Log widget, and project generator as **1.0.3 (2)**. Created App Store version 1.0.3 (`4335c968-c59e-4bca-b90d-df21c8c67c28`) with manual release control and copied the existing listing. Updated description, What’s New, and reviewer notes are in `1.0.3/`.
- Release archive and App Store export succeeded using Xcode automatic signing. Exported app/widget versions match. Strict recursive signature verification passed. Exported app has production App Attest/CloudKit, HealthKit, App Groups, and `get-task-allow=false`; backend origin is `https://cavecals.vercel.app`.
- Apple processing rejected build 1 with ITMS-90683 because HealthKit also requires `NSHealthShareUsageDescription`. Added the missing explanatory string without expanding the write-only Health authorization; rebuilt and uploaded build 2.
- Archive: `/tmp/CaveCals-1.0.3-2.xcarchive`; IPA: `/tmp/CaveCals-1.0.3-2.ipa`. Apple processed build `4d6bad88-f68e-4bfb-9a69-4371ba5002f9` as VALID. It is attached to version 1.0.3 and explicitly belongs to Internal Testers (`0aa5b575-10c4-4ef9-9cc7-4a50257b7816`), with internal state IN_BETA_TESTING. Non-exempt encryption is false.
- Release validation: 77 tests passed on iPhone 17 Pro (74 native unit tests and three weight UI tests); all 36 backend tests passed (24 unit, 12 isolated development-database integration). Production Urbane Cafe search returned HTTP 200 with 25 results, including eight Urbane items. All eight targeted iPad UI checks passed across the initial run and the focused photo-picker rerun. The photo-picker test now taps the actual image tile instead of a fixed full-screen coordinate; this fixes its iPhone-compatibility-layout failure.
- This build includes weight tracking/optional Apple Health export, FatSecret restaurant search, safe search caching, the shared 10-scan/100-entry introductory allowance, compact editable search rows, local search ranking, and widget refinements. Backend changes and the additive database migration were already deployed before this native release.
- App Store validation reports zero errors / zero blocking checks. Two warnings concern optional subscription promotional images. API validation cannot verify App Privacy publication; no cached Apple web session was available for deep validation. Version 1.0.3 remains PREPARE_FOR_SUBMISSION with manual release control; nothing was submitted for review or publicly released in this task.
- Physical-device Health permission/export/corrections and purchase/restore checks are still pending owner confirmation before review submission, per the weight-tracking release checklist. Real camera/microphone, production App Attest and CloudKit sync also are not proven by simulator fixtures. Trainerize delivery is not verified.

---

# Current release status — September 17, 2026

- Resubmission preparation: saved `ResubmissionReviewNotes.txt` into the live App Review details, with no demo account required. Verified Mainland China territory availability is `false` (`CANNOT_SELL`). The rejected App Store version remains 1.0 and the review submission remains `UNRESOLVED_ISSUES`; nothing was submitted. Latest uploaded build is still 1.0.1 (3), so do not submit until a current build is uploaded/selected and physical-iPad purchase/restore/paid access is verified. The reported Restore Purchases error has not been confirmed resolved.
- Current signing blocker: the login keychain exposes only an Apple Development code-signing identity, not a usable Apple Distribution identity. Xcode's previous export logs also report a missing account token. Restore the distribution identity/private key or refresh Xcode's Apple-account signing access before archiving/exporting the next build. No signing certificates were revoked or replaced during this preparation.
- The screenshot direction was revised again after owner feedback. The current set is `Screenshots/2026-09-17-v2/store/`: photographic silver iPhone frames, large headlines only, cream/blue/orange app colors, large logo only on the first panel, and a real Meal Scan UI capture using an AI-generated realistic meal photograph. `ReleaseScreenshotTests/testCaptureMealScanMarketing` passed. The previous uploaded set is backed up in the v2 `previous/` directory.
- Goal setup now displays the actual colored drumstick app icon above the three-line headline. New screenshot captures and five cream/branded marketing panels live in `Screenshots/2026-09-17/`; the previous App Store images were backed up before replacement. All 55 native unit tests and two focused UI tests (goal setup/settings and release screenshot capture) passed. The once-daily suggestion regression now checks ranking suppression rather than exclusion with six foods in a ten-slot list. See `SubmissionPlan.md` for current release gates, especially the unresolved physical-device restore error and review objections.
- Cave Cals+ branding is implemented locally in Settings with a new branded logo asset, premium-focused copy, a smaller restore action, active-member-only subscription management, and legal links at the bottom of Settings. The published RevenueCat paywall is now named **Cave Cals+ — Smarter logging** and uses matching customer-facing copy without changing its products, prices, purchase behavior, restore action, renewal disclosure, or legal links. App Store Connect's editable internal reference names and review notes were updated to Cave Cals+; the customer-facing subscription localization remains locked in the unresolved rejected submission and still needs updating when Apple makes a new subscription version editable.
- These Cave Cals+ source changes are newer than TestFlight **1.0.1 (3)** and are **not** in that build. Upload a new incremented build and verify its processing/group membership before telling testers that the branding is available in TestFlight.
- TestFlight **1.0.1 (3)** was uploaded September 17 and verified as VALID / IN_BETA_TESTING in the explicit Internal Testers group. The group contains the account-holder tester `phil.starkovich@gmail.com`. Apple reports `usesNonExemptEncryption: false`. Build 3 contains the current unified home-screen work and the paywall-navigation fix described below. Nothing was submitted for App Store review or released.
- The app and Quick Log widget now both use marketing version **1.0.1** and build **3** in every project configuration and in `scripts/generate_project.rb`. The signed archive and exported IPA were inspected before upload; both embedded bundles reported 1.0.1 (3), and the complete app passed strict code-signature verification with the Apple Distribution identity.
- Apple rejected App Store 1.0 (1): mainland China distribution with OpenAI functionality/metadata, and a subscription page that disappeared on iPad Air 11-inch (M3), iPadOS 27.0. The uploaded paywall fix replaces nested SwiftUI sheets with destinations in the existing navigation stacks and gates duplicate RevenueCat/app dismissal requests. The simulator build, nine AI integration tests, and the dismissal regression test on iPhone 17 Pro and iPad Air 11-inch (M3) iPadOS 26.0.1 passed. Build 3 still needs physical-iPad sandbox purchase, cancel, restore, and paid-feature tests, ideally on iPadOS 27.0, so the rejection is not yet confirmed resolved. Removing mainland China was recommended, but no availability change was verified in this task.
- Before resubmission, verify the paywall on a fresh physical-device/TestFlight install, including purchase, cancel, restore, and unlocking paid features. iPhone-only targeting does not eliminate iPad compatibility testing.
- Xcode's saved Apple-account entry is stale and cannot automatically export an App Store archive. Build 3 was exported with a newly created App Store distribution certificate and explicit app/widget provisioning profiles, then uploaded through the working App Store Connect API-key profile. Recheck signing/account status when distributing; do not assume credentials or agreements remain valid.
- Simulator builds and targeted tests passed for unified search/list restoration, repeated adds/Undo, logging deep links, and preserving Logged after a brief background transition. Camera freeze timing and microphone animation still need physical-device verification. Not every UI test has been rerun after the redesign.

The September 6 notes below are historical; their build, submission, metadata, and account status claims must be rechecked rather than treated as current.

---

# Cave Cals release readiness — September 6, 2026

Status: version 1.0 build 5 is VALID and ready in the Internal Testers group. It adds device-key recovery and diagnostics, removes the photo explanation panel, and adds calories to the small widget. Build 3 remains available for internal testing. Build 3 adds private production access testing and automatic production routing without a developer token. See DeveloperAccess.md. Build 2 remains available in Internal Testers. It includes the latest typography, settings, capture flows, and white/black app icon. **Not yet ready for App Store submission**; the remaining checks below still apply. Nothing has been submitted for App Store review or released.

## Completed

- iPhone-only app, bundle `com.philstarkovich.cavecals`, CaveCals project and scheme. Mac and Apple Vision availability are disabled in App Store Connect.
- Requested suggestions copy, larger light text and additional horizontal padding.
- RevenueCat SDK 5.88.0, `ai` entitlement, `default` offering, monthly and yearly products, published cave-themed paywall. Native fallback uses Schoolbell and cave icons. Remote custom font upload remains pending.
- $9.99/month with eligible 3-day trial; $59.99/year without trial. StoreKit supplies localized prices. The remote paywall uses price and relative-discount variables rather than fixed preview numbers.
- Only meal scanning and voice logging require payment. Backend authorization remains independent of client/RevenueCat UI state.
- Production backend deployed at https://cavecals.vercel.app with Neon, private Vercel Blob, OpenAI credentials, quotas and cleanup. No server secrets are in the app.
- Apple production and sandbox server notifications both point to RevenueCat.
- App Store 1.0 build 1 processed as VALID and attached. Manual release selected. Build 2 archive/export also succeeded; latest IPA is `/tmp/CaveCals-Build2-Export/CaveCals.ipa`. The exported signature was verified; production backend, App Attest, CloudKit environment, and matching app/widget build numbers were checked.
- Three iPhone 6.9-inch screenshots uploaded; source files are in `Screenshots/`. Description, keywords, category, age rating, privacy URL and free app availability configured.
- App Privacy questionnaire saved: media, health/food content, identifiers, purchases and usage; no tracking. Search history disclosed as not linked. Final legal publish confirmation remains for the owner.

## Validation

- 36 native unit tests passed after RevenueCat integration.
- Release screenshot UI test passed. After the capture-flow redesign, 36 native tests plus 2 focused UI tests passed (38 total): photo selection/removal and automatic voice recording without an upfront paywall. Real camera capture and purchase continuation still require device testing.
- Nine backend tests passed; production dependency audit reported zero vulnerabilities.
- Synthetic chicken/rice/broccoli image and spoken lunch both produced identifiable food items through live OpenAI calls; retry returned the cached result. See `live-ai-smoke.json`. This verifies the pipeline, not nutritional accuracy.
- A scoped private Blob upload above 2 MB succeeded; authenticated retrieval succeeded, anonymous retrieval failed, and the fixture was deleted.
- Production homepage/privacy return 200; developer tester returns 404; unauthenticated paid endpoints return 401.
- A broader legacy UI suite initially reported 4 passes and 8 failures, including stale selectors and offscreen controls. Tests were updated for the current labels, drawer, serving controls and navigation. The rerun exceeded the MCP tool’s 300-second timeout and was interrupted after the Mac locked; it is **incomplete, not passing**. Rerun the UI suite on the unlocked Mac and resolve any remaining failures before release.

## Remaining before submission

1. Provide a public support/privacy/deletion email and Apple review contact phone. Finish the support page, replace the privacy contact placeholder, and set App Store support URL/review details.
2. Review and click Publish in App Store Connect → App Privacy. Apple’s final dialog includes an agreement about legal accuracy and keeping disclosures updated; owner confirmation is required.
3. Unlock the connected iPhone and test the TestFlight build: App Attest registration, monthly trial, yearly purchase, restore after reinstall, cancellation/expiration and unpaid AI rejection. The development app installed successfully, but launch was blocked by the device lock. Simulator/local AI tests do not verify production device attestation.
4. Capture the actual subscription purchase screen for both subscriptions’ App Review screenshot fields. Both products currently report MISSING_METADATA. Include both subscriptions with the first app review submission.
5. Verify/deploy the production CloudKit schema for `iCloud.com.philstarkovich.cavecals`; test persistence and sync between devices. CLI access requires a CloudKit management token, which is not configured. Browser verification was also blocked after the Mac locked. Follow Apple’s [schema deployment guide](https://developer.apple.com/documentation/CloudKit/deploying-an-icloud-container-s-schema).
6. For the remote paywall Schoolbell font: Chrome → Extensions → ChatGPT browser extension → Details → Allow access to file URLs. The extension rejected the font upload. The paywall is published with its current fallback font.
7. Check any outstanding Apple account agreements and App Store Regulations and Permits declarations. Do not infer legal status from the CLI doctor report.
8. Rerun `asc review doctor --app 6809208501`, review the build on device and submit only after these checks pass. The latest report is `review-doctor.json`; it does not cover every privacy/legal/purchase requirement.

## Review notes draft

No app account or login is required. Barcode scanning, food search, manual calorie entry, diary/history, saved meals and widgets are free. Only meal photo analysis and voice logging require an auto-renewable subscription. Open Settings to view Cave Cals AI and restore purchases, or choose Meal Scan/Voice Log. The monthly plan has an introductory free trial for eligible users; the yearly plan has no trial. A real iPhone is required for App Attest. Apple sandbox purchases are accepted by the production backend after signature and server verification. Voice Log records locally on opening; Meal Scan opens the camera or lets the user select a photo. Tapping Analyze sends the selected media to OpenAI only after paid access is verified. If needed, a RevenueCat paywall opens at that point and successful purchase/restore resumes analysis. The screen explains this upload behavior, and users review/edit estimates before saving.

Do not place keys, purchase JWS values, developer tokens or private contact information in this document.
