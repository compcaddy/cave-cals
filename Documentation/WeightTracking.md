# Optional weight tracking

Implemented locally September 18, 2026. This is not evidence of a TestFlight upload or end-to-end Trainerize verification.

## Behavior

- The person icon opens **About You**, containing the calorie plan, goal, macros, and weight settings/logging. The chart icon opens **Progress**, containing weight graphs and editable history. Apple Health sharing lives in Settings.
- Tracking starts off. Turning it off preserves recorded history and reminder dismissal; turning it back on restores the views. Health export has a separate preference.
- The home reminder appears only for today when tracking is enabled and no weight exists. It sits above the anchored food search and hides during search/quick-calorie editing. Its X persists a dismissal for that calendar day, surviving app restarts. A new day is eligible again.
- There is one manual weight per local calendar day. Saving another reading for that day updates the existing record. An explicit edit cannot move onto a different occupied day. History supports adding past dates, editing, and deleting. Future dates are rejected.
- Kilograms are stored without display rounding; pounds use the exact 0.45359237 conversion. Editing an unchanged displayed value preserves the stored measurement. Decimal input follows the current locale.
- Progress uses calendar weeks, full calendar months (28–31 days), and calendar years. Week/month show recorded daily weights; year shows weekly averages of recorded weights, clipping boundary weeks to the year. Empty days/weeks are not filled. Lines break across gaps. The configurable week start defaults to Monday. Arrows browse older periods; touching the graph selects a reading/average. All exact entries remain accessible in All weigh-ins. See [Progress](Progress.md).

## Storage

`WeightStore` stores a versioned JSON document in Application Support/WeightTracking/weights-v1.json using atomic writes and complete-until-first-authentication file protection. The folder is excluded from backups. These records deliberately do not enter the existing CloudKit-backed SwiftData store. There is no backend request, AI analysis, or analytics payload involved. Weights read from Apple Health (see below) are stored in the same file.

Local history does not transfer through Cave Cals iCloud sync and is lost if the app is deleted. Health copies remain in Apple Health when sharing has succeeded, and since October 17, 2026 they come back after a reinstall when Weigh-ins is turned on again (see Apple Health import). Corrupt/unsupported files are left untouched and writes are blocked with an error rather than replacing history with an empty store.

## Apple Health export

The app requests write permission only for HealthKit body mass (and, since October 17, 2026, read permission for body mass too; see Apple Health import). Enabling **Save to Apple Health** exports existing and future Cave Cals entries. Permission denial does not prevent local weight logging. Turning sharing off preserves existing Health entries and pauses further updates/deletions.

Every record has a stable sync identifier and a monotonically increasing revision. HealthKit sync metadata replaces earlier versions and makes retries safe. A persisted exported revision tracks pending changes across app restarts. Operations serialize, and an edit/deletion during an export cannot accidentally acknowledge an older revision as current. Failed exports retry on foregrounding or via **Retry sharing**.

Deleted measurements are cleared locally immediately; only a tombstone with identity/revision remains until HealthKit acknowledges deletion. Deletion predicates include the exact sync identifier and this app’s source. Other apps’ Health entries are never modified. Corrections/deletions are sent only while sharing is enabled; they resume when sharing is enabled again.

## Apple Health import (October 17, 2026, local)

The **Weigh-ins** switch now syncs both ways. Turning it on asks Apple to write and read body mass in one sheet; nothing else is read. People who turned it on before this (write only) see **Bring in weigh-ins from Apple Health** in Settings → Apple Health until Apple's sheet has asked about reading (`statusForAuthorizationRequest`; iOS never says whether reading was allowed). Otherwise that spot shows **Sync now** (export, then import), which replaced Retry sharing.

Rules (`WeightHealthImport.merge`, unit-tested in `Tests/WeightTrackingTests.swift`):

- One weigh-in a day. A weigh-in logged in Cave Cals always wins its day.
- Otherwise the day shows its first reading from another app. A reading that syncs in later but was taken earlier that day replaces it (same record), and when the shown reading is deleted in Apple Health the next one takes over, or the day empties.
- Deletions are only inferred when some other app's weigh-ins came back at all, because iOS answers "nothing" when reading is declined.
- Cave Cals' own samples (recognized by their sync identifier, from before a reinstall or from another iPhone) come back as the same weigh-ins with their revision, so later edits replace them in Health. A pending local deletion is never brought back.
- Future-dated and impossible readings are skipped.
- Imported records carry `healthSampleID` and `healthSource` and are never written back to Health. Saving one unchanged keeps it imported; editing it clears both fields, so it becomes an ordinary Cave Cals weigh-in (shared like any other, never replaced). Deleting another app's reading removes it locally only and adds its sample to `ignoredHealthSamples`, so it never returns (a later reading that day still can).
- Clan weight challenges use only weigh-ins logged in Cave Cals; anything with a `healthSource` is left out, so Health data never reaches the backend. The challenge screens say so.

When it runs: on opening and returning to the app (after export), from Sync now, and from an `HKObserverQuery` set up as the store is created at launch. Background delivery (`enableBackgroundDelivery`, hourly) is on while Weigh-ins is on and reading was asked, so iOS wakes Cave Cals when another app saves a weight; it needs the `com.apple.developer.healthkit.background-delivery` entitlement (added to `App/CaveCals.entitlements`). Imports only run while weight tracking is on. Apple Health is unreadable while the iPhone is locked; that error is ignored and the next opening or new weight tries again. Usage stats: event `health.weightImport` {added}, errors under `appleHealth`.

Not verified yet (needs a signed iPhone): the read permission sheet, reading another app's samples, background wake-ups with the new entitlement in the provisioning profile, and the locked-device case.

Trainerize currently documents body-weight import from Apple Health, but its import timing and handling of subsequent corrections/deletions belong to Trainerize. Do not claim that a successful HealthKit write verifies delivery to Trainerize.

References:

- [Apple: saving HealthKit data](https://developer.apple.com/documentation/healthkit/saving-data-to-healthkit)
- [Apple: sync identifiers and replacement versions](https://developer.apple.com/documentation/healthkit/hkmetadatakeysyncidentifier)
- [Trainerize: supported integration data](https://help.trainerize.com/hc/en-us/articles/15206977916052-What-Data-Syncs-From-Wearables-and-App-Integrations)

## Verification before distribution

Automated coverage lives in `Tests/WeightTrackingTests.swift` and `UITests/WeightTrackingUITests.swift`. The tests use an injected Health exporter and isolated/in-memory records; no real user Health data is accessed.

September 18 simulator evidence:

- Debug simulator build succeeded. The existing native suite and home search/background regression checks passed during implementation.
- iPhone 17 Pro: the reminder and add/edit/delete UI flows passed; all 11 weight-store tests passed after the final calendar-boundary fix.
- iPad Air 11-inch (M3), iOS 26: 15 tests passed, covering all 11 weight-store tests, all three weight UI flows, and the existing calorie-goal editor regression.
- Visually reviewed the personal area with a 90-day synthetic history. Month shows individual readings and clear gaps. The simulator-only `--weight-preview` launch argument seeds this in-memory fixture.
- Existing warnings remain for actor isolation in `LoggingActionRouter.swift` and the app/widget build-number mismatch. Neither warning was introduced by this feature.

Physical-device checks still required:

1. Enable the HealthKit capability for the signed app/provisioning profile; test permission grant, denial, and revocation.
2. Save a synthetic test weigh-in, verify its value/unit/date in Apple Health, correct it, and confirm only one sample remains. Delete it and verify removal.
3. Exercise a locked-device/failed export, app restart, sharing disable/re-enable, and retry without duplicate samples.
4. Connect the owner’s Trainerize installation to Apple Health with weight access and verify a Cave Cals sample reaches it. Separately check corrections/deletions; do not assume downstream propagation.
5. Test iPhone and iPad compatibility, accessibility text sizes, locale decimal entry, and midnight/time-zone changes.

No release version/build changes or upload are included in this feature. The repository currently has an existing app/widget build-number mismatch; reconcile versions before an archive.


## Native release follow-up — September 21, 2026

Version **1.0.3 (2)** now includes these changes in App Store Connect, with Apple processing VALID and explicit Internal Testers membership (IN_BETA_TESTING). App Store version 1.0.3 is prepared with this build but has not been submitted for review or publicly released. See [current release readiness](Release/Readiness.md) for validation and outstanding physical-device checks.
