#!/usr/bin/env bash
# Report and reap background jobs started with scripts/bgtask.sh.
#
#   scripts/bgstatus.sh          # list live jobs with age + log tail
#   scripts/bgstatus.sh --reap   # also drop finished entries from tasks.tsv
#
# tasks.tsv is the ledger of jobs I started; the point is that no job is
# abandoned. Anything older than its own timeout should be reaped, and
# anything with an unread log gets read.
set -u
cd "$(dirname "$0")/.."
REAP=${1:-}
[ -f logs/tasks.tsv ] || { echo "no jobs recorded (logs/tasks.tsv)"; exit 0; }
tmp=$(mktemp)
echo "name	pid	started	status	age	log"
while IFS=$'\t' read -r name pid started; do
    [ -n "${pid:-}" ] || continue
    if kill -0 "$pid" 2>/dev/null; then
        age=$(( ($(date +%s) - $(date -d "$started" +%s 2>/dev/null || echo 0)) / 60 ))
        printf '%s\t%s\t%s\tRUNNING\t%sm\t%s\n' "$name" "$pid" "$started" "$age" "logs/${name}.log"
        printf '%s\t%s\t%s\n' "$name" "$pid" "$started" >> "$tmp"
    else
        printf '%s\t%s\t%s\tdone\t-\t' "$name" "$pid" "$started"
        tail -1 "logs/${name}.log" 2>/dev/null | cut -c1-70
        [ "$REAP" = "--reap" ] || printf '%s\t%s\t%s\n' "$name" "$pid" "$started" >> "$tmp"
    fi
done < logs/tasks.tsv
mv "$tmp" logs/tasks.tsv
