#!/usr/bin/env bash
# Drive the running game with injected keys, screenshotting after each key.
# usage: scripts/drive_keys.sh 40 "space space Return space" [tag]
# Frames: the shot sequence lands in logs/drive-<tag>-<n>.png (resized).
set -u
cd "$(dirname "$0")/.."
BOOT=${1:-40}
KEYS=${2:-"space"}
TAG=${3:-k}
export SDL_VIDEODRIVER=x11
pkill -9 -x tokyojungle
(timeout ${DRIVE_TIMEOUT:-220} ./build/tokyojungle > "logs/drive-${TAG}.log" 2>&1 &)
sleep "$BOOT"
i=0
for k in $KEYS; do
  .venv/bin/python scripts/keyinject.py --window ps3recomp --delay 0.4 "$k" >/dev/null 2>&1
  i=$((i+1))
  sleep 4
  DISPLAY=:0 spectacle -b -n -o "logs/drive-${TAG}-${i}.png" >/dev/null 2>&1
  magick "logs/drive-${TAG}-${i}.png" -crop 1920x1200+960+1440 -resize 900x "logs/drive-${TAG}-${i}-s.png" 2>/dev/null
  echo "after key $i ($k) -> logs/drive-${TAG}-${i}-s.png"
done
