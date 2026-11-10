/*
 * fiber_compat.h — declarations for the cellFiber PPU-fiber shims.
 *
 * The prototypes match the runtime's generic HLE handler ABI (see
 * ps3recomp/runtime/ppu/ppu_hle.cpp: `hle_generic` is called with the guest
 * argument registers r3..r10 and its return value lands in r3). Declaring the
 * shims this way — and including this header from the generated registration
 * unit — keeps the `(void*)cellFiberPpuX` cast unambiguous in C++, which the
 * old `void cellFiberPpuX(void);` declarations in gen'd code rely on.
 *
 * See fiber_compat.cpp for why each shim maps where it does.
 */

#ifndef TJ_FIBER_COMPAT_H
#define TJ_FIBER_COMPAT_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

uint64_t cellFiberPpuInitialize(uint64_t, uint64_t, uint64_t, uint64_t,
                                uint64_t, uint64_t, uint64_t, uint64_t);
uint64_t cellFiberPpuFinalize(uint64_t, uint64_t, uint64_t, uint64_t,
                              uint64_t, uint64_t, uint64_t, uint64_t);
uint64_t cellFiberPpuDeleteFiber(uint64_t, uint64_t, uint64_t, uint64_t,
                                 uint64_t, uint64_t, uint64_t, uint64_t);
uint64_t cellFiberPpuSwitchFiber(uint64_t, uint64_t, uint64_t, uint64_t,
                                 uint64_t, uint64_t, uint64_t, uint64_t);
uint64_t cellFiberPpuYieldFiber(uint64_t, uint64_t, uint64_t, uint64_t,
                                uint64_t, uint64_t, uint64_t, uint64_t);
uint64_t cellFiberPpuExitFiber(uint64_t, uint64_t, uint64_t, uint64_t,
                               uint64_t, uint64_t, uint64_t, uint64_t);
uint64_t cellFiberPpuGetCurrentFiber(uint64_t, uint64_t, uint64_t, uint64_t,
                                     uint64_t, uint64_t, uint64_t, uint64_t);
uint64_t cellFiberPpuGetFiberState(uint64_t, uint64_t, uint64_t, uint64_t,
                                   uint64_t, uint64_t, uint64_t, uint64_t);
uint64_t cellFiberPpuAttributeInitialize(uint64_t, uint64_t, uint64_t, uint64_t,
                                         uint64_t, uint64_t, uint64_t, uint64_t);
uint64_t cellFiberPpuSleep(uint64_t, uint64_t, uint64_t, uint64_t,
                           uint64_t, uint64_t, uint64_t, uint64_t);
uint64_t cellFiberPpuWakeup(uint64_t, uint64_t, uint64_t, uint64_t,
                            uint64_t, uint64_t, uint64_t, uint64_t);

#ifdef __cplusplus
}
#endif

#endif /* TJ_FIBER_COMPAT_H */
