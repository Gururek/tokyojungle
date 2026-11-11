#!/usr/bin/env python3
"""List lifted functions that read/write a TOC global (with the exact line), so
a guest object's owner/initializer can be found without a full-text scan per
probe. Runs in seconds over the ~40 MB of lifted C++.

    .venv/bin/python scripts/find_writers.py 0x14DC 0x14FC
"""
import re, sys, glob
want = [int(a, 16) for a in sys.argv[1:]]
pats = {a: re.compile(r"TOC [+\-] 0x%X\b" % a) for a in want}
FN = re.compile(r"\nvoid (func_[0-9A-F]{8})\(ppu_context\* ctx\)[^{]*\{(.*?)\n\}\n(?=void func_)", re.S)
for f in sorted(glob.glob("generated/ppu_recomp_*.cpp")):
    if f.endswith("preamble.h"):
        continue
    txt = open(f, encoding="utf-8", errors="replace").read()
    for m in FN.finditer(txt):
        body = m.group(2)
        hits = [l.strip()[:120] for l in body.splitlines()
                if any(p.search(l) for p in pats.values())]
        if hits:
            print(f"{m.group(1)}  ({f.split('/')[-1]})")
            for l in hits[:6]:
                print("     ", l)
