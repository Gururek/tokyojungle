#!/usr/bin/env bash
# Run a batch of boot experiments back to back, in the background.
#
# Each experiment is one runexp.sh run with its own env; the whole batch runs
# under one bgtask job so the machine stays busy while I work on the next
# decode.  Results land in logs/run-<tag>.log, logs/shot-<tag>-s.png, and a
# combined summary in logs/experiments-<batch>.log.
#
# Usage: scripts/bgtask.sh exp-A scripts/experiments.sh A
#        "140:" "141:TJ_TICKRING=0" "142:TJ_GENMAP=1"
# Each argument is <tag>:<VAR=value ...>.  DUR/FRAMES/SHOTAT come from the
# environment (defaults: DUR=60 FRAMES=600 SHOTAT=25).
set -uo pipefail
BATCH=${1:?usage: experiments.sh <batch-name> "<tag:env>" ...}
shift
OUT=logs/experiments-$BATCH.log
: > "$OUT"
for spec in "$@"; do
    tag=${spec%%:*}
    env_spec=${spec#*:}
    echo "##### run-$tag  env='$env_spec'" >> "$OUT"
    # shellcheck disable=SC2086
    scripts/runexp.sh "$tag" $env_spec >> "$OUT" 2>&1
done
echo "batch $BATCH done" >> "$OUT"
