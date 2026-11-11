#!/usr/bin/env python
"""Pretty-print a TJ_DUMP binary as words, and name any pointer it holds.

Boot-state questions are usually "what is this object's vtable, and which
lifted function is each slot?"  src/main.cpp's TJ_DUMP writes the raw guest
bytes to logs/dump_<addr>_<len>_<delay>ms.bin; this reads one back, prints the
words big-endian, and resolves every word that points inside a lifted function
so a vtable reads as a method list.

Usage:
    scripts/vtable.py logs/dump_00C03F50_00000040_1500ms.bin
    scripts/vtable.py <bin> --base 0x00C03F50      # label each word's address
"""
import argparse
import bisect
import json
import struct
import sys

FNS = 'generated/functions.json'


def load_functions(path=FNS):
    starts, ends = [], {}
    for e in json.load(open(path)):
        s = int(e['start'], 16) if isinstance(e['start'], str) else e['start']
        en = int(e['end'], 16) if isinstance(e['end'], str) else e['end']
        starts.append(s)
        ends[s] = en
    starts.sort()
    return starts, ends


def symbol(addr, starts, ends):
    i = bisect.bisect_right(starts, addr) - 1
    if i < 0:
        return None
    s = starts[i]
    if addr < ends[s]:
        return f"func_{s:08X}+0x{addr - s:x}"
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('bin')
    ap.add_argument('--base', default='0', help='guest address the dump started at')
    ap.add_argument('--words', type=int, default=0, help='stop after N words')
    a = ap.parse_args()

    base = int(a.base, 16) if a.base.startswith('0x') else int(a.base, 16)
    starts, ends = load_functions()
    data = open(a.bin, 'rb').read()
    n = len(data) // 4
    if a.words:
        n = min(n, a.words)
    for i in range(n):
        v = struct.unpack_from('>I', data, i * 4)[0]
        sym = symbol(v, starts, ends)
        tag = f"  -> {sym}" if sym else ''
        print(f"[0x{base + i * 4:08X}] = 0x{v:08X}{tag}")


if __name__ == '__main__':
    sys.exit(main())
