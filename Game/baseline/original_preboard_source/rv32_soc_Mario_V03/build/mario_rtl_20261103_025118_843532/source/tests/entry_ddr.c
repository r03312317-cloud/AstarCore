/* Simulation boot stub: DDR is preloaded by the testbench. It bypasses UART
 * transfer only, and jumps into the unmodified deployable mario.bin entry. */
#include "soc_port.h"
#include "game_regs.h"
static void check_timer64(void) {
    /* Test the actual RV32 driver across a 32-bit carry without simulating
     * 43 seconds. Counter writes belong only to this simulation boot stub. */
    __asm__ volatile("csrw 0xb80,%0\ncsrw 0xb00,%1"
                     ::"r"(0x12u),"r"(0xfffff000u):"memory");
    uint64_t first=soc_cycles(),previous=first,current=first;
    int valid=(first>>32)==0x12u;
    unsigned attempts=0;
    while(valid && (current>>32)==0x12u && attempts++<4096) {
        current=soc_cycles();
        if(current<previous || current-first>1000000u)valid=0;
        previous=current;
    }
    if(!valid || (current>>32)!=0x13u) {
        soc_uart_puts("MARIO_RTL_TIMER64_FAIL\n");
        for(;;){}
    }
    __asm__ volatile("csrw 0xb80,zero\ncsrw 0xb00,zero":::"memory");
    soc_uart_puts("MARIO_RTL_TIMER64_ROLLOVER_PASS\n");
}
int main(void) {
    while (!(*(volatile uint32_t *)(MMIO_GAME_VIDEO+GVID_STATUS)&8u)) {}
    check_timer64();
    for(unsigned i=0;i<24;i++)((volatile uint8_t *)(uintptr_t)SOC_ASSET_BASE)[i]=0;
    soc_uart_puts("MARIO_SIM_PRELOADED_DDR_JUMP\n");
    soc_fence_i();
    ((void (*)(void))(uintptr_t)SOC_APP_BASE)();
    for(;;) {}
}
