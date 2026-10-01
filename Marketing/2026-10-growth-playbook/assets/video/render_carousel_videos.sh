#!/bin/zsh
# Turn each carousel in ../social/carousels/<set>/ into a 9:16 slideshow video (2.5 s per slide).
# Run from assets/: zsh video/render_carousel_videos.sh   (needs ImageMagick + ffmpeg)
set -e
tmp=$(mktemp -d)
for set in social/carousels/*/; do
  name=$(basename $set); rm -f $tmp/*.png(N); i=0
  for f in $set*.png; do
    c=$(magick "$f" -format "%[pixel:p{5,5}]" info:)
    magick "$f" -background "$c" -gravity center -extent 1080x1920 $tmp/$(printf %02d $i).png; i=$((i+1))
  done
  ffmpeg -y -loglevel error -framerate 1/2.5 -i $tmp/%02d.png -vf "fps=30,format=yuv420p" -c:v libx264 -crf 20 -movflags +faststart video/carousels/$name-9x16.mp4
  echo "wrote video/carousels/$name-9x16.mp4"
done
rm -rf $tmp
