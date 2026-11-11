#!/usr/bin/env bash
# Summarise one tokyojungle run in the terms the boot model speaks.
#
#   frames advanced, pump steps, where the per-frame ticket handshake is,
#   which HLE calls show up, and the watchdog's last word.  Use this after
#   every run instead of grepping the log by hand: the boot chain is
#   pump -> ticket publish -> tick ring -> screen handler, and each of those
#   leaves its own line in the log.
#
# Usage: scripts/pumpstats.sh logs/run-140.log
set -uo pipefail
L=${1:?usage: pumpstats.sh <log>}
say() { printf '%-22s %s\n' "$1" "$2"; }
say "pump steps:"  "$(grep -acE '\[SCR\] loop' "$L")"
say "frames:"      "$(grep -acE '^\[frame\]' "$L")"
say "last frame:"  "$(grep -aE '^\[frame\]' "$L" | tail -1)"
say "drain pass:"  "$(grep -aE 'drain pass' "$L" | tail -1)"
say "tick0:"       "$(grep -aE 'tick0 ' "$L" | tail -1)"
say "spin-obj:"    "$(grep -aE 'spin-obj' "$L" | tail -1)"
say "ref:"         "$(grep -aE '^\[ref\]' "$L" | tail -1)"
say "watchdog:"    "$(grep -aE 'guest=' "$L" | tail -1 | cut -c1-140)"
say "exit:"        "$(grep -aE 'frame loop finished|Killed|Aborted' "$L" | tail -1)"
echo "HLE calls seen (unique, first 12):"
grep -aoE '\[genmap\] 0x[0-9A-Fa-f]+ [a-zA-Z_0-9]+' "$L" | awk '{print $3}' | sort -u | head -12 | tr '\n' ' '; echo
echo "tick counters:"
grep -aoE 'wi=[0-9A-Fa-f]+|counter=[0-9A-Fa-f]+|target=[0-9A-Fa-f]+' "$L" | sort | uniq -c | sort -rn | head -8
