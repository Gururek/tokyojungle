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
nohup "$@" > "logs/${name}.log" 2>&1 &
pid=$!
echo "$pid" > "logs/${name}.pid"
printf '%s\t%s\t%s\n' "$name" "$pid" "$(date +"%F %T")" >> logs/tasks.tsv
echo "started $name pid $pid -> logs/${name}.log"
