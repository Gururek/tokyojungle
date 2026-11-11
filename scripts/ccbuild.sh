#!/usr/bin/env bash
# Build with retry: GCC 16 segfaults (signal 11 in cc1plus) on a handful of the
# 111 MB lifted translation units, and which ones fail is a function of
# residency, not of the source.  Ninja is incremental, so a second pass at lower
# parallelism only recompiles what failed.  Four passes, decreasing -j.
set -u
cd "$(dirname "$0")/.."
export PATH="$PWD/.venv/bin:$PATH"
DIR="${1:-build}"
shift || true
# Cap default JOBS to 2: each of the 8 lifted translation units is ~133 MB and takes
# ~10 GB RAM to compile. Parallelism higher than 2 causes heavy swap thrashing and compiler crashes.
JOBS="${JOBS:-2}"
if [ "$JOBS" -gt 2 ]; then
    echo ">>> Clamping JOBS from $JOBS to 2 to prevent RAM exhaustion on 133MB translation units" >&2
    JOBS=2
fi
for pass in 1 2 3 4; do
    j=$(( JOBS / (2 ** (pass - 1)) ))
    [ "$j" -lt 1 ] && j=1
    echo "=== build pass $pass (-j$j) into $DIR"
    out_tmp=$(mktemp)
    if cmake --build "$DIR" -j"$j" "$@" 2>&1 | tee "$out_tmp"; then
        rm -f "$out_tmp"
        echo "=== build ok (pass $pass)"
        exit 0
    fi
    # Fast-fail: If the build failed due to syntax, missing files, or linker errors,
    # retrying at lower thread counts will never fix it. Fail immediately!
    if grep -aE "fatal error:|error: |undefined reference to|no such file" "$out_tmp" 2>/dev/null | grep -qvE "internal compiler error"; then
        rm -f "$out_tmp"
        echo "=== build failed with non-retryable error (aborting retries immediately)" >&2
        exit 1
    fi
    rm -f "$out_tmp"
done
echo "=== build failed after 4 passes"
exit 1
