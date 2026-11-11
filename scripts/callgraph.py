#!/usr/bin/env python3
"""Who calls these lifted functions? Scan the lifted C++ for call sites.

Reports, for each function EA given on the command line, the set of lifted
functions that call it. Walk the call graph from a wall (a spin loop) back to
the startup code that should have set the state up.

    .venv/bin/python scripts/callgraph.py 001F734C 001F72F4
"""
import glob
import re
import sys
from collections import defaultdict

WANT = {w.lower().lstrip("0") or "0" for w in sys.argv[1:]}
CALL = re.compile(r"func_([0-9A-Fa-f]{6,8})\(ctx\);")

callers = defaultdict(set)
for path in sorted(glob.glob("generated/ppu_recomp_*.cpp")):
    cur = None
    for line in open(path, encoding="utf-8", errors="replace"):
        if line.startswith("void func_"):
            cur = line.split()[1].split("(")[0]
            continue
        m = CALL.search(line)
        if not m:
            continue
        key = m.group(1).lower().lstrip("0")
        if key in WANT:
            callers[key].add(cur)

for w in sorted(WANT):
    got = sorted(callers.get(w, ()))
    print(f"func_{w.upper():0>8} <- {len(got)} caller(s)")
    for c in got:
        print("   ", c)
