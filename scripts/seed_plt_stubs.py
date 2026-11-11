#!/usr/bin/env python3
"""Seed the tail PLT stubs that the liveness walk misses.

The lifted set ends at ~0x258000 with the liveness walk's entry list. The last
420 words of the ELF text (0x258000..0x25868C) are the compiler's tail-of-text
PLT stubs -- `stdu r12,-0x70(r1); mflr r0; std r0,0x10(r1); stmw/bdsp/stwu`
prologues the liveness walk never seeds because nothing `bl`s them by name.
With them absent, ~420 call targets resolve to nothing and the boot path stalls.
Seed them as explicit entries in generated/functions.json, then re-run
gen_stubs.py. Idempotent: it merges, never duplicates.
"""
import json, pathlib
from capstone import CS_ARCH_PPC, CS_MODE_BIG_ENDIAN, Cs

ELF = pathlib.Path("input/EBOOT.ELF")
ELF_OFF, TEXT_START, TEXT_END = 0x66800, 0x10200, 0x258690
FN_JSON = pathlib.Path("generated/functions.json")

STUB_FIRST_WORDS = (0x39800000, 0x39810000, 0xF8010010, 0xF821FEF1, 0xF841FF71)


def main():
    blob = ELF.read_bytes()

    def word(ea):
        o = ELF_OFF + ea - TEXT_START
        return int.from_bytes(blob[o:o + 4], "big")

    funcs = json.loads(FN_JSON.read_text())
    have = {int(f["start"], 16) for f in funcs}
    added = 0
    ea = 0x258000
    while ea < TEXT_END:
        if word(ea) in STUB_FIRST_WORDS and ea not in have:
            funcs.append({"start": f"0x{ea:08X}", "end": f"0x{ea + 16:08X}"})
            have.add(ea)
            added += 1
        ea += 4
    FN_JSON.write_text(json.dumps(funcs, indent=1))
    print(f"seeded {added} tail PLT stubs -> {len(funcs)} functions")


if __name__ == "__main__":
    main()
