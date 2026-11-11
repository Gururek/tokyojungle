#!/usr/bin/env python3
"""Insert printf probes into the lifted pump (and any lifted function).

The lifted C++ is generated, so probes live in the generated tree the same way
the heap/abort redirects do (see scripts/post_lift.py) -- a marker line makes
the insertion idempotent, so re-running it is free.

    .venv/bin/python scripts/probe_screen.py            # pump + tick trio
    .venv/bin/python scripts/probe_screen.py --clean

Probes print to stderr and are cheap (one fprintf per call); gate them behind
the pump's own cadence, not a hot loop.
"""
import re
import sys

TARGET = "generated/ppu_recomp_000.cpp"
MARK = "[SCR] probe"

# (anchor line fragment, probe printf body)
PROBES = [
    ('ctx->lr = 0x001F2E54; func_0025C4C0(ctx); DRAIN_TRAMPOLINE(ctx);',
        'printf("[SCR] pre-drain ticket=%08X flagbyte=%d\\n",'
        '(uint32_t)ctx->gpr[31], (int)(int32_t)vm_read8(ctx->gpr[2]+0x14D8));'),
    ('ctx->lr = 0x001F2EA4; func_001F734C(ctx); DRAIN_TRAMPOLINE(ctx);',
        'printf("[SCR] tick0 obj=%08X wi=%08X ticket=%08X\\n",'
        '(uint32_t)ctx->gpr[3], (uint32_t)vm_read32(vm_read32(ctx->gpr[2]+0x14DC)+8),'
        '(uint32_t)ctx->gpr[28]);'),
    ('ctx->lr = 0x001F2EB8; func_001F734C(ctx); DRAIN_TRAMPOLINE(ctx);',
        'printf("[SCR] tickF0 wi=%08X\\n",'
        '(uint32_t)vm_read32(vm_read32(ctx->gpr[2]+0x14DC)+8));'),
    ('ctx->lr = 0x001F2EC4; func_001F15A0(ctx); DRAIN_TRAMPOLINE(ctx);',
        'printf("[SCR] post-ticks r30=%08X wi=%08X\\n",(uint32_t)ctx->gpr[30],'
        '(uint32_t)vm_read32(vm_read32(ctx->gpr[2]+0x14DC)+8));'),
    ('ctx->lr = 0x001F2E74; func_001F1708(ctx); DRAIN_TRAMPOLINE(ctx);',
        'printf("[SCR] drain pass ticket=%08X r28=%08X type=%d head=%08X tail=%08X cur=%d cap=%d\\n",'
        '(uint32_t)ctx->gpr[31],(uint32_t)ctx->gpr[28],'
        "(int)(int32_t)vm_read32((uint32_t)ctx->gpr[31]),"
        "(int)(int32_t)vm_read32((uint32_t)ctx->gpr[31]+4),"
        "(int)(int32_t)vm_read32((uint32_t)ctx->gpr[31]+8),"
        "(int)(int32_t)vm_read32((uint32_t)ctx->gpr[31]+0x1C),"
        '(int)(int32_t)vm_read32((uint32_t)ctx->gpr[31]+0x20));'),
    ('ctx->lr = 0x001F2F74; func_00243E0C(ctx); DRAIN_TRAMPOLINE(ctx);',
        'printf("[SCR] register-request idx=%d ret=%d\\n",(int)(int32_t)ctx->gpr[3],'
        "(int)(int32_t)ctx->gpr[26]);"),
]


def main():
    txt = open(TARGET, encoding="utf-8").read()
    if "--clean" in sys.argv:
        txt = re.sub(r"^        /\* " + re.escape(MARK) + r" \*/.*?\n        printf\(.*?\);\n",
                     "", txt, flags=re.M | re.S)
        open(TARGET, "w", encoding="utf-8").write(txt)
        print("probes removed")
        return
    n = 0
    for anchor, probe in PROBES:
        tag = "/* " + MARK + " */"
        if probe.split("(")[0] in txt and tag in txt:
            pass
        idx = txt.find(anchor)
        if idx < 0:
            print("anchor missing:", anchor[:48])
            continue
        end = idx + len(anchor)
        block = txt[end:end + 200]
        if tag in block:
            continue
        ins = "\n        " + tag + " " + probe + "\n"
        txt = txt[:end] + ins + txt[end:]
        n += 1
    open(TARGET, "w", encoding="utf-8").write(txt)
    print(f"probes inserted: {n}")


if __name__ == "__main__":
    main()
