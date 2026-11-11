/* Present / vblank ticker.
 *
 * Nothing in Tokyo Jungle's harness was advancing the display. The game
 * requests a flip (_cellGcmSetFlipCommand), then polls cellGcmGetFlipStatus
 * until it clears -- and it never did, because cellGcmTickFlip is what clears
 * it and no thread was calling it. The boot sat in that poll forever.
 *
 * ps3recomp's own harness (runtime/ppu/tests/boot_main.cpp) and the LBP port
 * both run a thread like this; TJ has its own main() and so needs its own.
 *
 * The ticks are driven off real elapsed time rather than off how long
 * present() takes: on a hidden or occluded window DXGI throttles Present
 * hard, and pacing the guest's frame counter behind it drops the whole boot
 * to a few frames a second.
 *
 * ponytail: a straight copy of the harness cadence (16 ms ticks, drain at the
 * outer 4 ms cadence). If TJ turns out to need different pacing, measure
 * before changing it -- the drain interval is load-bearing for titles that
 * fence every render pass.
 */
#include <stdio.h>
#include <stdlib.h>
#ifdef _WIN32
#include <windows.h>
#else
#include "platform/win32_compat.h"   /* ULONGLONG/GetTickCount64/Sleep/DWORD WINAPI */
#endif

#include "ppu_context.h"
#include "recomp_bridge.h"   /* vm_write64 (diagnostic clock tick) */
#include "sys_ppu_thread.h"

/* TJ_THREADS=1: every 2 s, print each PPU thread's state and the guest address
 * of its last syscall/HLE call (prof_pc). The watchdog only samples the main
 * thread, so a worker that finished early or wedged is otherwise invisible --
 * and "the game runs its frame loop but never loads anything" is exactly the
 * shape a wedged worker produces. */
static void tj_dump_threads(void)
{
    static int on = -1;
    if (on < 0) on = getenv("TJ_THREADS") ? 1 : 0;
    if (!on) return;

    static ULONGLONG next = 0;
    ULONGLONG now = GetTickCount64();
    if (now < next) return;
    next = now + 2000;

    static const char* kState[] = { "FREE", "RUNNING", "FINISHED", "DETACHED" };
    fprintf(stderr, "[threads]\n");
    for (int i = 0; i < PPU_THREAD_MAX; i++) {
        const ppu_thread_info* t = &g_ppu_threads[i];
        if (t->state == PPU_THREAD_STATE_FREE) continue;
        fprintf(stderr, "   tid=%d %-9s entry=0x%08llX prof_pc=0x%08X name=\"%s\"\n",
                i, kState[t->state & 3],
                (unsigned long long)t->entry_addr, t->prof_pc, t->name);
    }
}

extern "C" {
void cellGcmTickVBlank(void);
void cellGcmTickFlip(void);
void cellGcm_rsx_process_fifo(void);
int  cellGcm_take_flip_pending(void);
}

/* Render backend, same selection ps3recomp's own host (runtime/host/host_posix.c)
 * and project template make: D3D12 on Windows, Vulkan on Linux when the runtime
 * is configured with -DPS3RECOMP_RSX_VULKAN=ON, and the headless null backend
 * everywhere else. All three expose the same three entry points. This matters
 * beyond pixels: cellGcm_rsx_process_fifo() is only driven when the backend is
 * up, and the fences it publishes are what ctrl->ref advances -- with no
 * backend the guest's first `while (ctrl->ref != put) usleep(30);` never ends. */
#if defined(_WIN32)
extern "C" int  rsx_d3d12_backend_init(int w, int h, const char* title);
extern "C" void rsx_d3d12_backend_present(void);
extern "C" int  rsx_d3d12_backend_pump_messages(void);
#  define rsx_backend_init    rsx_d3d12_backend_init
#  define rsx_backend_present rsx_d3d12_backend_present
#  define rsx_backend_pump    rsx_d3d12_backend_pump_messages
#  define RSX_BACKEND_NAME    "D3D12"
#elif defined(PS3RECOMP_RSX_VULKAN)
extern "C" int  rsx_vulkan_backend_init(uint32_t w, uint32_t h, const char* title);
extern "C" void rsx_vulkan_backend_present(void);
extern "C" int  rsx_vulkan_backend_pump_messages(void);
#  define rsx_backend_init    rsx_vulkan_backend_init
#  define rsx_backend_present rsx_vulkan_backend_present
#  define rsx_backend_pump    rsx_vulkan_backend_pump_messages
#  define RSX_BACKEND_NAME    "Vulkan"
#else
extern "C" int  rsx_null_backend_init(uint32_t w, uint32_t h, const char* title);
extern "C" void rsx_null_backend_present(void);
extern "C" int  rsx_null_backend_pump_messages(void);
#  define rsx_backend_init    rsx_null_backend_init
#  define rsx_backend_present rsx_null_backend_present
#  define rsx_backend_pump    rsx_null_backend_pump_messages
#  define RSX_BACKEND_NAME    "null (headless software)"
#endif

/* Window lifetime, so main() can stop its frame loop when the user closes it. */
static volatile int s_window_alive = 1;
extern "C" int tj_window_alive(void) { return s_window_alive; }

/* Present on every tick, not only on a flip.
 *
 * The title flips rarely while it boots, so a flip-driven present leaves the
 * window (and PS3RECOMP_VK_DUMP's PPM) showing whatever the first frame left
 * behind. Presenting the offscreen target again is cheap and makes each
 * screenshot show the current state. TJ_PRESENT_ALWAYS=0 keeps the old
 * behaviour. */
static int tj_present_always(void)
{
    static int cached = -1;
    if (cached < 0) {
        const char* e = getenv("TJ_PRESENT_ALWAYS");
        cached = (e && e[0] == '0') ? 0 : 1;
    }
    return cached;
}

static DWORD WINAPI tj_present_thread(LPVOID)
{
    const char* title = getenv("PS3_TITLE");
    if (!title || !*title) title = "Tokyo Jungle (ps3recomp)";

#if defined(PS3RECOMP_RSX_VULKAN) && !defined(_WIN32)
    /* The Vulkan backend renders offscreen by default and only creates a
     * window when PS3RECOMP_VK_WINDOW is set; the null/GL backend always
     * created one.  Set it so both trees show their window. */
    if (!getenv("PS3RECOMP_VK_WINDOW")) setenv("PS3RECOMP_VK_WINDOW", "1", 0);
    /* SDL reports "x11 not available" when DISPLAY is unset, which is how a
     * background run starts, and the run then looks headless. */
    if (!getenv("DISPLAY")) setenv("DISPLAY", ":0", 0);
#endif

    int rsx_ok = (rsx_backend_init(1280, 720, title) == 0);
    fprintf(stderr, "[rsx] " RSX_BACKEND_NAME " backend init %s\n",
            rsx_ok ? "OK -- window open" : "FAILED");

    ULONGLONG next_tick = GetTickCount64();
    for (;;) {
        Sleep(4);
        ULONGLONG now = GetTickCount64();

        int fired = 0;
        while ((long long)(now - next_tick) >= 0 && fired < 240) {
            /* TJ_TICK_GAMECLOCK=<guestEA>: DIAGNOSTIC ONLY.
             *
             * The main loop waits for [[TOC+0x1860]+0x18] to pass a stored
             * timestamp + 3, and that field reads 0 forever -- nothing writes
             * it: not guest code, not an HLE, not SPU DMA (all three checked).
             * Ticking it by hand says whether the wait is really what holds the
             * boot, and in what units, without guessing.
             *
             * This is not a fix. Whatever should own that clock still has to be
             * found; poking it from outside just makes the guest believe time
             * passed. */
            { static long ea = -1;
              if (ea < 0) { const char* e = getenv("TJ_TICK_GAMECLOCK");
                            ea = e ? strtol(e, nullptr, 0) : 0; }
              if (ea > 0) { static uint64_t t = 0; vm_write64((uint32_t)ea, ++t); } }

            cellGcmTickVBlank();
            cellGcmTickFlip();
            /* Host-side tick publisher. The JP disc's screen pump (func_001F2D88)
             * publishes a request into a tick ring and then waits until the
             * ring's write index (0x00C0475C+8) passes the request's ticket; the
             * producer of that index is the game's tick source, which on
             * hardware is driven by the GCM vblank. Nothing wrote it here, so
             * every pump parked on the GCM ref register. Advance one ring entry
             * per ~16 ms tick, which is the hardware cadence. */
            {
                static uint32_t tick_ea = 0;
                static int init = 0;
                if (!init) {
                    const char* e = getenv("TJ_TICKRING");
                    tick_ea = e ? (uint32_t)strtoul(e, NULL, 0)
                                : 0x02010008u;   /* ticket consumer's processed-ticket counter */
                    init = 1;
                }
                if (tick_ea) {
                    /* The pump's tickets DESCEND - request(0), then
                     * request(0xFFFFFFFF = -1) - and func_001F734C spins while
                     * (int)ticket < (int)[consumer+8].  So the consumer's
                     * processed-ticket counter counts DOWN, one per ticket. */
                    /* func_001F734C spins while (int)ticket < (int)[r30+8], where
                     * [r30+8] holds the sequence the consumer copied out of the
                     * ring's write index.  The pump's tickets are 0 then -1, so
                     * the published sequence has to come DOWN to them: 0 clears
                     * both. */
                    /* Two consumers share one register. The fence spin
                     * (func_001F8C4C = cellGcmFinish) waits ref == the value the
                     * title's SET_REFERENCE wrote -- the boot ring emits 0 at
                     * +0xF4 and 0xFFFFFFFF at +0xEC. The pump's ticket spins
                     * want 0 then -1 (signed). Cycling the values per vblank
                     * lets each waiter see its own value, one per tick, which
                     * is what hardware does: the register holds each fence for
                     * about a frame. TJ_TICKVALUES overrides the cycle. */
                    static const uint32_t k_cycle[] = { 0u, 0xFFFFFFFFu };
                    static uint32_t k_cycle_i = 0;
                    const char* tv = getenv("TJ_TICKVALUES");
                    if (tv && tv[0]) {
                        /* comma separated hex cycle, e.g. "0,FFFFFFFF" */
                        uint32_t vals[8]; int n = 0;
                        const char* q = tv;
                        while (n < 8 && *q) { vals[n++] = (uint32_t)strtoul(q, (char**)&q, 16); if (*q == ',') q++; }
                        if (n) vm_write32(tick_ea, vals[k_cycle_i++ % n]);
                    } else {
                        vm_write32(tick_ea, k_cycle[k_cycle_i++ % (sizeof k_cycle / sizeof k_cycle[0])]);
                    }
                }
            }
            if (rsx_ok && (cellGcm_take_flip_pending() || tj_present_always()))
                rsx_backend_present();
            if (rsx_ok)
                cellGcm_rsx_process_fifo();
            next_tick += 16;          /* ~60 Hz */
            fired++;
        }
        if (fired >= 240)
            next_tick = now;          /* fell far behind -- resync */

        /* Also drain at the outer cadence: titles fence every render pass on
         * an RSX label the drain writes, and waiting a full 16 ms per fence
         * paces the guest to single-digit fps. */
        tj_dump_threads();

        if (rsx_ok) {
            if (cellGcm_take_flip_pending() || tj_present_always())
                rsx_backend_present();
            cellGcm_rsx_process_fifo();
            if (rsx_backend_pump() != 0) {
                rsx_ok = 0;           /* window closed */
                s_window_alive = 0;
            }
        }
    }
}

extern "C" void tj_start_present_thread(void){
    if (getenv("TJ_NO_PRESENT")) {
        printf("[TJ] TJ_NO_PRESENT: no present thread (headless)\n");
        return;
    }
    CreateThread(NULL, 4u * 1024 * 1024, tj_present_thread, NULL, 0, NULL);
    printf("[TJ] present thread started (60 Hz vblank/flip ticker)\n");
}
