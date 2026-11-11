#!/usr/bin/env bash
# One job = one chain.  Stage markers + fail-fast, so a cheap poll says where a
# chain is and a broken stage does not silently run the stages after it.
#
# The two failures this prevents:
#   - a chain whose only output was ninja progress lines looked dead, so a
#     replacement chain got queued and several compiled the same 9 units;
#   - a failed build ran the run batches anyway against a stale/missing binary,
#     so every run "succeeded" and I read the same answer three times.
#
# Usage:
#   scripts/bgtask.sh work-A scripts/work.sh work-A
#   BIN_DIR=build scripts/bgtask.sh work-W scripts/work.sh work-W
set -uo pipefail
JOB=${1:-work}
BIN_DIR=${BIN_DIR:-build-clang}
shift 2>/dev/null || true

stage() { echo "## [$(date +%H:%M:%S)] $*"; }
# Every stage ends with `|| fail <name>`: a failed stage is the last thing the
# chain does, and the marker is what bgstatus.sh shows as the row's status.
fail() { stage "FAILED: $1"; exit 1; }

stage "build start ($BIN_DIR, JOBS=${JOBS:-10})"
JOBS=${JOBS:-10} scripts/ccbuild.sh "$BIN_DIR" || fail build
stage "build ok: $(ls -l "$BIN_DIR/tokyojungle" 2>/dev/null | awk '{print $6" "$7" "$8}')"

BIN=$PWD/$BIN_DIR/tokyojungle
stage "runs: pump/tick variants (screenshots)"
BIN=$BIN scripts/experiments.sh "$JOB-tick" "140:" "141:TJ_TICKRING=0" || fail runs-tick

stage "runs: screen-manager object dumps"
BIN=$BIN DUR=45 SHOT=0 scripts/experiments.sh "$JOB-dump" \
    "150:TJ_DUMP=00C03F50:40:1500" "151:TJ_DUMP=00C04048:20:1500" \
    "152:TJ_GENMAP=1 TJ_IMPTRACE=1" || fail runs-dump

stage "ALL DONE"
