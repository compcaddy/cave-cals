# Next review submission plan — September 17, 2026

## Prepared

- Goal setup now uses the colored drumstick app icon above the three-line headline.
- Cave Cals+ local Settings branding and rectangular cream logo are ready.
- Five fresh App Store marketing screenshots use actual current app captures and supplied artwork; previous images are backed up under `Screenshots/2026-09-17/previous/`.
- Simulator build succeeds. All 55 native unit tests pass. The once-daily suggestion test was corrected to verify ranking suppression with six candidates in a ten-slot list.
- The goal setup/settings UI flow and release screenshot capture UI test both pass (two tests, zero failures).

## Required before submission

1. Finish remaining UI work, increment app/widget build numbers together, archive, and upload a new TestFlight build. Latest verified Apple build remains 1.0.1 (3); it lacks the latest branding and setup changes.
2. On the physical iPad, test the new build's paywall persistence, purchase, cancellation, restore after reinstall, and paid-feature unlock. The reported Restore Purchases “Unable to Complete Request” remains unresolved by this screenshot/UI work. Preserve the actual error details and sandbox account context when investigating.
3. Resolve Apple's mainland China/OpenAI distribution objection. Confirm the intended storefront decision with the owner before changing availability; no storefront change was made in this work.
4. Recheck production CloudKit sync, camera capture, microphone behavior, and App Attest. Simulator success is not evidence for these hardware/server integrations.
5. Reconcile the rejected App Store version record (currently 1.0) with the intended uploaded marketing version (currently 1.0.1). Attach the final build and both first-time subscriptions on the version page, and update the locked customer-facing subscription localization to Cave Cals+ when editable.
6. Review privacy disclosures, support/contact information, current agreements, and Regulations and Permits. `asc review doctor` does not validate every legal or runtime requirement.
7. Run `asc review doctor --app 6809208501` again. Current review state is UNRESOLVED_ISSUES; promotional subscription images are optional unless using App Store subscription promotion.
8. Reply to App Review with specific reproduction/test results and submit the prepared version once the outstanding tasks pass. Preserve manual release so approval does not automatically publish the app.

This is a submission plan, not a record of a completed review submission or production release.
