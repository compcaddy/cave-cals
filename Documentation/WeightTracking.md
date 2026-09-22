# Optional weight tracking

Implemented locally September 18, 2026. This is not evidence of a TestFlight upload or end-to-end Trainerize verification.

## Behavior

- The hand-drawn person icon opens **You**, containing the existing calorie goal, optional weight tracking and history, Apple Health sharing, and existing app/subscription settings.
- Tracking starts off. Turning it off preserves recorded history and reminder dismissal; turning it back on restores the views. Health export has a separate preference.
- The home reminder appears only for today when tracking is enabled and no weight exists. It sits above the anchored food search and hides during search/quick-calorie editing. Its X persists a dismissal for that calendar day, surviving app restarts. A new day is eligible again.
- There is one manual weight per local calendar day. Saving another reading for that day updates the existing record. An explicit edit cannot move onto a different occupied day. History supports adding past dates, editing, and deleting. Future dates are rejected.
- Kilograms are stored without display rounding; pounds use the exact 0.45359237 conversion. Editing an unchanged displayed value preserves the stored measurement. Decimal input follows the current locale.
- Week shows seven days; Month shows thirty days; Year shows twelve calendar months, with monthly averages calculated only from recorded days. Empty days/months are not filled. Lines break across gaps. Arrows browse older periods; touching the graph selects a reading/average. All exact entries remain accessible in the history list.

## Storage

`WeightStore` stores a versioned JSON document in Application Support/WeightTracking/weights-v1.json using atomic writes and complete-until-first-authentication file protection. The folder is excluded from backups. These records deliberately do not enter the existing CloudKit-backed SwiftData store. There is no backend request, AI analysis, analytics payload, or Health import involved.

Local history does not transfer through Cave Cals iCloud sync and is lost if the app is deleted. Health copies remain in Apple Health when sharing has succeeded; this version does not import them after reinstall. Corrupt/unsupported files are left untouched and writes are blocked with an error rather than replacing history with an empty store.

## Apple Health export

The app requests write permission only for HealthKit body mass. Enabling **Save to Apple Health** exports existing and future Cave Cals entries. Permission denial does not prevent local weight logging. Turning sharing off preserves existing Health entries and pauses further updates/deletions.

Every record has a stable sync identifier and a monotonically increasing revision. HealthKit sync metadata replaces earlier versions and makes retries safe. A persisted exported revision tracks pending changes across app restarts. Operations serialize, and an edit/deletion during an export cannot accidentally acknowledge an older revision as current. Failed exports retry on foregrounding or via **Retry sharing**.

Deleted measurements are cleared locally immediately; only a tombstone with identity/revision remains until HealthKit acknowledges deletion. Deletion predicates include the exact sync identifier and this app’s source. Other apps’ Health entries are never modified. Corrections/deletions are sent only while sharing is enabled; they resume when sharing is enabled again.

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
