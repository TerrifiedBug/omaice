#!/bin/bash
# Compose the marketplace hero (preview.png, 1280x640) from two bar-band crops.
#
# Capture them first, on a top bar with at least four widgets left of the
# chevron and `icon` left at chevron:
#
#   cd io.github.terrifiedbug.omaice
#   mkdir -p docs/preview
#   # Logical geometry: grim takes compositor coordinates, and a fractional
#   # scale (1.25, 1.5) would break integer shell arithmetic, so jq divides.
#   LW=$(hyprctl monitors -j | jq '(.[0].width / .[0].scale) | floor')
#   H=$(jq -r '.bar["size-horizontal"] // 24' ~/.config/omarchy/shell.json)
#   omarchy bar set io.github.terrifiedbug.omaice revealMode inline
#   omarchy-shell io.github.terrifiedbug.omaice hide   && sleep 1 && grim -g "0,0 ${LW}x$H" /tmp/omaice-collapsed.png
#   omarchy-shell io.github.terrifiedbug.omaice reveal && sleep 1 && grim -g "0,0 ${LW}x$H" /tmp/omaice-revealed.png
#   # Right half only, so the chevron and its neighbours fill the frame.
#   for f in collapsed revealed; do
#     magick "/tmp/omaice-$f.png" -gravity East -crop 55%x100%+0+0 +repage "docs/preview/$f.png"
#   done
#
# Then run this script. Output is deterministic: same inputs, same bytes.
set -euo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
root=$(dirname "$here")
collapsed="$here/preview/collapsed.png"
revealed="$here/preview/revealed.png"
out="$root/preview.png"

for src in "$collapsed" "$revealed"; do
  [[ -f $src ]] || { echo "missing crop: $src (see the header of this script)" >&2; exit 1; }
done

tagline="Everything left of the chevron hides. Click it, it all comes back."

# The bar crops are very wide strips, so each is scaled to a fixed width and
# stacked with a caption under it.
magick -size 1280x640 "gradient:#171c2a-#0e1219" \
  -font Adwaita-Sans-Bold -pointsize 64 -fill '#f2e7d0' \
  -gravity north -annotate +0+96 "OmaIce" \
  -font Adwaita-Sans -pointsize 24 -fill '#cfc6b4' \
  -gravity north -annotate +0+196 "$tagline" \
  \( "$collapsed" -resize 1000x -bordercolor '#ffffff1f' -border 1 \) \
  -gravity north -geometry +0+300 -composite \
  -font Adwaita-Sans -pointsize 18 -fill '#8a8f9c' \
  -gravity north -annotate +0+372 "collapsed" \
  \( "$revealed" -resize 1000x -bordercolor '#ffffff1f' -border 1 \) \
  -gravity north -geometry +0+440 -composite \
  -font Adwaita-Sans -pointsize 18 -fill '#8a8f9c' \
  -gravity north -annotate +0+512 "revealed" \
  -depth 8 -strip -define png:exclude-chunk=date,time \
  "$out"

echo "wrote $out"
magick identify "$out"
