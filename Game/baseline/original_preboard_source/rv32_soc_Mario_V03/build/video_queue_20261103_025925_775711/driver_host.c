#include <stdint.h>
uint32_t test_io_read(uint32_t);
void test_io_write(uint32_t,uint32_t);
uint64_t test_cycles(void);
void test_barrier(void);
#include "soc_port.h"
#include "game_regs.h"
/* Serialize device accesses across this out-of-order core. Volatile alone
 * only controls the compiler; it is not an architectural I/O barrier. */
static uint32_t io_read32(uint32_t address){return test_io_read(address);}
static void io_write32(uint32_t address,uint32_t value){test_io_write(address,value);}
static unsigned front;
static uint32_t pending_address,pending_published,pending_start;
static unsigned completed;
uint64_t soc_cycles(void){return test_cycles();}
uint32_t soc_millis(void) {return (uint32_t)(soc_cycles()/100000u);}
void soc_uart_putc(char c) {while(!(io_read32(MMIO_UART_STATUS)&2u)){} io_write32(MMIO_UART_TX,(uint8_t)c);}
void soc_uart_puts(const char *s) {while(*s)soc_uart_putc(*s++);}
int soc_uart_getc(uint32_t timeout_ms) {
    uint32_t start=soc_millis();
    while(!(io_read32(MMIO_UART_STATUS)&1u))if((uint32_t)(soc_millis()-start)>=timeout_ms)return -1;
    return (int)(io_read32(MMIO_UART_RX)&255u);
}
uint8_t soc_buttons(void) {return (uint8_t)io_read32(MMIO_GAME_INPUT+GIN_LEVEL);}
void soc_fence_i(void) {test_barrier();}
void soc_video_init(void) {
    pending_address=0;completed=0;
    io_write32(MMIO_GAME_INPUT+GIN_DEBOUNCE_MS,6);
    io_write32(MMIO_GAME_VIDEO+GVID_FB0,SOC_VIDEO_FB0);io_write32(MMIO_GAME_VIDEO+GVID_FB1,SOC_VIDEO_FB1);
    io_write32(MMIO_GAME_VIDEO+GVID_CTRL,0);
    front=(io_read32(MMIO_GAME_VIDEO+GVID_ACTIVE_FB)==SOC_VIDEO_FB1);
}
static int finish_video(void) {
    if(!pending_address)return 0;
    while(io_read32(MMIO_GAME_VIDEO+GVID_PUBLISHED)==pending_published || io_read32(MMIO_GAME_VIDEO+GVID_ACTIVE_FB)!=pending_address)
        if((uint32_t)(soc_millis()-pending_start)>120)return -1;
    if(io_read32(MMIO_GAME_VIDEO+GVID_ERROR)||io_read32(MMIO_GAME_VIDEO+GVID_FAULT))return -1;
    pending_address=0;front^=1;completed++;return 0;
}
uint16_t *soc_video_back(void) {
    if(finish_video())return NULL;
    return (uint16_t *)(uintptr_t)(front?SOC_VIDEO_FB0:SOC_VIDEO_FB1);
}
int soc_video_publish(void) {
    if(pending_address)return -1;
    uint32_t addr=front?SOC_VIDEO_FB0:SOC_VIDEO_FB1;
    pending_published=io_read32(MMIO_GAME_VIDEO+GVID_PUBLISHED);pending_start=soc_millis();
    test_barrier();
    io_write32(MMIO_GAME_VIDEO+GVID_COMMIT,addr);
    /* Even an error status can accompany an accepted/queued request. Keep
     * ownership pending until finish_video proves that reuse is safe. */
    pending_address=addr;
    if(io_read32(MMIO_GAME_VIDEO+GVID_ERROR))return -1;
    return 0;
}
unsigned soc_video_completed(void){return completed;}
