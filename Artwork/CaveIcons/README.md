# Cave icon artwork

The approved concept is preserved as `approved-preview.png`. Individual editable SVGs are traced from its light-row drawings; the actual app/widget assets are template vector PDFs in `Shared/CaveIcons.xcassets`.

Six independent assets: Barcode, Voice, Meal, Search, Plus, Slash. `Shared/CaveIcon.swift` provides `CaveIcon` and the composed `CaveSearchAddIcon`. Tint comes from the parent foreground style. The icon view is decorative for accessibility; buttons retain their descriptive labels and hit targets. Native Home Screen long-press shortcuts retain their system-symbol fallback.

To reproduce the SVG and PDF files, install ImageMagick and Potrace and run `python3 scripts/build_cave_icons.py` from the repository. The script does not require an API key. It removes tiny speckles for small-size readability while preserving the approved silhouettes and irregular contours. PDFs contain vector paths, not embedded bitmap previews.

Utility icons (pencil, camera, settings, arrows, selection, recording, sync, and warning) use deliberately uneven SVG contours with broad strokes. Rebuild their template PDFs with `python3 scripts/build_cave_utility_icons.py`. Close controls reuse the original Plus rotated 45 degrees.
