# Tokyo Jungle (JP, BCJS30069) — port state, 2026-11-11

## What this project is
A PS3→PC recompile of **Tokyo Jungle**. Two trees work together:

- `~/workspaces/tokyo-jungle-recompiled` (this repo, branch **las-port**) — the
  title-specific half: the lifted PPU translation (`generated/ppu_recomp_*.cpp`,
  12 MB of C++ per TU, 8,006 guest functions), the app harness (`src/main.cpp`),
  import routing (`src/hle_imports.h`, `src/import_resolver.h`,
  `src/dispatch_glue.cpp`), the present thread (`src/tj_present.cpp`), the
  sysutil event pump (`src/tj_sysutil.cpp`), and the analysis scripts
  (`scripts/*.py`).
- `~/workspaces/ps3recomp` (remote `fork` = Gururek/ps3recomp, branch
  **tokyojungle**, pinned at `d7fff845` + `patches/ps3recomp/
  ps3recomp-tokyojungle-2026-10-17.patch`) — the emulator half: PPU loader,
  lv2 syscalls, cellPad, cellGcmSys, the RSX backends, and the lifter tools.

Disc: `input/EBOOT.ELF` (JP, SELF key_rev 0x19, decrypted by
`scripts/decrypt_self.py`). The reference fork **LasVola/tokyojungle** runs the
**US** disc (NPUA80523) on Windows/D3D12 and is "Playable" (Survival, 60 FPS) —
same code, different addresses, so map by *role*, not by address.

## Build/run loop
```
export PATH="$PWD/.venv/bin:$PATH"          # cmake 4.4.4 + ninja live in .venv
scripts/bgtask.sh cycle-N sh -c 'python scripts/analyze.py --skip-to lift &&
    python scripts/gen_stubs.py --tus 12 &&
    PYTHONPATH=../ps3recomp/tools python scripts/fix_import_slots.py &&
    python scripts/post_lift.py && python scripts/probe_screen.py &&
    python scripts/probe_pump.py &&
    cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DPS3RECOMP_RSX_VULKAN=OFF &&
    cmake --build build -j16'
scripts/bgstatus.sh                          # what is still running
scripts/buildlog.sh logs/cycle-N.log         # failures + real warnings + link
SDL_VIDEODRIVER=x11 ./build/tokyojungle
scripts/shot.sh                              # capture the ps3recomp window only
```
`--tus 12` splits the lifted source into 12 TUs so a full `-j16` build is bound
by 12 parallel compiles, not by one 111 MB TU.

## Boot chain (what works today)
1. VM + VFS + LV2 table → ELF entry `0x003428F0` → code `0x00010230`, TOC
   `0x003591E0`; TLS at `0x01300000`, `r13=0x01307000`, `SP=0xD00FFFD0`.
2. `main = func_00010354`: CRT init, then **one** call into the screen pump,
   then `printf`, then return — so the harness (`src/main.cpp` frame loop,
   `TJ_FRAME_LOOP`) drives `func_001F2D88` once per frame.
3. `cellPadInit(4, 3)` returns the connected-port count (ps3recomp
   `libs/input/cellPad.c` POSIX poll returns port 0 even with no gamepad).
4. GCM: `_cellGcmInitBody(cmdSize=0x10000, ioSize=0, ioAddr=0x02100000)`; the
   ioSize=0 default (16 MB) is what maps the ring's idle-jump slot at io
   `0x01000000`. The boot FIFO buffer at ea `0x02100000` is decoded
   (`logs/fifo-notes.md`): four subchannel-0 semaphore releases, a 1280×720
   viewport/scissor block, and one `SET_REFERENCE` (`0x00040050`, fence 0) at
   `+0xEC`. `put == get == ref == 0xF4` now, i.e. the FIFO drains.

## The two live walls
- **Per-frame ticket handshake.** The pump publishes a ticket into the GCM tick
  ring (obj `[[TOC+0x14DC]]` = `0x03002000`, record `0x00040050` + count,
  producer `func_001F73CC`) then spins on the consumer counter at
  `0x02010000+8` (`func_001F734C`, signed compare, budget `r28=0x2D0`). The
  host ticks it from `src/tj_present.cpp` (`TJ_TICKRING=0x02010008`,
  `TJ_TICK_US=8000`). The consumer's callbacks are reached through the guest
  GOT (`func_0025C2C0` → `[0x00342500]` → `0x003B4388`, `func_0025C0A0` →
  `[0x003424BC]` → `0x003B42B8`); in the RW segment those are small method
  tables, so the handshake is data-driven — `scripts/seed_tick_fns.py` seeds
  them (ends = start + 4, the lifter emits its terminator *at* `end`).
- **No pixels.** The window shows black. The host-side backend on POSIX is
  `libs/video/rsx_null_backend.c` (SDL2 + fixed-function GL), which today draws
  a clear only. LasVola's visible output comes from a real RSX backend, so the
  highest-value parallel track is `PS3RECOMP_RSX_VULKAN=ON` (branch
  **vulkan-port**: master's `rsx_vulkan_backend.c` + `libs/video/vulkan/` +
  `rsx_shader_spirv` + 9 helper TUs, needs a master→pin header migration —
  74 `rsx_fp_decompiler.c` + 54 `cellGcmSys.c` errors).

## Ranked plan
1. **Pixels:** land the Vulkan RSX backend on the pin (`vulkan-port`), keep the
   null backend as the headless fallback.
2. **Pump depth:** get past the per-frame ticket spin so the pump walks the
   16-screen state machine (`func_001F2F84` dispatches on `r31` = 0x131/0x132/
   0x101) and the title screen appears.
3. **Input:** pad → the README's 16-screen map; `scripts/keyinject.py` drives
   the `ps3recomp` window with XTEST.
4. **Audio/SFX:** FMOD + SGX bank loader ("the SGX bank loader is the only
   thing that opens files").

## Boot model, decoded (2026-11-11)

The JP disc's frame is a producer/consumer handshake, not a flat loop. Reading it
in terms of "who is waiting for whom" is the only way to make progress on the
black screen, so the pieces are recorded here:

- **Pump** `func_001F2D88` = one screen step (main() calls it once; `src/main.cpp`
  drives it per host frame). Head calls `func_001F2478` which allocates the frame's
  **ticket** (`func_0023B8FC` 0x90-byte blocks) and sets `r28 = [obj] + 0x2D0` — the
  `r28=720` in the `[SCR]` probes is that, not a flag count.
- **Ticket** (`func_001F31A0`): `[0x00]=5` type, `[0x04]=0x500` capacity,
  `[0x08]=0x2D0` budget, `[0x1C]` read cursor, `[0x1D]=1` armed.
- **Publish** `func_001F15A0` (needs byte `[0x14] != 0`) → `func_001F5164` →
  `func_001F4CC4`: a linked list walked from `[TOC+0x1594]`, calling each node's
  vtable slot `[0x0]`. This is the flip/swap notifier.
- **Drain** `func_001F1708` returns 0 unless bytes `[0x05]` and `[0x06]` are set;
  `func_001F54EC` early-exits on the same two bytes, else calls the ticket's
  vtable method `[0x10]`.
- **Tick ring** `[[TOC+0x14DC]]` = `0x03002000` = the GCM control block. Producer
  `func_001F73CC(obj,count)` writes the record `0x00040050` (type 4, tag 0x50 =
  `SET_REFERENCE`) + the count at `[obj+8]`, bumping the write index by 8.
  `func_001F734C` = producer + consumer + `sys_timer_usleep(30)` spinning while
  **signed** `(int)ticket < (int)[r30+8]`.
- **Consumer** `func_001F72F4` = `func_0025C2C0` (GOT `[0x00342500]` → `0x003B4388`,
  an acquire that returns a ticket pointer) then `func_0025C0A0` (GOT `[0x003424BC]`
  → `0x003B42B8`) copies the ring's write index into the ticket. The 0x003B42xx/
  0x003B43xx targets live in the RW LOAD segment (file 0x340000 → vaddr 0x340000,
  memsz 0x8CE008) as method tables, so this handshake is data-driven, not calls.
- **Screen handler** `func_001F2F84(r3 = screen id, r5 = flag)`: runs the
  `[TOC+0x14E0]` (= `0x00C03F2C`) object's vtable slot `[0x0]` when non-null, then
  dispatches `0x131` → `func_0023F38C([TOC+0x14E8])` + screen-object method `[0x1C]`,
  `0x132` → `[TOC+0x14EC]` + method `[0x20]`, `0x101` → a third path. `func_0023F38C`
  is the screen/table setter (`[TOC+0x2858]`, `func_00242FBC`, `func_0023D580`).
- **Screen table** `func_001F61EC`: `func_0023B8FC(8)` + `func_0023B8FC(0x5C4)`,
  writes `[r9]=0`, `[r9+4]=-1`, `[r9+0xC]=r28`. `[TOC+0x15FC]` = the pad state,
  `[TOC+0x1608]` = the button-history ring (see `func_001F60E8`, which writes
  `[+0x4B0]/[+0x4B1]/[+0x4B2]` = button/analog/flag).

## Build discipline

- The lifted units get `TJ_GENERATED_VM_FAST_ACCESS` on every platform (the
  CMakeLists.txt guard used to be WIN32-only).  With the inline VM accessors a
  unit is ~40 MB and compiles in ~2 min; the out-of-line fallback spells the
  access out at ~1M call sites and produces ~140 MB units, which is where the
  long compiles came from.
- Optimization is `TJ_GENERATED_PPU_OPT` (default **-O1**), applied to both
  compilers.  Measured on a 138 MB unit: -O3 ~6 min and crashes, -O2 ~4 min
  (clang dies in `called-value-propagation`), -O1 ~2 min and crashes on no unit.
- GCC 16.2.1 segfaults (cc1plus signal 11) on a rotating subset of the units;
  `scripts/ccbuild.sh` runs up to four ninja passes at decreasing `-j` and
  ninja's incremental state recompiles only what failed.
- 8 translation units (`scripts/gen_stubs.py --tus 8`) is the sweet spot.
- Keep total ninja width ≤ 16: two concurrent builds (`build`, `build-vk`) at
  -j16 saturate the machine.  `scripts/cbuild.sh` = a single low-`-j` pass.
- Daily driver is **build-clang** (clang 23): `cmake -B build-clang -G Ninja
  -DCMAKE_BUILD_TYPE=Release -DPS3RECOMP_RSX_VULKAN=OFF
  -DCMAKE_EXPORT_COMPILE_COMMANDS=ON -DCMAKE_C_COMPILER=clang
  -DCMAKE_CXX_COMPILER=clang++`, then `scripts/bgtask.sh work-A
  scripts/work.sh work-A` (build + run batches, one row in the ledger,
  `scripts/bgstatus.sh` says RUNNING/STALE/OK/FAIL).

## Why the screen is black on the master/Vulkan tree (run-m8..m14)

The pump runs (6,556 steps with `TJ_TICKRING=0x20002008 TJ_TICKVALUES=0,FFFFFFFF`)
and the window shows the boot clear, but the title submits **one** FIFO command
buffer of 252 bytes: `TJ_REFWATCH` says `put=001000FC get=001000FC ref=FFFFFFFF`
and never changes, so per-frame submissions stop after boot.  Evidence:

- `TJ_GENMAP=1 TJ_IMPTRACE=1` over 5,618 pump steps: **36 HLE calls in total**
  (one each: cellPadInit/End, cellVideoOut*, cellSysutil*, sys_lwmutex*,
  sys_initialize_tls, cellSysmoduleLoadModule).  Zero GCM calls per frame.
- `RSX_ENGINE_PASS_DUMP=logs/passes RSX_ENGINE_PASS_DUMP_AFTER=5` captures **no
  passes** — no draw reaches the register-file engine (it is up:
  `[rsx engine] register-file draw engine up (1280x720)`,
  `[rsx engine] surface 0:0x00000000 1280x720 fmt 3`, so the framebuffer is set).
- `PS3_CALLTRACE=260` over 1,398 steps: the dominant per-frame call target is
  **0x00000000 (124 hits)**, i.e. a virtual method on an object whose vtable
  word is 0.  Two sites:
    * `func_000266B4+0xF3D` (lr=0x000266F4) walks an intrusive list of 0x30-byte
      elements at 0x00A7F010, 0x00A7F040, ... (word +0x14 = next, +0x18 = prev;
      every other field is 0, so the elements are value-initialised) and calls
      `[[obj]+0]` per element.
    * `func_001F5320+0x276` (lr=0x001F5338, the `bl 0x1f30ec` thunk) with
      r3=0 r4=0 r5=0x00F00004 — the ticket publish path calling a method on a
      null object.
- The screen machine's per-frame entry runs only twice, at boot:
  `[SCR] handler r3=0 r5=0` then `[SCR] handler r3=6 r5=0` (JP disc ids, small
  integers, not the NA disc's 0x131/0x132/0x101).  The list-flag byte
  `[TOC+0x14D8]` = 0x00C03F28 reads 0, and the list heads at 0x00C03F2C/30 are
  0 — nothing is queued, so every pump call takes the empty-drain path.

So the roadblock is upstream of the backend: the per-frame path stops at a
virtual call on an uninitialised object, and the screen list is empty.
Next probes: find who fills those 0x30-byte list elements (and their vtable),
and who is supposed to enqueue a screen.
