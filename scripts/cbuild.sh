#!/usr/bin/env bash
# ccbuild with a renice: the Vulkan side tree should not compete with the main
# build for the machine.  JOBS caps ninja width (default 4).
set -u
cd "$(dirname "$0")/.."
export PATH="$PWD/.venv/bin:$PATH"
JOBS="${JOBS:-4}"
DIR="$1"; shift
cmake --build "$DIR" -j"$JOBS" "$@"
