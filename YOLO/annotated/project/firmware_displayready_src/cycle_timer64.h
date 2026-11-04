// 架构导读：cycle_timer64。
// 读取板上 64 位周期计时，避免跨高低字翻转得到撕裂时间戳。
#ifndef SOC_CYCLE_TIMER64_H
#define SOC_CYCLE_TIMER64_H
#include <stdint.h>
// 服务函数 soc_ticks64。
// 接口参数：void；返回值及副作用由下列函数体定义。
// 参数入口：无位置参数；类型、指针限定及返回约定沿用下列声明。
static inline uint64_t soc_ticks64(void) {
#ifdef BOARD_HOST_UNIT
    static uint64_t host_ticks;
    return ++host_ticks;
#else
    uint32_t saved,low,high;
    // 服务函数 volatile。
    __asm__ volatile("csrrc %0,mstatus,%1" : "=r"(saved) : "r"(8u) : "memory");
    low=R32(0x60000000u);high=R32(0x60000004u);
    if(saved&8u)__asm__ volatile("csrs mstatus,%0" :: "r"(8u) : "memory");
    return ((uint64_t)high<<32)|low;
#endif
}
#endif
