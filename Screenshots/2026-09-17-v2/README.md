# App Store screenshots — revised direction

Five 1320 × 2868 opaque sRGB panels. Real app captures are composited into Koubou 0.18.1 photographic iPhone 17 Pro Silver frames. Cream, app blue, orange, and dark-brown typography; large headlines only; supplied caveman logo appears large on the first panel only. No added footnotes, captions, promotional statistics, or guaranteed weight-loss claims.

Meal Scan uses `raw/meal-scan.png`, captured from the actual app after selecting `artwork/meal.png` in Photos. The photo was generated with the built-in image tool: “Photorealistic overhead smartphone photo of a home-cooked lunch: sliced grilled chicken, cooked rice, roasted broccoli and carrots on a white ceramic plate, warm cream stone tabletop, natural window light, believable food texture; no labels or UI.” The generated photo is illustrative food; no analysis result was fabricated. The large headline identifies meal scanning as premium.

Other original captures are retained in `../2026-09-17/raw/`. Reproduce frames with `kou generate Screenshots/2026-09-17-v2/frames.yaml`, then run `bash scripts/render_store_screenshots_v2.sh` from the project root. Koubou 0.18.1 and ImageMagick are required. Review `contact-sheet.png` and full-size `store/` files before upload.

Capture verification: `ReleaseScreenshotTests/testCaptureMealScanMarketing` passed. App Store upload targets the existing en-US APP_IPHONE_67 set for app 6809208501. Prior uploaded images are backed up under `previous/`. These are marketing metadata updates, not an App Store review submission or a new TestFlight build.

Upload verified: all five v2 screenshots replaced the prior set and reached COMPLETE processing status in App Store Connect.
