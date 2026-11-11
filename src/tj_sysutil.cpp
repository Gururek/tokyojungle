// Sysutil event pump, the piece the JP disc's screen machine waits on.
//
// The title registers a sysutil callback (cellSysutilRegisterCallback(slot,
// func, userdata)) and its pump (func_001F2D88) services it every step: it
// calls cellSysutilCheckCallback() and, as long as a callback ran, keeps
// servicing the screen handler. Our first stub returned 0 -- "no callback
// ran" -- which left the pump parked on the very first screen.
//
// This is a queue + dispatcher. post() enqueues from the host side; check()
// drains one event per call into the registered guest callback
//   void cb(uint64_t status, uint64_t param, void* userdata)  -> r3/r4/r5
// through the runtime's OPD dispatch hook (src/dispatch_glue.cpp installs it).
//
// Observed on the NA disc (logs/las/README.md): "callback slot 2: boot event
// 0/6" -- two boot events on slot 2, CELL_SYSUTIL_SYSTEM_EVENT_SYSTEM (0) and
// CELL_SYSUTIL_SYSTEM_EVENT_AVCONF_CHANGE (6).

#include "tj_sysutil.h"

#include <ps3emu/guest_call.h>   /* ps3_invoke_guest: guest OPD dispatch */

#include "ppu_context.h"          /* ppu_context */

/* ps3recomp's queue lives in libs/system/cellSysutil.c; its header is not on
 * this target's include path, so the prototype is spelled out. */
extern "C" void cellSysutilQueueEvent(int slot, uint32_t status, uint32_t param);

#include <cstdio>
#include <cstdlib>

namespace {

struct Event {
    uint64_t status;
    uint64_t param;
};

struct Slot {
    uint32_t func_opd = 0;   // guest OPD of the registered callback
    uint32_t userdata = 0;
    bool registered = false;
    Event queue[32] = {};
    int head = 0;
    int tail = 0;
};

Slot g_slots_storage[TJ_SYSUTIL_MAX_SLOTS];

}  // namespace

static Slot* const g_slots = g_slots_storage;
static int g_verbose = -1;

static void verbose_init(void) {
    if (g_verbose < 0) {
        const char* v = getenv("TJ_SYSUTIL");
        g_verbose = v ? atoi(v) : 1;
    }
}

void tj_sysutil_register(int slot, uint32_t func_opd, uint32_t userdata) {
    verbose_init();
    if (slot < 0 || slot >= TJ_SYSUTIL_MAX_SLOTS)
        return;
    Slot& s = g_slots[slot];
    s.func_opd = func_opd;
    s.userdata = userdata;
    s.registered = func_opd != 0;
    s.head = s.tail = 0;
    if (g_verbose)
        printf("[sysutil] register slot=%d func=0x%08X userdata=0x%08X\n",
               slot, func_opd, userdata);
}

void tj_sysutil_post(int slot, uint64_t status, uint64_t param) {
    if (slot < 0 || slot >= TJ_SYSUTIL_MAX_SLOTS)
        return;
    Slot& s = g_slots[slot];
    int next = (s.tail + 1) % 32;
    if (next == s.head)
        return;  // full: drop, the guest polls
    s.queue[s.tail] = Event{status, param};
    s.tail = next;
}

int tj_sysutil_check(ppu_context* ctx) {
    verbose_init();
    for (int slot = 0; slot < TJ_SYSUTIL_MAX_SLOTS; ++slot) {
        Slot& s = g_slots[slot];
        if (!s.registered || s.head == s.tail)
            continue;
        Event e = s.queue[s.head];
        s.head = (s.head + 1) % 32;
        if (g_verbose)
            printf("[sysutil] -> slot %d cb(status=0x%llX, param=0x%llX, ud=0x%08X)\n",
                   slot, (unsigned long long)e.status,
                   (unsigned long long)e.param, s.userdata);
        if (ctx) {
            ctx->gpr[3] = e.status;
            ctx->gpr[4] = e.param;
            ctx->gpr[5] = s.userdata;
        }
        ps3_invoke_guest(s.func_opd, e.status, e.param, (uint64_t)s.userdata,
                         0, 0, 0, 0, 0);
        return 1;  // "a callback ran" -- the title keeps servicing
    }
    return 0;
}

void tj_sysutil_boot_events(void) {
    verbose_init();
    /* The JP disc binds cellSysutilRegisterCallback to ps3recomp's own
     * implementation (NID 0x9D98AFA0), so the queue that matters is the one
     * inside libs/system/cellSysutil.c. Post the boot events there for every
     * slot; unregistered slots are skipped when the queue is drained. */
    for (int slot = 0; slot < TJ_SYSUTIL_MAX_SLOTS; ++slot) {
        cellSysutilQueueEvent(slot, 0, 0);   // CELL_SYSUTIL_SYSTEM_EVENT_SYSTEM
        cellSysutilQueueEvent(slot, 6, 0);   // CELL_SYSUTIL_SYSTEM_EVENT_AVCONF_CHANGE
        tj_sysutil_post(slot, 0, 0);         // app-side queue, for the app stub
        tj_sysutil_post(slot, 6, 0);
        if (g_verbose)
            printf("[sysutil] boot events queued for slot %d\n", slot);
    }
}
