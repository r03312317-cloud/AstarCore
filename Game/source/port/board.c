// [ARCH] 板级访问边界使用固定 SoC 寄存器映射。
// [ARCH] 设备读写两侧保留 fence，volatile 本身不保证乱序设备顺序。
// [ARCH] 周期计数按高、低、高读取，回绕时重试。
// [ARCH] 100 MHz mcycle 才是实板性能时基，不能用 NES 时间预算替代。
// [ARCH] pending_address 表示已排队、尚未确认的显示目标。
// [ARCH] 提交立即返回，让下一帧计算与换帧等待重叠。
// [ARCH] PUBLISHED 改变且 ACTIVE_FB 匹配后才能重用旧缓冲。
// [ARCH] 即使提交后报错，也保留 pending 所有权。
// [ARCH] 120 ms 等待使用无符号时间差，允许毫秒计数回绕。
// [ARCH] completed 只累计已确认发布，不等于提交请求次数。
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
static uint32_t pending_address,pending_published,pending_start;
static unsigned completed;
// [ARCH] 先读高位再读低位，最后重读高位核对是否回绕。
// [ARCH] 这样不需要对普通计数器读执行设备缓存维护。
// [ARCH] 机器 CSR 0xb00/0xb80 已由实际核与回绕测试覆盖。
uint64_t soc_cycles(void) {
    uint32_t hi,lo,again;
    /* RV32 implements machine counter CSRs b00/b80. Counter reads do not
     * access a device and need no I/O fence/cache maintenance. Retry if the
     * low word rolls over between the two high-word reads. */
    do {
        __asm__ volatile("csrr %0,0xb80\ncsrr %1,0xb00\ncsrr %2,0xb80"
                         :"=&r"(hi),"=&r"(lo),"=&r"(again)::"memory");
    }while(hi!=again);
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
// [ARCH] 显式设置两块固定缓冲地址和硬件去抖。
// [ARCH] 初始软件 front 从硬件活动地址推导。
// [ARCH] 不假定上电后的 DDR 像素全为零。
void soc_video_init(void) {
    pending_address=0;completed=0;
    io_write32(MMIO_GAME_INPUT+GIN_DEBOUNCE_MS,6);
    io_write32(MMIO_GAME_VIDEO+GVID_FB0,SOC_VIDEO_FB0);io_write32(MMIO_GAME_VIDEO+GVID_FB1,SOC_VIDEO_FB1);
    io_write32(MMIO_GAME_VIDEO+GVID_CTRL,0);
    front=(io_read32(MMIO_GAME_VIDEO+GVID_ACTIVE_FB)==SOC_VIDEO_FB1);
}
// [ARCH] 没有排队目标时无需等待。
// [ARCH] 有目标时必须确认发布计数和活动地址两项条件。
// [ARCH] 错误或超时返回失败，不把不确定的目标重新交给绘图。
static int finish_video(void) {
    if(!pending_address)return 0;
    while(io_read32(MMIO_GAME_VIDEO+GVID_PUBLISHED)==pending_published || io_read32(MMIO_GAME_VIDEO+GVID_ACTIVE_FB)!=pending_address)
        if((uint32_t)(soc_millis()-pending_start)>120)return -1;
    if(io_read32(MMIO_GAME_VIDEO+GVID_ERROR)||io_read32(MMIO_GAME_VIDEO+GVID_FAULT))return -1;
    pending_address=0;front^=1;completed++;return 0;
}
// [ARCH] 先解决前一次发布的所有权，再交出可写目标。
// [ARCH] 失败时返回空指针，调用者不得继续绘图。
// [ARCH] 这样把下一帧计算与硬件等待重叠，但不并发改写前台。
uint16_t *soc_video_back(void) {
    if(finish_video())return NULL;
    return (uint16_t *)(uintptr_t)(front?SOC_VIDEO_FB0:SOC_VIDEO_FB1);
}
// [ARCH] 保存本次目标与发布前计数，再发送提交。
// [ARCH] 提交后立即保留 pending 身份，即使错误状态同时出现。
// [ARCH] 真正翻转 front 在后续确认完成时进行。
int soc_video_publish(void) {
    if(pending_address)return -1;
    uint32_t addr=front?SOC_VIDEO_FB0:SOC_VIDEO_FB1;
    pending_published=io_read32(MMIO_GAME_VIDEO+GVID_PUBLISHED);pending_start=soc_millis();
    __asm__ volatile("fence rw,rw":::"memory");
    io_write32(MMIO_GAME_VIDEO+GVID_COMMIT,addr);
    /* Even an error status can accompany an accepted/queued request. Keep
     * ownership pending until finish_video proves that reuse is safe. */
    pending_address=addr;
    if(io_read32(MMIO_GAME_VIDEO+GVID_ERROR))return -1;
    return 0;
}
unsigned soc_video_completed(void){return completed;}
