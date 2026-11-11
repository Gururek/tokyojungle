#!/usr/bin/env bash
# One experiment = one run + its summary + one screenshot of the game window.
#
# The loop that used to take four hand-written commands: run under a timeout
# into its own log, screenshot the ps3recomp window *while it is up* (the
# desktop has several screens, so capture the window, not the root), then
# summarise with pumpstats.sh.
#
# Run it in the background and keep working:
#   scripts/bgtask.sh run-140 scripts/runexp.sh 140 TJ_GENMAP=1
#   scripts/bgtask.sh run-141 scripts/runexp.sh 141 TJ_TICKRING=0
#
# Knobs: BIN defaults to the clang tree (fastest).
# DUR (timeout, default 60), SHOTAT (seconds before the shot, default
# 25), FRAMES/FLOG/TICK_US, BIN (default build/tokyojungle), SHOT=0 to skip.
set -uo pipefail
TAG=${1:?usage: runexp.sh <tag> [env ...]}; shift
BIN=${BIN:-build/tokyojungle}
DUR=${DUR:-60}
LOG=logs/run-$TAG.log
[ -x "$BIN" ] || { echo "runexp: no binary at $BIN - build first" >&2; exit 1; }
pkill -9 -x tokyojungle 2>/dev/null; sleep 1
env SDL_VIDEODRIVER=x11 TJ_MAX_FRAMES=${FRAMES:-600} TJ_FRAME_LOG=${FLOG:-30} \
    TJ_TICK_US=${TICK_US:-8000} "$@" timeout -s KILL "$DUR" "$BIN" > "$LOG" 2>&1 &
APP=$!
sleep "${SHOTAT:-25}"
if [[ ${SHOT:-1} == 1 ]]; then
    W=$(DISPLAY=:0 .venv/bin/python scripts/wininfo.py --id 2>/dev/null)
    if [[ -n ${W:-} ]]; then
        DISPLAY=:0 import -window "$W" "logs/shot-$TAG.png" 2>/dev/null \
            && magick "logs/shot-$TAG.png" -resize 900x "logs/shot-$TAG-s.png" \
            && echo "shot: logs/shot-$TAG-s.png ($W)"
    else
        echo "shot: no ps3recomp window"
    fi
fi
wait $APP 2>/dev/null
echo "== $TAG -> $LOG"
./scripts/pumpstats.sh "$LOG"
