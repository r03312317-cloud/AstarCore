#include "soc_port.h"
#include "game_regs.h"
#define REG(a) (*(volatile uint32_t *)(uintptr_t)(a))
static uint8_t block[1024];
static int read_exact(uint8_t *p,unsigned n) {while(n--){int c=soc_uart_getc(2000);if(c<0)return -1;*p++=(uint8_t)c;}return 0;}
static uint32_t u32(const uint8_t*p){return (uint32_t)p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24;}
static int allowed(uint32_t a,uint32_t n) {
    return n>0&&n<=sizeof block&&((a>=SOC_APP_BASE&&a<SOC_APP_LIMIT&&n<=SOC_APP_LIMIT-a)||(a>=SOC_ASSET_BASE&&a<SOC_ASSET_LIMIT&&n<=SOC_ASSET_LIMIT-a));
}
int main(void) {
    uint8_t header[16];unsigned sync=0;int app_loaded=0;static const char magic[]="APAL";
    uint32_t start=soc_millis();
    while(!(REG(MMIO_GAME_VIDEO+GVID_STATUS)&8u))if((uint32_t)(soc_millis()-start)>10000){soc_uart_puts("APAL_DDR_TIMEOUT\n");for(;;){}}
    /* Clear the resource header so a no-data run cannot mount stale DDR. */
    for(unsigned i=0;i<24;i++)((volatile uint8_t*)(uintptr_t)SOC_ASSET_BASE)[i]=0;
    soc_uart_puts("APAL_READY V01 100MHz\n");
    for(;;) {
        int c=soc_uart_getc(1000);if(c<0)continue;
        if(c!=magic[sync]){sync=c=='A';continue;}if(++sync<4)continue;sync=0;
        if(read_exact(header,sizeof header)){soc_uart_putc('N');continue;}
        uint32_t cmd=u32(header),addr=u32(header+4),n=u32(header+8),crc=u32(header+12);
        if(cmd==0&&addr==0&&n==0&&crc==0)soc_uart_puts("APAL_READY V01 100MHz\n");
        else if(cmd==1&&allowed(addr,n)) {
            if(read_exact(block,n)||soc_crc32(block,n)!=crc){soc_uart_putc('N');continue;}
            volatile uint8_t *dst=(volatile uint8_t*)(uintptr_t)addr;for(unsigned i=0;i<n;i++)dst[i]=block[i];
            if(soc_crc32((const void*)(uintptr_t)addr,n)!=crc){soc_uart_putc('N');continue;}
            if(addr==SOC_APP_BASE)app_loaded=1;
            soc_uart_putc('K');
        } else if(cmd==2&&addr==SOC_APP_BASE&&n>0&&n<=SOC_APP_LIMIT-SOC_APP_BASE&&app_loaded&&soc_crc32((const void*)(uintptr_t)addr,n)==crc) {
            soc_uart_puts("APAL_GO\n");soc_fence_i();((void(*)(void))(uintptr_t)addr)();for(;;){}
        } else soc_uart_putc('N');
    }
}
