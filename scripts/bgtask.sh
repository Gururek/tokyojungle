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
FORCE_LAUNCH=0
if [ "${FORCE:-0}" = "1" ] || [ "$name" = "--force" ] || [ "$name" = "-f" ]; then
    FORCE_LAUNCH=1
    [ "$name" = "--force" ] || [ "$name" = "-f" ] && { name="$1"; shift; }
fi

if [ -f logs/tasks.tsv ]; then
    while IFS=$'\t' read -r existing_name existing_pid _ || [ -n "${existing_name:-}" ]; do
        if [ -n "${existing_pid:-}" ] && kill -0 "$existing_pid" 2>/dev/null; then
            if [ "$FORCE_LAUNCH" = "1" ]; then
                echo ">>> Force flag set: terminating active task $existing_name (PID $existing_pid) and its process tree..." >&2
                kill -9 -"$existing_pid" 2>/dev/null || kill -9 "$existing_pid" 2>/dev/null
                pkill -9 -g "$existing_pid" 2>/dev/null || true
            else
                echo "ERROR: Background task '$existing_name' (PID $existing_pid) is already running!" >&2
                echo "Check status: scripts/bgstatus.sh" >&2
                echo "Kill it:      scripts/bgstatus.sh --kill" >&2
                echo "Or replace:   FORCE=1 scripts/bgtask.sh $name ..." >&2
                exit 1
            fi
        fi
    done < logs/tasks.tsv
fi

# Clean up any lingering orphaned compiler or build processes belonging to this workspace
pkill -9 -f "tokyo-jungle-recompiled.*(clang\+\+|ninja|cmake)" 2>/dev/null || true

# Launch in isolated process group (setsid) with a hard timeout (default 20 min)
TASK_TIMEOUT="${TASK_TIMEOUT:-20m}"
caller_pid=$PPID
log_file="logs/${name}.log"
setsid timeout --kill-after=30s "$TASK_TIMEOUT" "$@" > "$log_file" 2>&1 &
pid=$!
echo "$pid" > "logs/${name}.pid"
printf '%s\t%s\t%s\n' "$name" "$pid" "$(date +"%F %T")" >> logs/tasks.tsv
echo "started $name pid $pid (pgid $pid, max duration $TASK_TIMEOUT) -> $log_file"

# Background watcher: monitors the background task.
# If the caller shell runs a sleep (e.g. `&& sleep 280`), this watcher detects when
# the background task finishes/fails, dumps the log tail to stderr, and wakes up
# the caller sleep immediately. No more waiting minutes for failed jobs!
(
    start_s=$(date +%s)
    while kill -0 "$pid" 2>/dev/null; do
        sleep 1
    done
    elapsed=$(( $(date +%s) - start_s ))

    # Check if the caller shell is currently blocked on a sleep
    if kill -0 "$caller_pid" 2>/dev/null; then
        sleep_pid=$(pgrep -P "$caller_pid" -x sleep 2>/dev/null || true)
        if [ -n "$sleep_pid" ]; then
            echo "" >&2
            echo ">>> [bgtask] Task '$name' (PID $pid) finished in ${elapsed}s." >&2
            echo ">>> Early wake-up from sleep. Result log tail:" >&2
            tail -n 15 "$log_file" >&2
            kill "$sleep_pid" 2>/dev/null || true
        fi
    fi
) >/dev/null 2>&1 &
