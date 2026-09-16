#!/usr/bin/env bash
# Render the README hero and the GitHub social preview from assets/src/*.html
# with headless Chrome. Usage: assets/build.sh
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
chrome="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"

shot() { # html, out, width, height, scale, transparent(0|1)
  local bg=()
  [ "$6" = 1 ] && bg=(--default-background-color=00000000)
  "$chrome" --headless=new --disable-gpu --hide-scrollbars --no-first-run \
    --force-device-scale-factor="$5" --window-size="$3,$4" \
    --virtual-time-budget=8000 ${bg[@]+"${bg[@]}"} \
    --screenshot="$2" "file://$here/src/$1" >/dev/null 2>&1
  echo "$2"
}

shot hero.html "$here/hero.png" 960 460 2 1
shot social.html "$here/social-preview.png" 1280 640 1 0
