#!/usr/bin/env bash
# Regenerate all Android launcher icons from the SVG sources in this folder.
# Requires: rsvg-convert, ImageMagick (magick/convert).
set -euo pipefail

cd "$(dirname "$0")"
ROOT="../../android/app/src/main/res"

# Legacy square icon densities (dp 48 baseline).
declare -A LEGACY=( [mdpi]=48 [hdpi]=72 [xhdpi]=96 [xxhdpi]=144 [xxxhdpi]=192 )
# Adaptive icon layers are 108dp.
declare -A ADAPTIVE=( [mdpi]=108 [hdpi]=162 [xhdpi]=216 [xxhdpi]=324 [xxxhdpi]=432 )

# Pre-render the walker artwork once and trim to its bounding box so we can
# centre it consistently inside the adaptive safe zone.
rsvg-convert -w 1024 -h 1024 walker.svg -o /tmp/wk_feet.png
magick /tmp/wk_feet.png -trim +repage /tmp/wk_feet_trim.png

for dpi in "${!LEGACY[@]}"; do
  dir="$ROOT/mipmap-$dpi"
  mkdir -p "$dir"

  # Legacy icon (full square with background baked in).
  rsvg-convert -w "${LEGACY[$dpi]}" -h "${LEGACY[$dpi]}" icon_master.svg -o "$dir/ic_launcher.png"

  # Adaptive background layer.
  S="${ADAPTIVE[$dpi]}"
  rsvg-convert -w "$S" -h "$S" icon_background.svg -o "$dir/ic_launcher_background.png"

  # Adaptive foreground layer: footprints scaled to ~66% of the canvas, centred,
  # on a transparent background.
  inner=$(( S * 66 / 100 ))
  magick /tmp/wk_feet_trim.png -resize "${inner}x${inner}" \
    -background none -gravity center -extent "${S}x${S}" \
    "$dir/ic_launcher_foreground.png"
done

echo "Icons regenerated under $ROOT"
