/*
 * fiber_compat.cpp — cellFiber PPU-fiber shims for the title's import table.
 *
 * The disc imports the SPURS-era cellFiber PPU API (cellFiberPpuInitialize,
 * ...YieldFiber, ...Wakeup, ...), the names src/gen/ppu_hle_nids.cpp registers
 * by NID. ps3recomp's current cellFiber HLE exposes the newer SDK shape
 * (a scheduler object + RunFibers/SendSignal/Yield/Exit/Self/JoinFiber), so
 * the old names have no definition and the link fails. Each shim below is
 * registered under the NID the disc imports and forwards to the current
 * implementation, picking the scheduler-implicit behaviour the old API had
 * (one scheduler, created by cellFiberPpuInitialize).
 *
 * Calling convention: the runtime's generic HLE dispatch calls a registered
 * handler as `fn(ctx->gpr[3..10])` and stores the result in r3 (see
 * ps3recomp/runtime/ppu/ppu_hle.cpp `hle_generic`), so every shim takes eight
 * uint64_t guest arguments. Fiber handles are guest EAs carried in a pointer,
 * which is what cellFiber.c itself uses (find_fiber(ea)).
 */

#include "fiber_compat.h"

#include "cellFiber.h"          /* ps3recomp libs/spurs: current API */

extern "C" {

/* s32 cellFiberPpuInitialize(void) — the old API had one implicit scheduler. */
uint64_t cellFiberPpuInitialize(uint64_t, uint64_t, uint64_t, uint64_t,
                                uint64_t, uint64_t, uint64_t, uint64_t)
{
    return (uint64_t)(int64_t)(int32_t)_cellFiberPpuInitialize();
}

/* s32 cellFiberPpuAttributeInitialize(CellFiberPpuAttribute*, u32 sdkVersion) */
uint64_t cellFiberPpuAttributeInitialize(uint64_t attr, uint64_t sdkVersion,
                                         uint64_t, uint64_t, uint64_t, uint64_t,
                                         uint64_t, uint64_t)
{
    return (uint64_t)(int64_t)(int32_t)_cellFiberPpuAttributeInitialize(
        (CellFiberPpuAttribute*)(uintptr_t)attr, (u32)sdkVersion);
}

/* s32 cellFiberPpuFinalize(void) — tears the implicit scheduler down. */
uint64_t cellFiberPpuFinalize(uint64_t, uint64_t, uint64_t, uint64_t,
                              uint64_t, uint64_t, uint64_t, uint64_t)
{
    return (uint64_t)(int64_t)(int32_t)cellFiberPpuFinalizeScheduler(nullptr);
}

/* s32 cellFiberPpuDeleteFiber(CellFiberPpu*). The current API frees fibers with
 * their scheduler, so there is nothing per-fiber to release. */
uint64_t cellFiberPpuDeleteFiber(uint64_t, uint64_t, uint64_t, uint64_t,
                                 uint64_t, uint64_t, uint64_t, uint64_t)
{
    return (uint64_t)(int64_t)(int32_t)CELL_OK;
}

/* s32 cellFiberPpuSwitchFiber(CellFiberPpu*) — make the target runnable; the
 * scheduler reaches it at the next yield point. */
uint64_t cellFiberPpuSwitchFiber(uint64_t fiber, uint64_t, uint64_t, uint64_t,
                                 uint64_t, uint64_t, uint64_t, uint64_t)
{
    return (uint64_t)(int64_t)(int32_t)cellFiberPpuSendSignal(
        (CellFiberPpu*)(uintptr_t)fiber, nullptr);
}

/* s32 cellFiberPpuYieldFiber(void) */
uint64_t cellFiberPpuYieldFiber(uint64_t, uint64_t, uint64_t, uint64_t,
                                uint64_t, uint64_t, uint64_t, uint64_t)
{
    return (uint64_t)(int64_t)(int32_t)cellFiberPpuYield();
}

/* s32 cellFiberPpuExitFiber(s32 status) */
uint64_t cellFiberPpuExitFiber(uint64_t status, uint64_t, uint64_t, uint64_t,
                               uint64_t, uint64_t, uint64_t, uint64_t)
{
    return (uint64_t)(int64_t)(int32_t)cellFiberPpuExit((s32)status);
}

/* CellFiberPpu* cellFiberPpuGetCurrentFiber(void) — the running fiber's EA. */
uint64_t cellFiberPpuGetCurrentFiber(uint64_t, uint64_t, uint64_t, uint64_t,
                                     uint64_t, uint64_t, uint64_t, uint64_t)
{
    return (uint64_t)(uintptr_t)cellFiberPpuSelf();
}

/* s32 cellFiberPpuGetFiberState(CellFiberPpu*, s32* status). The nearest
 * current-API call: it waits for the fiber to end and writes its status. */
uint64_t cellFiberPpuGetFiberState(uint64_t fiber, uint64_t status, uint64_t,
                                   uint64_t, uint64_t, uint64_t, uint64_t,
                                   uint64_t)
{
    return (uint64_t)(int64_t)(int32_t)cellFiberPpuJoinFiber(
        (CellFiberPpu*)(uintptr_t)fiber, (s32*)(uintptr_t)status);
}

/* s32 cellFiberPpuSleep(u64* abstime). No current-API equivalent (the scheduler
 * sleeps with RunFibers); returning immediately is what a fired timer looks
 * like, and it is what got the title past boot on the runtime this port was
 * built against. */
uint64_t cellFiberPpuSleep(uint64_t, uint64_t, uint64_t, uint64_t,
                           uint64_t, uint64_t, uint64_t, uint64_t)
{
    return (uint64_t)(int64_t)(int32_t)CELL_OK;
}

/* s32 cellFiberPpuWakeup(CellFiberPpu*, u32* numWorker) */
uint64_t cellFiberPpuWakeup(uint64_t fiber, uint64_t numWorker, uint64_t,
                            uint64_t, uint64_t, uint64_t, uint64_t, uint64_t)
{
    return (uint64_t)(int64_t)(int32_t)cellFiberPpuSendSignal(
        (CellFiberPpu*)(uintptr_t)fiber, (u32*)(uintptr_t)numWorker);
}

} /* extern "C" */
