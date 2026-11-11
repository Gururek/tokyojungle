#!/usr/bin/env bash
# Chain work onto a background job: run CMD once <jobname>'s pid exits.
#
# Builds and run batches have to be serialised (16 cores, one X window), so
# queue the next step instead of polling for the build by hand:
#   scripts/bgtask.sh exp-A scripts/after.sh clang-3 scripts/experiments.sh A "140:" "141:TJ_TICKRING=0"
set -uo pipefail
JOB=${1:?usage: after.sh <jobname> <cmd...>}; shift
PIDF=logs/$JOB.pid
[ -f "$PIDF" ] || { echo "no $PIDF"; exit 1; }
PID=$(cat "$PIDF")
while kill -0 "$PID" 2>/dev/null; do sleep 5; done
echo "== after $JOB (exit $(tail -1 logs/$JOB.log 2>/dev/null | cut -c1-60))"
exec "$@"
