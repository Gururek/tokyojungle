#!/usr/bin/env python3
"""Disassemble guest EAs from the ELF on the ISO -- the one helper for ad-hoc
code reading, so traces and disassembly stay comparable across sessions.

    .venv/bin/python scripts/gdis.py 0x001F2D88 40      # 40 insns from EA
    .venv/bin/python scripts/gdis.py 0x1F2D88 --calls    # + annotate bl targets
"""
import sys
from capstone import CS_ARCH_PPC, CS_MODE_BIG_ENDIAN, Cs

ELF = "input/EBOOT.ELF"          # extracted from the ISO: file offset 0x66800 == vaddr 0x10200
ELF_OFF, ELF_VADDR = 0x66800, 0x10200


def blob():
    with open(ELF, "rb") as f:
        return f.read()


PHDRS = [(0x10000, 0x10000, 0x324768), (0x340000, 0x340000, 0x7EBF0)]


def ea2off(ea):
    """EA -> file offset, from the ELF program headers. Segment 1 is
    self-decompressed at a 0x56600 skew; segment 2 maps identity."""
    for off, va, sz in PHDRS:
        if va <= ea < va + sz:
            return off + (ea - va)
    return ELF_OFF + ea - ELF_VADDR


def read(b, ea, n):
    o = ea2off(ea)
    return b[o: o + n]


def main():
    args = sys.argv[1:]
    ea = int(args[0], 16)
    n = int(args[1]) if len(args) > 1 and args[1].isdigit() else 40
    calls = "--calls" in args
    b = blob()
    md = Cs(CS_ARCH_PPC, CS_MODE_BIG_ENDIAN)
    for i in md.disasm(read(b, ea, 4 * n), ea):
        a = i.address
        line = f"  {a:08X}  {i.mnemonic:8s} {i.op_str}"
        if calls and i.mnemonic.startswith("bl"):
            t = i.op_str.lstrip("0x")
            if t.isdigit() or (t and t[0] in "0123456789abcdefABCDEF" and "0x" in i.op_str):
                line += f"    // func_{int(t, 16):08X}"
        print(line)


if __name__ == "__main__":
    main()
