#!/usr/bin/env bash
# Wait for a background task started with bgtask.sh to complete or fail.
# Returns immediately as soon as the task finishes, without wasting time sleeping.
#
# Usage:
#   scripts/bgwait.sh <task_name> [max_wait_seconds]
#
# Examples:
#   scripts/bgtask.sh build-1 scripts/ccbuild.sh && scripts/bgwait.sh build-1
#   scripts/bgwait.sh master-4 300
set -u
cd "$(dirname "$0")/.."
name="${1:?usage: bgwait.sh <task_name> [max_wait_seconds]}"
max_wait="${2:-300}"

PIDF="logs/${name}.pid"
LOG="logs/${name}.log"

[ -f "$PIDF" ] || { echo "ERROR: No PID file '$PIDF' found" >&2; exit 1; }
pid=$(cat "$PIDF")

start_s=$(date +%s)
while kill -0 "$pid" 2>/dev/null; do
    elapsed=$(( $(date +%s) - start_s ))
    if [ "$elapsed" -ge "$max_wait" ]; then
        echo ">>> Timed out waiting for '$name' (PID $pid) after ${elapsed}s" >&2
        exit 124
    fi
    sleep 1
done

elapsed=$(( $(date +%s) - start_s ))
echo "=== Task '$name' (PID $pid) finished in ${elapsed}s ==="
tail -n 15 "$LOG" 2>/dev/null
./scripts/bgstatus.sh
