#!/bin/bash
set -euo pipefail
# First run: kou generate Screenshots/2026-09-17-v2/frames.yaml
# Koubou 0.18.1 supplies photographic iPhone 17 Pro device frames.
base=Screenshots/2026-09-17-v2
font='/System/Library/Fonts/Supplemental/Arial Bold.ttf'
mkdir -p "$base/store"
while IFS='|' read -r name title color top size; do
  source="$base/frames/iPhone_17_Pro_-_Silver_-_Portrait/$name.png"
  if [[ "$name" == 01-goals ]]; then
    magick "$source" \
      \( Screenshots/2026-09-17/artwork/cave-cals-mascot-logo.png -resize 700x467 \) \
      -gravity North -geometry +0+20 -composite \
      -font "$font" -fill "$color" -pointsize "$size" -interline-spacing 12 \
      -gravity North -annotate +0+"$top" "$title" -alpha off -colorspace sRGB "$base/store/$name.png"
  else
    magick "$source" -font "$font" -fill "$color" -pointsize "$size" \
      -interline-spacing 12 -gravity North -annotate +0+"$top" "$title" \
      -alpha off -colorspace sRGB "$base/store/$name.png"
  fi
done <<'PANELS'
01-goals|Weight-loss goals.\nMade simpler.|#291F13|520|112
02-quick|One tap.\nBack to your day.|#FFFFFF|185|135
03-scan|Premium meal\nscanning.|#291F13|185|144
04-meals|Your favorites.\nReady in a tap.|#FFFFFF|185|135
05-start|Build your\nweight-loss habit.|#291F13|185|130
PANELS
magick montage "$base"/store/*.png -thumbnail 264x574 -tile 5x1 -geometry +6+6 "$base/contact-sheet.png"
