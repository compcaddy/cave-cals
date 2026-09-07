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
