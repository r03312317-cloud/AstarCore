#ifndef SOC_CYCLE_TIMER64_H
#define SOC_CYCLE_TIMER64_H
#include <stdint.h>
static inline uint64_t soc_ticks64(void) {
#ifdef BOARD_HOST_UNIT
    static uint64_t host_ticks;
    return ++host_ticks;
#else
    uint32_t saved,low,high;
    __asm__ volatile("csrrc %0,mstatus,%1" : "=r"(saved) : "r"(8u) : "memory");
    low=R32(0x60000000u);high=R32(0x60000004u);
    if(saved&8u)__asm__ volatile("csrs mstatus,%0" :: "r"(8u) : "memory");
    return ((uint64_t)high<<32)|low;
#endif
}
#endif
