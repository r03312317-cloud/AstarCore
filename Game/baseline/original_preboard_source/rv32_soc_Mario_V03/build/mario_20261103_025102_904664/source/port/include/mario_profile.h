#ifndef MARIO_PROFILE_H
#define MARIO_PROFILE_H
#include <stdint.h>
struct mario_costs {uint32_t cpu,bg,sprite,scale,publish,input,clear;};
extern struct mario_costs mario_costs;
#ifdef __riscv
/* Compact loops run from cached DDR without device accesses inside them. */
#define MARIO_DDR_LOOP __attribute__((section(".ddr_text"),noinline,noclone))
static inline uint32_t mario_profile_ticks(void) {
    uint32_t value;__asm__ volatile("csrr %0,mcycle":"=r"(value)::"memory");return value;
}
#define PROF_BEGIN(name) uint32_t name=mario_profile_ticks()
#define PROF_END(field,name) (mario_costs.field+=(uint32_t)(mario_profile_ticks()-(name)))
#else
#define MARIO_DDR_LOOP
#define PROF_BEGIN(name) ((void)0)
#define PROF_END(field,name) ((void)0)
#endif
#endif
