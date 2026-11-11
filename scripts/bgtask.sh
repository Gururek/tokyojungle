#!/usr/bin/env bash
# Launch a host-side job in the background and remember it, so it can be
# checked and reaped. Every long job should go through this.
#
#   scripts/bgtask.sh build-42 cmake --build build -j16
#   scripts/bgtask.sh run-77 env SDL_VIDEODRIVER=x11 timeout 200 ./build/tokyojungle
#
# stdout/stderr land in logs/<name>.log, the pid in logs/<name>.pid, and the
# entry is appended to logs/tasks.tsv for scripts/bgstatus.sh.
set -u
cd "$(dirname "$0")/.."
[ -d logs ] || mkdir -p logs
name="$1"; shift
export PATH="$PWD/.venv/bin:$PATH"

# Concurrency check: enforce single running task to avoid resource thrashing and duplicated work
if [ -f logs/tasks.tsv ]; then
    while IFS=$'\t' read -r existing_name existing_pid _ || [ -n "$existing_name" ]; do
        if [ -n "${existing_pid:-}" ] && kill -0 "$existing_pid" 2>/dev/null; then
            echo "ERROR: Background task '$existing_name' (PID $existing_pid) is already running!" >&2
            echo "Check status: scripts/bgstatus.sh" >&2
            echo "Kill it:      scripts/bgstatus.sh --kill" >&2
            exit 1
        fi
    done < logs/tasks.tsv
fi

# Launch in isolated process group (setsid) with a hard timeout (default 20 min)
TASK_TIMEOUT="${TASK_TIMEOUT:-20m}"
setsid timeout --kill-after=30s "$TASK_TIMEOUT" "$@" > "logs/${name}.log" 2>&1 &
pid=$!
echo "$pid" > "logs/${name}.pid"
printf '%s\t%s\t%s\n' "$name" "$pid" "$(date +"%F %T")" >> logs/tasks.tsv
echo "started $name pid $pid (pgid $pid, max duration $TASK_TIMEOUT) -> logs/${name}.log"
