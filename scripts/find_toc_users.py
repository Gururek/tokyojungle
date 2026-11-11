#!/usr/bin/env python3
"""List lifted functions touching a guest global, with the exact lines.

The lifted code addresses globals as r2/r13-relative (`vm_read32(ctx->gpr[2] +
0x14DC)`) and the TOC is 0x003591E0, so a TOC offset like 0x14DC is guest
0x0035A6BC. Pass offsets, not absolute EAs. Runs in ~20 s over the 40 MB of
lifted C++; run it in the background and keep working.

    .venv/bin/python scripts/find_toc_users.py 0x14DC 0x14FC
"""
import glob
import re
import sys

WANT = [a.lower() for a in (x[2:] if x.startswith("0x") else x for x in sys.argv[1:])]
FN = re.compile(
    r"\nvoid (func_[0-9A-F]{8})\(ppu_context\* ctx\)[^{]*\{(.*?)\n\}\n(?=void func_)",
    re.S,
)

for path in sorted(glob.glob("generated/ppu_recomp_*.cpp")):
    txt = open(path, encoding="utf-8", errors="replace").read()
    if not any(w in txt for w in WANT):
        continue
    for m in FN.finditer(txt):
        hits = [l.strip()[:130] for l in m.group(2).splitlines()
                if any(w in l.lower() for w in WANT)]
        if hits:
            print(f"{m.group(1)}  ({path.split('/')[-1]})")
            for l in hits[:8]:
                print("     ", l)
