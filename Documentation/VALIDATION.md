# V1 validation — September 4, 2026

## Build results

- Debug simulator build and launch: passed on iPhone 17 Pro / iOS 26 and iPhone 15 Pro / iOS 17.2.
- Release build for generic iOS devices: passed with signing disabled. The physical-device CloudKit code path compiled successfully.
- Final iOS 26 suite: **24 passed, 0 failed, 0 skipped** (19 domain tests, 5 UI tests).
- iOS 17.2: all 24 tests passed across the full run and reruns of two UI selectors adjusted for OS accessibility differences.
- Property lists and entitlements passed `plutil -lint`.

## Optional-goal update

- iPhone 15 Pro / iOS 17.2 full suite: **29 passed, 0 failed, 0 skipped** (23 domain tests, 6 UI tests).
- Verified name-free onboarding, skipping a goal, logging without a target, enabling/disabling goals in Settings, persistence across reopen, and preservation of historical goals.
- Search results now scroll above the keyboard when searching begins; covered by quick-add and no-goal UI flows.
- Goal input is centered, uses a 56-point base font and only a bottom border, and Start Tracking is enabled immediately.

## Covered behavior

### Caveman welcome screen and goal adjustment

- Added the supplied caveman image unchanged and updated welcome copy to “You eat.” / “App count.”, “Me Calorie Goal”, “Me Start Now”, and “Me Have No Goal”.
- Settings → Adjust Daily Calorie Goal opens the shared welcome screen with the saved goal; cancelling leaves it unchanged.
- Two targeted iPhone 15 Pro / iOS 17.2 UI tests passed: goal-free logging plus enabling/removing a goal through the shared screen, and cancelling an edit without changing the saved target.
- Rebuilt, relaunched, and visually checked the welcome screen on the user's iPhone 15 Pro simulator.

### Core workflows

- Setup, numeric quick entry, editing, delete, and undo.
- Local persistence across store reopen; moving an entry to another day.
- Historical goals and skipped-day goal history.
- Bidirectional serving/calorie calculations and invalid-value rejection.
- Creating meals from today and from scratch, scaled addition, independent entry snapshots, and grouped undo.
- Normalized history, external food identity, outlier-resistant defaults, cold start, and retained suggestions after logging.
- Unknown barcode manual entry, saved local lookup, and reuse without a remote call.
- Serving vs. 100 g calorie interpretation, kilojoule conversion, absent calorie data, and offline search failure.
- Week navigation limits and camera-unavailable fallback.

## Integration and visual checks

Live read-only requests to Open Food Facts staging returned a barcode product and food-search results. Automated tests use fixtures and a failing provider for deterministic normalization/offline checks.

Inspected the actual iPhone simulator UI in light and dark appearances and at the largest accessibility text size. Fixed list-row button interference, search dismissal/scroll behavior after adding, icon output, oversized day-number clipping, and dark-mode accent contrast. Simulator appearance and text-size preferences were restored after inspection.

## Requires signed physical devices

Real camera recognition, camera permission behavior on hardware, iCloud upload/download, conflict behavior across two devices, and restore after reinstall remain physical-device checks. They require selecting the developer team and provisioning the CloudKit container in Xcode. Code, entitlements, local fallback, and a verification procedure are included; account synchronization is not claimed to have been verified in the unsigned simulator.

Before public distribution, deploy the CloudKit development schema to production and complete the release/API-provider setup described in the main README.
