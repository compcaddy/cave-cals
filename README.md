# Cave Cals

A native, iPhone-only calorie logger built with SwiftUI and SwiftData. Supports iOS 17 and later. No signup is required. Manual logging is local-first; optional photo and voice estimates with an introductory free allowance use a secure backend and OpenAI.

## AI backend

Photo and voice logging use the Next.js backend in `backend/`, with Neon Postgres, server-verified Apple subscriptions and direct private uploads. Production is deployed at https://cavecals.vercel.app. RevenueCat supplies subscription offerings and the published paywall; Apple verification on the server controls paid access. See [current release readiness](Documentation/Release/Readiness.md) for completed work and remaining submission checks. Follow [the backend setup and release checklist](Documentation/BackendSetup.md) for local testing, your OpenAI key, App Store products and Vercel deployment.

## Open and run

Open `CaveCals.xcodeproj`, select the **CaveCals** scheme, choose an iPhone simulator, and run. The project is already generated; you do not need a project-generation tool to open it.

- Bundle identifier: `com.philstarkovich.cavecals`
- Deployment target: iOS 17.0
- Supported device family: iPhone only, portrait
- App title: Cave Cals
- Simulator builds use local persistence; retain ad-hoc signing so the widget can access its App Group.
- Choose your Apple Developer team in Signing & Capabilities to run on a physical iPhone.

## Cave Cals Dev on your iPad or iPhone

The shared **Cave Cals Dev** scheme builds the same app and widget source using **Dev Debug** (Run/Test) and **Dev Release** (Archive). It installs separately as `com.philstarkovich.cavecals.dev`; the existing **CaveCals** scheme remains the normal app. You can keep both installed and remain signed into the same Apple/iCloud account.

1. Open `CaveCals.xcodeproj` in Xcode. Choose **Cave Cals Dev** in the scheme menu beside Run.
2. Connect and unlock the iPad, accept **Trust This Computer** if asked, and select that iPad as the run destination. Xcode must support the iPad's installed iPadOS version.
3. In the iPad's **Settings → Privacy & Security → Developer Mode**, enable Developer Mode and follow the restart/confirmation prompts if needed. See [Apple's Developer Mode instructions](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device).
4. The app and **QuickLogWidget** targets use automatic signing with the existing developer team. Sign into that team in **Xcode → Settings → Accounts** if Xcode requests it. Allow Xcode to register the device/new identifiers and create provisioning profiles. Both Dev targets need the new App Group `group.com.philstarkovich.cavecals.dev`. If automatic signing cannot register it, register that group in the Apple Developer account and associate it with `com.philstarkovich.cavecals.dev` and `com.philstarkovich.cavecals.dev.QuickLogWidget`. Do not substitute the normal app's group or iCloud container.
5. Press **Run** (Command-R). Confirm the installed app's name is **Cave Cals Dev**. It runs on iPad in the app's existing iPhone compatibility layout. For later updates, choose the same scheme and Run again; Dev's test data is retained.

**Settings → Cave Cals Dev → Reset Test Data** asks for confirmation, then shows close/reopen instructions. Swipe Dev away in the app switcher and reopen it (or Stop/Run in Xcode). On that cold launch, before opening any stores, it deletes Dev's diary, meals, barcode history, goals, saved nutrition, weigh-ins, progress photos, caches, widget snapshot, applied discount code, and app preferences; setup starts again. The reset removes the contents of the standard sandbox folders, keeping the folders themselves in place because iOS protects them. A failed reset blocks opening the stores and retries at the next launch. If an older Dev build stopped with a “Caches” permission error, build and run the updated Cave Cals Dev scheme over the existing installation; it will finish the pending reset automatically. Developer connection/test-access credentials and settings are retained, as are server usage limits and iOS permissions. The normal app's data is never part of this reset.

Isolation is enforced by separate bundle IDs, Keychain service, widget App Group, and `cavecals-dev://` links. Dev's SwiftData store explicitly uses its private app sandbox and disables CloudKit. Dev entitlements contain only its own App Group—no iCloud, HealthKit, push, or App Attest capability. Health export is also blocked in code, and Dev does not send anonymous usage stats. No separate cloud container has been created yet. Before testing sync, add a **Dev-only** container and adapt reset to handle Dev cloud records; never point Dev at the normal container.

Manual logging, food search, barcode lookup, meals, weights, photos, and normal UI testing work locally. AI requires the existing authorized **Developer settings → Private test-access key** (with **Override subscription for testing** enabled), or the existing local backend developer connection. Without that setup Dev displays an explanation. This does not transfer a normal subscription or change backend authorization. The existing owner test API supports scans/voice/recipe imports; macro estimation still requires a separately supported backend route. Store purchases, restores, and RevenueCat setup are disabled for Dev; this build does **not** validate real subscription purchases. Private access still uses the existing service and its usage limits.

Project maintenance: `scripts/configure_dev_build.rb` updates the Dev configurations from the current normal configurations without recreating targets. `scripts/generate_project.rb` also includes that setup when intentionally regenerating the project. No source fork or second app implementation is maintained.

## Features

- Short optional onboarding lets users choose weight and macro tracking (both on by default), and estimates an editable calorie goal from body details, activity, and preferred pace, with suggested protein/carbs/fat targets when macros are tracked. Manual/no-goal setup remains available. See [onboarding and calorie plans](Documentation/Onboarding.md).
- After setup, “Where did you hear about Cave Cals?” asks once, with a box for a trainer’s or creator’s discount code. A code switches every Cave Cals+ paywall to its prices; each code has a page at CaveCals.com/<Name>, and the owner adds codes and sees their counts on `/admin/codes`. See [discount codes](Documentation/DiscountCodes.md).
- Progress page with calendar-based calorie/macro and weight charts, weekly comparisons, configurable week starts, and a one-page Weekly Recap PDF with five-week trends, AirPrint, and sharing. See [progress and reports](Documentation/Progress.md).
- Progress Photos: a full-screen camera with Front/Back/Left Side/Right Side or typed angles, a see-through ghost of the last photo at that angle with an opacity slider, a 10-second timer, library imports dated by when they were taken, a week-by-week browser, and side-by-side or slider comparisons with the weight change. One photo a day is free; more angles need Cave Cals+. Photos stay on the iPhone (included in its backups, never uploaded). See [progress and reports](Documentation/Progress.md#progress-photos).
- Daily date navigation, disabled future dates, day status, and historical editing.
- Calorie total and chronological entries; target/remaining amounts appear only when a goal is set. Goals can be enabled or removed in Settings without changing historical targets.
- unified Logged / Quick Add screen, calorie shortcuts, barcode scanning, meal scanning and voice logging.
- Numeric quick-add, compact local-first food results, unified entry editor, and serving calculations with last-edit precedence.
- Eight-second undo for adds/deletes; a meal's components undo as one action.
- Local Quick Add ranks up to ten foods using smooth food-specific time windows, recent and established habits, conditional day patterns, same-day occurrence cadence, and meal-session companions. Context-specific calorie variants require repeated evidence so one outlier cannot redefine a food.
- Meals built from today's entries or from scratch; templates expand into independently editable entries and support proportional scaling.
- FatSecret food/restaurant search and Open Food Facts camera barcode lookup, manual calorie entry when the camera is unavailable, and persistent local barcode overrides.
- Expiring positive-result search caches when the provider plan permits, offline local history/meals/logging, and nonblocking network errors.
- SwiftData private CloudKit synchronization on signed devices, with account and sync-event status in Settings.
- Dynamic Type, VoiceOver labels, system light/dark appearance, Schoolbell headings and hand-drawn cave icons.

## iCloud setup and verification

In Xcode's Signing & Capabilities, select your team and enable **iCloud → CloudKit**, using `iCloud.com.philstarkovich.cavecals`. The entitlements and remote-notification background mode are included. Allow Xcode to create/update provisioning profiles. The project contains no Apple account credentials.

Models have CloudKit-compatible defaults and no unique constraints. Meal components are saved as one Codable data value so a template update is atomic. Logged entries retain copied calories and serving metadata; changes to templates or remote food data cannot rewrite past entries. Daily goal records retain historical defaults, including gaps without entries.

On a signed device the app opens a CloudKit-backed local store. If the container cannot initialize, it opens the same named local store without CloudKit. The app never replaces an existing store with an empty in-memory fallback. Simulator builds intentionally use a local store; automated UI tests use a separate in-memory store.

To verify real synchronization, run on two signed iPhones using the same iCloud account, add/edit/delete an entry, change the goal, and create/edit a meal. Wait for CloudKit to sync and verify the second phone reflects the changes. Test offline changes followed by reconnecting, then reinstall/restore only after confirming upload on the second device. iCloud availability is not displayed as proof that an upload finished; completed CloudKit events update the status.

Before TestFlight/App Store release, initialize and inspect the development CloudKit schema, then deploy it to production in CloudKit Console. A simulator build cannot verify real account synchronization or camera capture. Those checks require your signing setup and physical devices.

## Food provider

`FoodSearchService` and `BarcodeLookupService` isolate the providers. Food search uses the free `/api/v1/foods/search` backend endpoint and FatSecret. Barcode lookup stays on Open Food Facts. Local matches never wait for either provider. A 450 ms debounce and request identity guard prevent excessive requests and stale results after query changes.

FatSecret credentials and OAuth tokens remain server-side. Basic search uses v1; set `FATSECRET_API_TIER=premier` after account approval to use v5 with structured default servings. Branded results are named by the product itself ("Diet Coke"); the brand appears beside the serving in search results, and one-word product names keep their brand ("Starbucks Latte"). Calorie portions are retained in logged entries. Search has distributed per-IP and provider-wide quotas independent of paid AI subscriptions. See [FatSecret setup and verification](Documentation/FatSecret.md).

Empty results and errors are never cached. FatSecret Basic results are not cached; Premier positive search results expire after one hour, including across app restarts. Old unversioned caches are no longer read. Offline manual logging, diary history, saved meals, and local common-food suggestions continue to work.

Products without usable calorie/serving data are excluded. Barcode calories are taken from a stated serving or explicitly labeled as a 100 g / 100 ml amount. User-provided barcode values take precedence and survive deletion of their original log entry.

Search terms go through our backend to FatSecret; scanned barcodes go directly to Open Food Facts. Neither provider receives the diary or profile. Attribution: [fatsecret Platform API](https://platform.fatsecret.com), [Open Food Facts](https://world.openfoodfacts.org), [ODbL](https://opendatacommons.org/licenses/odbl/1-0/).

## Tests and maintenance

The shared scheme includes `ECCTests` and `ECCUITests`. Run Product → Test in Xcode. Domain tests cover persistence, historical goals, day boundaries, serving calculations, meals, undo, history ranking, barcode overrides, provider calorie normalization, and offline behavior. UI tests start with `--uitesting` and do not alter the simulator's normal app data.

```sh
xcodebuild test -project CaveCals.xcodeproj \
  -scheme CaveCals \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -parallel-testing-enabled NO
```

Source files are grouped by feature under `App/`. Tests are under `Tests/` and `UITests/`. The optional `scripts/generate_project.rb` recreates the Xcode project using the Ruby `xcodeproj` gem. It is only needed when intentionally regenerating the project after source-file changes. `scripts/make_icon.swift` regenerates the 1024-pixel icon.

Optional Apple Health sharing lives in Settings: **Calories & macros** writes each logged food's Dietary Energy, protein, carbs, fat and fiber (from the day it's turned on, updated on edit/delete), and **Weigh-ins** shares weight. Cave Cals never reads Health data.

Optional weight tracking is available in the **You** area. It includes daily weigh-ins, pounds/kilograms, a dismissible daily reminder, and opt-in Apple Health export. Graphs and editable weigh-in history live in **Progress** (the chart icon between the person and cog). Weight records are stored in a separate protected local file excluded from backup, not in the diary’s CloudKit store. See [weight tracking](Documentation/WeightTracking.md) for behavior and verification.

Optional protein, total-carbohydrate, and fat tracking is on by default; goals and estimates are available. Food editors also store fiber and display calculated net carbs. See [macros](Documentation/Macros.md). Water, exercise logging, and future meal planning remain out of scope.

Optional meal types (off by default) sort the log into Breakfast, Lunch, and other meals, set by time of day or picked each time food is added. Meal types and their times sync with the diary. See [meal types](Documentation/MealTypes.md).

## Widget calorie total

The Quick Log widget shows today's total and goal beside its title (for example `500/2100`), or `500 cal` when no goal is set. The app publishes a small local snapshot after saved changes and imported iCloud updates. Widget timelines include a midnight reset; iOS controls the precise timing of widget refreshes.

The four orange widget tiles use foreground App Intents in both small and medium sizes. Search/Add opens today’s add mode with the search field focused and keyboard visible, including when a sheet was previously open. Tapping the widget’s surrounding area or calorie summary opens today’s Home without the keyboard or a capture screen. The background uses `cavecals://home`; existing `cavecals://log/<action>` links continue to work.

For signed device builds, enable **App Groups** for both the app and QuickLogWidget targets and register/select `group.com.philstarkovich.cavecals` with the same Apple Developer team. Both entitlement files already include this group. Open the updated app once to populate the widget's shared data. The widget does not contact the backend or OpenAI.

Photo and voice share ten successful free scans until 100 regular food-log entries, whichever threshold comes first. See [scan access and rollout](Documentation/ScanAccess.md).
