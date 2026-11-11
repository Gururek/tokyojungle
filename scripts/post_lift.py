#!/usr/bin/env python3
"""Post-lift patches for the Tokyo Jungle recompilation.

Run after the lifter, before building. Idempotent: re-running on an
already-patched tree is a no-op. The generated tree is regenerate-able, so
patches belong here rather than being hand-edited into it.

Currently patches: the PS3 libc/CRT init chain -> tj_crt_skip (see
src/tj_crt_overrides.cpp for why each one is skipped).

The lifter emits each function as

    void func_XXXXXXXX(ppu_context* ctx) {
        ...body...
    }                                        <- a lone "}" at column 0

so we replace the whole span [signature line .. next lone "}"] with a
one-line redirect. This is robust to the body's own nested braces (which are
indented). Same shape as rubberducky/tools/post_lift.py.
"""
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RECOMP_GLOB = os.path.join(ROOT, "generated", "ppu_recomp_*.cpp")
# scripts/gen_stubs.py splices the lifter's ppu_recomp_NNN.cpp chunks into one
# translation unit, so on a prepared tree that is the only file to patch.
MERGED_GLOB = os.path.join(ROOT, "generated", "ppu_recomp.cpp")

# guest addr -> human name. The real bodies abort() or wander into kernel
# structures the HLE runtime does not model.
CRT_SKIPS = {
    # Empty: with the import table fully resolved (see src/import_resolver.h)
    # the real CRT init chain runs. It only abort()ed because
    # sys_ppu_thread_create "returned" a stale nonzero r3 -- the call had been
    # dropped by the lifter. Re-add an address here if its real body proves
    # too far ahead of the runtime.
}

# The __sys_init_* entries at 0x0025Fxxx that the old generated/ppu_stubs.c
# also stubbed are .stub import thunks, not functions -- find_functions no
# longer emits them and src/import_resolver.h owns that range instead.

SIG = re.compile(r"void func_([0-9A-F]{8})\(ppu_context\* ctx\) \{\s*$")
MARK = "/* tj-crt-skip"
HEAP_MARK = "/* tj-heap"

# guest addr -> (host redirect symbol, human name). The libc heap wrappers:
# the mspace they front is never initialised, so all of them return 0 and the
# game aborts with "exception: bad allocation" before graphics init. See
# src/tj_crt_overrides.cpp for how each was identified from the binary.
#
# The addresses are per-disc: each region ships its own libc build at a
# different offset, and the JP disc's CRT is the same code shifted. Both sets
# are listed because the patch script is shared; addresses absent from the
# current lift are reported as a NOTE, not an error.
HEAP_PATCHES = {
    # NA disc (NPUA80523 / BCAS20219 builds this repo was developed against)
    "0024DDC0": ("tj_heap_malloc",   "malloc"),
    "0024DD94": ("tj_heap_free",     "free"),
    "0024DCBC": ("tj_heap_free",     "free (realloc-internal)"),
    "0024DCEC": ("tj_heap_memalign", "memalign"),
    "0024DD24": ("tj_heap_realloc",  "realloc"),
    # JP disc (BCJS30069 -- the disc this checkout runs). Identified the same
    # way as the NA set: the eight wrappers that read the mspace handle from
    # TOC+0x29E8 (NA: TOC+0x2A98), matched by their single dlmalloc callee and
    # by the NA call-site counts (malloc 25, free 100, memalign 50). realloc is
    # the one whose callee also calls the free wrapper.
    "0024C360": ("tj_heap_malloc",   "malloc"),
    "0024C334": ("tj_heap_free",     "free"),
    "0024C25C": ("tj_heap_free",     "free (realloc-internal)"),
    "0024C28C": ("tj_heap_memalign", "memalign"),
    "0024C21C": ("tj_heap_realloc",  "realloc"),
    # Diagnostic, not a heap wrapper: the guest abort() walks its own stack
    # to print a backtrace and faults doing it when the stack is the thing
    # that is wrong. See src/tj_crt_overrides.cpp.
    "0023E380": ("tj_abort",        "abort"),   # NA
    "0023C920": ("tj_abort",        "abort"),   # JP
    # The JP abort on BCJS30069 is the one that allocates a report buffer
    # (sys_mmapper 0x3DC), sleeps (0x193) and walks its own stack to print
    # "abort() is called from 0x..." + "Continue... (Lv-2 is still running.)".
    # 0023C920 is its stack-walker callee.
    "0023CA80": ("tj_abort",        "abort"),   # JP (the reporter)
    "0025279C": ("tj_pure_virtual", "__cxa_pure_virtual"),
}


def patch_file(path):
    with open(path, "r", encoding="utf-8", errors="surrogateescape") as f:
        lines = f.readlines()

    out, i, patched = [], 0, set()
    while i < len(lines):
        m = SIG.match(lines[i])
        addr = m.group(1) if m else None
        if addr in HEAP_PATCHES:
            sym, name = HEAP_PATCHES[addr]
            if HEAP_MARK in (lines[i + 1] if i + 1 < len(lines) else ""):
                patched.add(addr)                    # already patched
                out.append(lines[i]); i += 1; continue
            j = i + 1
            while j < len(lines) and lines[j].rstrip(chr(10)) != "}":
                j += 1
            out.append(lines[i])
            out.append("    " + HEAP_MARK + ": " + name + " -> " + sym + " */" + chr(10))
            out.append("    extern void " + sym + "(ppu_context*);" + chr(10))
            out.append("    " + sym + "(ctx);" + chr(10))
            out.append("}" + chr(10))
            patched.add(addr)
            i = j + 1
            continue
        if addr in CRT_SKIPS:
            if MARK in (lines[i + 1] if i + 1 < len(lines) else ""):
                patched.add(addr)                       # already patched
                out.append(lines[i]); i += 1; continue
            j = i + 1
            while j < len(lines) and lines[j].rstrip("\n") != "}":
                j += 1
            name = CRT_SKIPS[addr]
            out.append(lines[i])
            out.append('    %s: %s */\n' % (MARK, name))
            out.append('    extern void tj_crt_skip(ppu_context*, const char*);\n')
            out.append('    tj_crt_skip(ctx, "%s");\n' % name)
            out.append("}\n")
            patched.add(addr)
            i = j + 1
            continue
        out.append(lines[i]); i += 1

    if patched:
        with open(path, "w", encoding="utf-8", errors="surrogateescape") as f:
            f.writelines(out)
    return patched


# The lifter emits a load-multiple (lmw) as one statement per register joined
# with " ".  For a 24-register lmw the join can drop a separator, leaving
# `vm_read32(_ea + 28){ ctx->gpr[15] = ...` -- one missing ';' in a 90 MB
# translation unit, which GCC reports as "expected ';' before '{' token" plus a
# brace-imbalance cascade ("a function-definition is not allowed here",
# "jump to label").  Repair it here so every lift gets a clean tree.
LMW_SEMICOLON = re.compile(r"vm_read32\(_ea \+ (\d+)\)(?=\{)")

# A single stray '`' lands in the lifted text at one spot per emitted file
# (`ctx->gpr[13]`= _b - _a; ...`): GCC reads it as "stray '`' in program" and
# then reports an "unable to find numeric literal operator" cascade.  It is a
# ';' that the writer emitted as a backtick.
STRAY_TICK = re.compile(r"\]=` = ")

# Two more single-shot writer glitches seen in the emitted text: a digit glued
# in front of a declaration (`; 5int32_t _c = ...`) and a subscript that loses
# its `] =` (`ctx->gpr[13 _b - _a;`).
STRAY_DIGIT = re.compile(r"(?<=[;}]) ?\d(?=int32_t _\w+ =)")
MANGLED_SUB = re.compile(r"ctx->gpr\[(\d+) (?=\w+ - \w+;)")


def repair_lmw_semicolons(path):
    with open(path, 'r') as f:
        text = f.read()
    fixed, n = LMW_SEMICOLON.subn(r"vm_read32(_ea + \1);", text)
    fixed, t = STRAY_TICK.subn("] = ", fixed)
    fixed, d = STRAY_DIGIT.subn("", fixed)
    fixed, m = MANGLED_SUB.subn(r"ctx->gpr[\1] = ", fixed)
    if n or t:
        with open(path, 'w') as f:
            f.write(fixed)
    return n + t + d + m


def main():
    files = sorted(glob.glob(RECOMP_GLOB))
    if not files:
        files = sorted(glob.glob(MERGED_GLOB))
    if not files:
        print("post_lift: no %s -- run the lifter first" % RECOMP_GLOB,
              file=sys.stderr)
        return 1

    mended = 0
    for path in files:
        mended += repair_lmw_semicolons(path)
    if mended:
        print("post_lift: repaired %d lmw statement(s) missing a ';'" % mended)

    done = set()
    for path in files:
        done |= patch_file(path)

    want = set(CRT_SKIPS) | set(HEAP_PATCHES)
    print("post_lift: %d/%d redirects (%d CRT skips, %d heap)"
          % (len(done), len(want), len(CRT_SKIPS), len(HEAP_PATCHES)))
    missing = sorted(want - done)
    if missing:
        # Not fatal: a re-lift with a newer ps3recomp discovers functions from
        # a slightly different seed set, so some of these guest addresses are
        # simply not lifted as standalone entries any more.
        print("  NOTE: not present in this lift (address moved or the lifter "
              "inlined it): %s" % ", ".join(missing))
    return 0


if __name__ == "__main__":
    sys.exit(main())
