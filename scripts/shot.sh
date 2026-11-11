#!/usr/bin/env bash
# Capture ONLY the ps3recomp SDL2 window. The desktop root has several screens
# of other windows open, so cropping the root (the old approach) is not
# evidence of what the game drew -- grab the window id from wininfo.py.
#   scripts/shot.sh logs/shot-90.png            # full window
#   scripts/shot.sh logs/shot-90.png 900        # scale to 900px wide
set -euo pipefail
out="${1:?usage: scripts/shot.sh out.png [width]}"
w="${2:-900}"
cd "$(dirname "$0")/.."
id=$(DISPLAY=:0 .venv/bin/python scripts/wininfo.py --id "${TJ_WIN:-ps3recomp}")
DISPLAY=:0 import -window "$id" logs/_shot_raw.png
magick logs/_shot_raw.png -resize "${w}x" "$out"
echo "captured $(du -h logs/_shot_raw.png | cut -f1) -> $out (window $id)"
