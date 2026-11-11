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
for pass in 1 2 3 4; do
    j=$(( JOBS / (2 ** (pass - 1)) ))
    [ "$j" -lt 1 ] && j=1
    echo "=== build pass $pass (-j$j) into $DIR"
    cmake --build "$DIR" -j"$j" "$@" && { echo "=== build ok (pass $pass)"; exit 0; }
done
echo "=== build failed after 4 passes"
exit 1
