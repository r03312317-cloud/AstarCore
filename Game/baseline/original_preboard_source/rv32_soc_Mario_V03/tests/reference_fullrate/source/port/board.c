#include "soc_port.h"
#include "game_regs.h"
/* Serialize device accesses across this out-of-order core. Volatile alone
 * only controls the compiler; it is not an architectural I/O barrier. */
static uint32_t io_read32(uint32_t address) {
    __asm__ volatile("fence iorw,iorw":::"memory");
    uint32_t value=*(volatile uint32_t *)(uintptr_t)address;
    __asm__ volatile("fence iorw,iorw":::"memory");
    return value;
}
static void io_write32(uint32_t address,uint32_t value) {
    __asm__ volatile("fence iorw,iorw":::"memory");
    *(volatile uint32_t *)(uintptr_t)address=value;
    __asm__ volatile("fence iorw,iorw":::"memory");
}
static unsigned front;
uint64_t soc_cycles(void) {
    uint32_t hi,lo,again;
    do {hi=io_read32(MMIO_TIMER_MS_HI);lo=io_read32(MMIO_TIMER_MS);again=io_read32(MMIO_TIMER_MS_HI);}while(hi!=again);
    return ((uint64_t)hi<<32)|lo;
}
uint32_t soc_millis(void) {return (uint32_t)(soc_cycles()/100000u);}
void soc_uart_putc(char c) {while(!(io_read32(MMIO_UART_STATUS)&2u)){} io_write32(MMIO_UART_TX,(uint8_t)c);}
void soc_uart_puts(const char *s) {while(*s)soc_uart_putc(*s++);}
int soc_uart_getc(uint32_t timeout_ms) {
    uint32_t start=soc_millis();
    while(!(io_read32(MMIO_UART_STATUS)&1u))if((uint32_t)(soc_millis()-start)>=timeout_ms)return -1;
    return (int)(io_read32(MMIO_UART_RX)&255u);
}
uint8_t soc_buttons(void) {return (uint8_t)io_read32(MMIO_GAME_INPUT+GIN_LEVEL);}
void soc_fence_i(void) {__asm__ volatile("fence rw,rw\n.word 0x0000100f":::"memory");}
void soc_video_init(void) {
    io_write32(MMIO_GAME_INPUT+GIN_DEBOUNCE_MS,6);
    io_write32(MMIO_GAME_VIDEO+GVID_FB0,FB0_ADDR);io_write32(MMIO_GAME_VIDEO+GVID_FB1,FB1_ADDR);
    io_write32(MMIO_GAME_VIDEO+GVID_CTRL,0);
    front=(io_read32(MMIO_GAME_VIDEO+GVID_ACTIVE_FB)==FB1_ADDR);
}
uint16_t *soc_video_back(void) {return (uint16_t *)(uintptr_t)(front?FB0_ADDR:FB1_ADDR);}
int soc_video_publish(void) {
    uint32_t addr=(uint32_t)(uintptr_t)soc_video_back();
    uint32_t published=io_read32(MMIO_GAME_VIDEO+GVID_PUBLISHED),start=soc_millis();
    __asm__ volatile("fence rw,rw":::"memory");
    io_write32(MMIO_GAME_VIDEO+GVID_COMMIT,addr);
    while(io_read32(MMIO_GAME_VIDEO+GVID_PUBLISHED)==published || io_read32(MMIO_GAME_VIDEO+GVID_ACTIVE_FB)!=addr)
        if((uint32_t)(soc_millis()-start)>120)return -1;
    if(io_read32(MMIO_GAME_VIDEO+GVID_ERROR))return -1;
    front^=1;return 0;
}
