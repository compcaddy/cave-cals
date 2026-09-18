#!/bin/bash
set -euo pipefail
# Compose genuine simulator captures; requires ImageMagick. Run at repo root.
base=Screenshots/2026-09-17
font=App/Fonts/Schoolbell-Regular.ttf
mkdir -p "$base/store"
while IFS='|' read -r name raw title subtitle eyebrow; do
  footer='Simple calorie tracking. No account required.'
  if [[ "$name" == 05-plus ]]; then footer='Cave Cals+ subscription required for photo, voice & link imports.'; fi
  magick -size 1320x2868 xc:'#FAF6EE' \
    -font "$font" -fill '#291F13' -gravity North \
    \( "$base/artwork/cave-cals-mascot-logo.png" -resize 240x160 \) \
    -gravity North -geometry +0+15 -composite \
    -fill '#C9450A' -pointsize 30 -annotate +0+206 "$eyebrow" \
    -fill '#291F13' -pointsize 112 -interline-spacing 0 -annotate +0+288 "$title" \
    -pointsize 43 -annotate +0+573 "$subtitle" \
    \( "$base/raw/$raw.png" -resize 900x -bordercolor '#291F13' -border 12 \) \
    -gravity South -geometry +0+138 -composite \
    -gravity South -font "$font" -pointsize 30 -fill '#291F13' -annotate +0+55 "$footer" \
    -alpha off -colorspace sRGB "$base/store/$name.png"
done <<'PANELS'
01-progress|logged|Know where\nyour day stands.|Your calories. Your goal. One clear view.|FREE DAILY TRACKING
02-quick-add|quick-add|Less typing.\nMore living.|Your familiar foods, ready to log again.|QUICK ADD
03-meals|meals|Save your favorites.\nSkip the repeat work.|Build a meal once. Add it again in a tap.|SAVED MEALS
04-portions|portions|Your portion.\nYour numbers.|Adjust servings and calories with ease.|YOU’RE IN CONTROL
05-plus|new-meal|A little less effort.\nA little more +.|Photo, voice & recipe imports with Cave Cals+.|OPTIONAL PREMIUM MEMBERSHIP
PANELS
magick montage "$base"/store/*.png -thumbnail 264x574 -tile 5x1 -geometry +6+6 "$base/contact-sheet.png"
