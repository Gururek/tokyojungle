#ifndef TJ_SYSUTIL_H
#define TJ_SYSUTIL_H

#include <cstdint>

struct ppu_context;

#define TJ_SYSUTIL_MAX_SLOTS 16

/* Register the title's sysutil callback (cellSysutilRegisterCallback). */
void tj_sysutil_register(int slot, uint32_t func_opd, uint32_t userdata);

/* Queue an event for a slot's callback. status/param are the 64-bit values
 * the guest callback receives in r3/r4 (r5 = userdata). */
void tj_sysutil_post(int slot, uint64_t status, uint64_t param);

/* cellSysutilCheckCallback: dispatch one queued event, returning 1 when a
 * callback ran (the title keeps servicing), 0 when the queue was empty. */
int tj_sysutil_check(ppu_context* ctx);

/* Queue the boot events the title screen waits for on every registered slot
 * (observed on the NA disc as "callback slot 2: boot event 0/6"). */
void tj_sysutil_boot_events(void);

#endif  // TJ_SYSUTIL_H
