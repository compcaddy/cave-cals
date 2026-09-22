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

## Features

- Short optional onboarding estimates an editable calorie goal from body details, activity, and preferred pace. Manual/no-goal setup remains available. See [onboarding and calorie plans](Documentation/Onboarding.md).
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

FatSecret credentials and OAuth tokens remain server-side. Basic search uses v1; set `FATSECRET_API_TIER=premier` after account approval to use v5 with structured default servings. Restaurant/brand names and calorie portions are retained in logged entries. Search has distributed per-IP and provider-wide quotas independent of paid AI subscriptions. See [FatSecret setup and verification](Documentation/FatSecret.md).

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

Optional weight tracking is available in the **You** area. It includes daily weigh-ins, pounds/kilograms, editable history, Week/Month/Year graphs, a dismissible daily reminder, and opt-in Apple Health export. Weight records are stored in a separate protected local file excluded from backup, not in the diary’s CloudKit store. See [weight tracking](Documentation/WeightTracking.md) for behavior and verification.

Optional protein, net-carb, and fat tracking is on by default; goals and estimates are available. See [macros](Documentation/Macros.md). Water, exercise logging, meal categories, and future meal planning remain out of scope.

## Widget calorie total

The Quick Log widget shows today's total and goal beside its title (for example `500/2100`), or `500 cal` when no goal is set. The app publishes a small local snapshot after saved changes and imported iCloud updates. Widget timelines include a midnight reset; iOS controls the precise timing of widget refreshes.

For signed device builds, enable **App Groups** for both the app and QuickLogWidget targets and register/select `group.com.philstarkovich.cavecals` with the same Apple Developer team. Both entitlement files already include this group. Open the updated app once to populate the widget's shared data. The widget does not contact the backend or OpenAI.

Photo and voice share ten successful free scans until 100 regular food-log entries, whichever threshold comes first. See [scan access and rollout](Documentation/ScanAccess.md).
