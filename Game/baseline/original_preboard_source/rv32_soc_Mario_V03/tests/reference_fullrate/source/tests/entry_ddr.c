/* Simulation boot stub: DDR is preloaded by the testbench. It bypasses UART
 * transfer only, and jumps into the unmodified deployable mario.bin entry. */
#include "soc_port.h"
#include "game_regs.h"
int main(void) {
    while (!(*(volatile uint32_t *)(MMIO_GAME_VIDEO+GVID_STATUS)&8u)) {}
    for(unsigned i=0;i<24;i++)((volatile uint8_t *)(uintptr_t)SOC_ASSET_BASE)[i]=0;
    soc_uart_puts("MARIO_SIM_PRELOADED_DDR_JUMP\n");
    soc_fence_i();
    ((void (*)(void))(uintptr_t)SOC_APP_BASE)();
    for(;;) {}
}
