#!/usr/bin/env bash
# Show lifted lines that touch a TOC-relative global (TOC = 0x003591E0), with the
# owning function's name. usage: scripts/tocrefs.sh 0x14DC
a="${1#0x}"
grep -nE "gpr\[(2|13)\] \+ 0x${a}\b" generated/ppu_recomp_*.cpp | head -30
