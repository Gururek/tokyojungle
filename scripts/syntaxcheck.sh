#!/usr/bin/env bash
# Syntax-only sweep of the lifted translation units.
#
# A full -O2 pass over a 138 MB lifted source costs ~15 minutes; the
# parser-only pass costs a fraction of that, and the generated-code writer
# glitches (a dropped ';' in a load-multiple body, a backtick where ';'
# belongs, a subscript that loses its '] =') are all parse-level defects.
# Run this after a lift to enumerate every syntax defect in the tree at once
# instead of discovering them one -j8 build pass at a time.
#
# Flags come from build/compile_commands.json, so the sweep sees the same
# -D/-I set the real build uses.  Usage: scripts/syntaxcheck.sh [build-dir]
set -uo pipefail
BUILD=${1:-build}
CC=${BUILD}/compile_commands.json
[ -f "$CC" ] || { echo "no $CC (configure the build first)"; exit 1; }
mkdir -p logs
: > logs/syntax.log
.venv/bin/python - "$CC" > /tmp/syn_cmds.txt <<'PY'
import json, shlex, sys
for e in json.load(open(sys.argv[1])):
    if 'generated/ppu_recomp_' in e['file'] and e['file'].endswith('.cpp'):
        a = shlex.split(e['command'])
        out = []
        skip = 0
        for t in a:
            if skip:
                skip = 0
                continue
            if t in ('-o', '-c'):
                skip = 1
                continue
            out.append(t)
        print(' '.join(out[1:]))
PY
JOBS=${JOBS:-8}
xargs -a /tmp/syn_cmds.txt -P "$JOBS" -I{} bash -c 'g++ -fsyntax-only -O0 {} 2>&1 | sed -e "s|'$PWD'/||"' >> logs/syntax.log 2>&1
echo "swept $(wc -l < /tmp/syn_cmds.txt) TU(s) -> logs/syntax.log"
grep -a "error:" logs/syntax.log | sed -e 's/:[0-9]*:[0-9]*:/:/' | sort | uniq -c | sort -rn | head -20
