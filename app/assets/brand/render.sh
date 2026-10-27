#!/usr/bin/env bash
# Renders every PNG of the Chama icon from the SVG masters in this folder.
# Needs rsvg-convert (librsvg) and ImageMagick 7 (`magick`).
#   assets/brand/render.sh
set -euo pipefail
cd "$(dirname "$0")"
APP=../..
RES=$APP/android/app/src/main/res
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# chama-icon.svg is the 108-unit adaptive canvas. Crops of it:
#   legacy launcher: the 72-unit visible area, as a rounded square or a circle;
#   web icon: the mark at about 60% of the square, centred; maskable: the whole
#   canvas (the art sits inside the central 80% circle).
crop() { sed "s|viewBox=\"0 0 108 108\"|viewBox=\"$1\"|" chama-icon.svg >"$TMP/$2.svg"; }
crop "18 18 72 72" legacy
crop "7.5 7.5 93 93" web

png() { rsvg-convert -w "$2" -h "$2" "$1" -o "$3"; }
masked() { # svg size out shape
  png "$1" "$2" "$TMP/in.png"
  local n=$(($2 - 1)) r=$(($2 * 22 / 100))
  if [ "$4" = round ]; then
    magick -size "$2x$2" xc:none -fill white -draw "circle $(($2 / 2)),$(($2 / 2)) $(($2 / 2)),0" "$TMP/mask.png"
  else
    magick -size "$2x$2" xc:none -fill white -draw "roundrectangle 0,0 $n,$n $r,$r" "$TMP/mask.png"
  fi
  magick "$TMP/in.png" "$TMP/mask.png" -compose CopyOpacity -composite "$3"
}

for d in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
  dir=$RES/mipmap-${d%%:*}
  mkdir -p "$dir"
  masked "$TMP/legacy.svg" "${d##*:}" "$dir/ic_launcher.png" square
  masked "$TMP/legacy.svg" "${d##*:}" "$dir/ic_launcher_round.png" round
done

png "$TMP/web.svg" 192 "$APP/web/icons/Icon-192.png"
png "$TMP/web.svg" 512 "$APP/web/icons/Icon-512.png"
png "$TMP/web.svg" 180 "$APP/web/icons/apple-touch-icon.png"
png chama-icon.svg 192 "$APP/web/icons/Icon-maskable-192.png"
png chama-icon.svg 512 "$APP/web/icons/Icon-maskable-512.png"
png chama-mark-simple.svg 32 "$APP/web/favicon.png"
cp chama-mark-simple.svg "$APP/web/favicon.svg"

# Play Store: 512 icon (the store applies its own mask) and the 1024x500
# feature graphic (the ipê mark and the white wordmark on açaí).
mkdir -p store
png "$TMP/web.svg" 512 store/icon-512.png
sed 's/#4A1D6E/#F5B700/' chama-mark.svg >"$TMP/ipe.svg"
png "$TMP/ipe.svg" 220 "$TMP/mark.png"
magick -size 1024x500 xc:'#4A1D6E' "$TMP/mark.png" -geometry +230+140 -composite \
  -font ../fonts/Inter-700.ttf -pointsize 132 -kerning -3 -fill white -annotate +480+305 'chama' \
  store/feature-graphic.png
echo "rendered"
