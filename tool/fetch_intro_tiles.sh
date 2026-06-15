#!/usr/bin/env bash
# Fetch CartoDB dark_nolabels tiles for the RunWar intro slides and bundle
# them as Flutter assets so the onboarding works fully offline.
#
# Idempotent: skips tiles that already exist on disk.
# Re-run safely after editing slide centers/zoom.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/assets/intro_tiles"
UA="app.runwar.runwar_app/1.0"
BASE_URL="https://a.basemaps.cartocdn.com/dark_nolabels"

# Viewport: 540x960 px + 1-tile buffer on each side.
VIEW_W=540
VIEW_H=960
BUFFER_TILES=1

# Slide centers (lat, lon, zoom). Mirrors task brief.
SLIDES=(
  "39.4599 -0.3756 16 slide1_pulse"
  "39.4650 -0.3756 16 slide2_capture"
  "39.4650 -0.3756 16 slide3_defense"
  "39.4607 -0.3762 16 slide4_fortify"
  "39.4620 -0.3760 16 slide6_loot"
  "39.47360 -0.36490 16 slide7_flag"
)

mkdir -p "$OUT_DIR"

# Python helper: print tile (x, y) range covering the viewport at given zoom.
# Args: lat lon zoom view_w view_h buffer_tiles
tile_range() {
  python3 - "$@" <<'PY'
import math, sys
lat = float(sys.argv[1])
lon = float(sys.argv[2])
z = int(sys.argv[3])
w = int(sys.argv[4])
h = int(sys.argv[5])
buf = int(sys.argv[6])
n = 2 ** z
# Center pixel coordinates (256 px tiles).
cx_pix = (lon + 180.0) / 360.0 * n * 256.0
lat_rad = math.radians(lat)
cy_pix = (1.0 - math.asinh(math.tan(lat_rad)) / math.pi) / 2.0 * n * 256.0
x_min = int((cx_pix - w / 2) // 256) - buf
x_max = int((cx_pix + w / 2) // 256) + buf
y_min = int((cy_pix - h / 2) // 256) - buf
y_max = int((cy_pix + h / 2) // 256) + buf
# Clamp.
x_min = max(0, x_min)
y_min = max(0, y_min)
x_max = min(n - 1, x_max)
y_max = min(n - 1, y_max)
print(f"{x_min} {x_max} {y_min} {y_max}")
PY
}

declare -i fetched=0
declare -i skipped=0

for slide in "${SLIDES[@]}"; do
  read -r lat lon zoom label <<<"$slide"
  echo "Slide $label  center=($lat,$lon)  zoom=$zoom"
  # Grab the requested zoom and one level lower (safety / animation fallback).
  for z in $((zoom - 1)) "$zoom"; do
    # For the fallback zoom (z-1), shrink the buffer; the viewport covers
    # fewer tiles at lower zoom so we don't need extra padding.
    if [ "$z" -lt "$zoom" ]; then
      buf=0
    else
      buf="$BUFFER_TILES"
    fi
    range=$(tile_range "$lat" "$lon" "$z" "$VIEW_W" "$VIEW_H" "$buf")
    read -r x_min x_max y_min y_max <<<"$range"
    echo "  z=$z  x=[$x_min..$x_max]  y=[$y_min..$y_max]"
    for ((x = x_min; x <= x_max; x++)); do
      for ((y = y_min; y <= y_max; y++)); do
        dest="$OUT_DIR/$z/$x/$y.png"
        if [ -f "$dest" ]; then
          skipped+=1
          continue
        fi
        mkdir -p "$(dirname "$dest")"
        url="$BASE_URL/$z/$x/$y.png"
        if curl -fsSL -A "$UA" -o "$dest" "$url"; then
          fetched+=1
        else
          echo "  ! failed: $url" >&2
          rm -f "$dest"
        fi
        # Be a good citizen.
        sleep 0.05
      done
    done
  done
done

total=$(find "$OUT_DIR" -name '*.png' | wc -l)
size=$(du -sh "$OUT_DIR" | cut -f1)
echo ""
echo "Fetched: $fetched  Skipped (already on disk): $skipped"
echo "Total tiles on disk: $total  Size: $size"
