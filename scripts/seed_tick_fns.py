#!/usr/bin/env python3
"""Seed the tick/flip helper functions the discoverer misses.

The JP disc's screen pump (func_001F2D88) publishes per-frame tickets into the
GCM tick ring and then spins on two consumer values.  Both consumer entry points
are reached only through the guest GOT:

    func_0025C2C0 -> [0x00342500] -> 0x003B4388   tick ticket producer
    func_0025C0A0 -> [0x003424BC] -> 0x003B42B8   tick ticket consumer

find_functions.py never walks the GOT, so both lifted as `halt` stubs and the
pump's ticket handshake silently no-op'd.  The four seeds below are the pair of
accessors plus the flip-queue vtables they dispatch through.

Ends are the exact instruction counts: each accessor is `lwz rN,0(r3); blr`
(8 bytes), the vtables are 8-word descriptor blocks.

Usage:  .venv/bin/python scripts/seed_tick_fns.py        # idempotent
        re-lift afterwards: scripts/analyze.py --skip-to lift
"""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# start -> end.  The lifter treats `end` as the address of its emitted
# terminator, so `end` = last instruction + 4: accessors are lwz+blr, the
# vtables are 8-word descriptor blocks.  Ends one short of that get an extra
# "no continuation at 0x..; emitting halt" and lose the blr.
SEEDS = {
    "0x003B4388": "0x003B438C",  # lwz r9,0(r3); blr   - ticket producer
    "0x003B42B8": "0x003B42BC",  # lwz r11,0(r3); blr  - ticket consumer
    # The two flip-queue vtables stay data: their words decode as a method
    # table, and lifting them as code returns garbage in r3 from the pad-init
    # path, which puts the boot back to spinning on cellPadInit.
    
}

TARGETS = [
    ROOT / "generated" / "functions.json",
    ROOT / "generated" / "functions_with_opds.json",
]


def main() -> int:
    for path in TARGETS:
        if not path.exists():
            print(f"skip {path.name} (missing)")
            continue
        funcs = json.loads(path.read_text())
        index = {str(f.get("start", "")).lower(): f for f in funcs}
        changed = 0
        for start, end in SEEDS.items():
            entry = index.get(start.lower())
            if entry is None:
                funcs.append({"start": start, "end": end})
                changed += 1
                print(f"  seed {start} .. {end}")
            elif entry.get("end") != end:
                entry["end"] = end
                changed += 1
                print(f"  fix  {start} end -> {end}")
        if changed:
            path.write_text(json.dumps(funcs, indent=1) + "\n")
        print(f"{path.name}: {len(funcs)} functions, {changed} change(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
