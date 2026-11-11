#!/usr/bin/env bash
# Report, flag, and reap background jobs started with scripts/bgtask.sh.
#
#   scripts/bgstatus.sh            # list jobs, flag the long ones
#   scripts/bgstatus.sh --stale    # also KILL the long ones
#   scripts/bgstatus.sh --keep     # keep finished rows in the ledger
#
# logs/tasks.tsv is the ledger; every job I start goes into it, so nothing is
# abandoned.  Finished rows are reaped on every invocation (the ledger is a work
# queue, not a history file), and their status is read from the log, not
# assumed: a chain that exited 0 after a failed stage used to be reported as
# `done` with its ninja error line as the "result", which read as success.
#
# Statuses: RUNNING, STALE (over BG_WARN_MIN minutes, default 25 = one lifted
# TU compile plus a run), OK, FAIL.
set -u
cd "$(dirname "$0")/.."
ACTION=${1:-}
WARN=${BG_WARN_MIN:-25}
[ -f logs/tasks.tsv ] || { echo "no jobs recorded (logs/tasks.tsv)"; exit 0; }
tmp=$(mktemp); : > "$tmp"
stale=0; failed=0
printf 'name\tpid\tstarted\tstatus\tage\tlog\n'
while IFS=$'\t' read -r name pid started _; do
    [ -n "${pid:-}" ] || continue
    log=logs/${name}.log
    if kill -0 "$pid" 2>/dev/null; then
        age=$(( ($(date +%s) - $(date -d "$started" +%s 2>/dev/null || echo 0)) / 60 ))
        status=RUNNING
        [ "$age" -gt "$WARN" ] && { status=STALE; stale=$((stale + 1)); }
        printf '%s\t%s\t%s\t%s\t%sm\tlogs/%s.log\n' "$name" "$pid" "$started" "$status" "$age" "$name"
        printf '%s\t%s\t%s\n' "$name" "$pid" "$started" >> "$tmp"
        if [ "$ACTION" = "--stale" ] && [ "$status" = STALE ]; then
            pkill -9 -P "$pid" 2>/dev/null
            kill -9 "$pid" 2>/dev/null
            echo "  killed $name (pid $pid, ${age}m): $(tail -1 "$log" 2>/dev/null | cut -c1-70)"
        fi
    else
        # Finished: ask the log.  `## [..] FAILED:` (work.sh), the lifter/fixture
        # chain's own markers, then compiler/build/run evidence.
        status=OK
        detail=$(grep -a "^## \[.*FAILED" "$log" 2>/dev/null | tail -1 | sed 's/^## //')
        [ -z "$detail" ] && detail=$(grep -aoE "ALL DONE|chain: done" "$log" 2>/dev/null | tail -1)
        [ -z "$detail" ] && detail=$(grep -aoE "ninja: build stopped[^|]*|error: [^|]{0,60}|Killed|Segmentation fault" "$log" 2>/dev/null | tail -1)
        [ -z "$detail" ] && detail=$(tail -1 "$log" 2>/dev/null)
        case "$detail" in
            *FAILED*|*build\ stopped*|*error:*|*Segmentation\ fault*|*Killed*)
                status=FAIL
                failed=$((failed + 1))
                ;;
        esac
        # `tail -1` on a log with no trailing newline would run into the next
        # row, which merged ledger lines and hid jobs from the reaper.
        printf '%s\t%s\t%s\t%s\t-\t%s\n' "$name" "$pid" "$started" "$status" \
            "$(printf '%s' "$detail" | tr -d '\t\n' | cut -c1-70)"
        [ "$ACTION" = "--keep" ] && printf '%s\t%s\t%s\n' "$name" "$pid" "$started" >> "$tmp"
    fi
done < logs/tasks.tsv
mv "$tmp" logs/tasks.tsv
[ "$stale" -gt 0 ] && echo ">>> $stale job(s) over ${WARN}m - read their logs, then: scripts/bgstatus.sh --stale"
[ "$failed" -gt 0 ] && echo ">>> $failed job(s) FAILED - fix the cause, then re-run ONE job"
exit 0
