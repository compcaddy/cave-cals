# Cave Cals App Store screenshot refresh

Captured September 17, 2026 from the current Debug simulator app on iPhone 17 Pro (iOS 26). All phone UI is a genuine simulator capture. `--screenshots` uses isolated in-memory sample entries and meals; it is compiled only in Debug simulator builds. `raw/setup.png` documents the colored app icon above the setup headline and is not a store marketing panel.

The five `store/` panels are opaque sRGB PNGs, 1320 × 2868, composed with Schoolbell type, cream background, and the user's supplied caveman logo. They show daily progress, Quick Add, saved meals, portions, and premium meal-creation options. The premium panel explicitly states the subscription requirement. No purchase completion or scan-result UI has been fabricated.

Rebuild the panels from the saved captures with `bash scripts/render_store_screenshots.sh` at the repository root. Inspect `contact-sheet.png` and the full-size panels, then run `asc screenshots validate --path Screenshots/2026-09-17/store --device-type IPHONE_67`.

App Store Connect target: Cave Cals `6809208501`, en-US localization `25b5dff6-f0e2-45e4-be54-f7012523d179`, screenshot set `f623bc3d-80f1-40ac-9f03-47f658ce7451` (API label APP_IPHONE_67). The four previous screenshots were downloaded into `previous/` before replacement and can be restored.

Upload verified: all five replacement screenshots reached Apple's COMPLETE processing state on September 17. The four old screenshots were removed from this set; their local backups remain recoverable.

The store screenshots depict source changes newer than TestFlight 1.0.1 (3). Upload and test a new build containing these changes before submitting the version for review. Screenshot upload alone does not submit a version or release it.
