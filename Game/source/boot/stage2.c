// [ARCH] 二级接收器在预留的 0x10002000 指令 SRAM 区域运行。
// [ARCH] APAL 协议保持兼容，逐字节校验和回读避开初级接收器已知路径问题。
// [ARCH] 映像从 0x84000000 开始，最终长度与整段 CRC 必须匹配。
// [ARCH] READY 标记让主机确认执行权已转移。
// [ARCH] UART 字节轮询不依赖操作系统中断服务。
// [ARCH] 通过校验后发送 APAL_GO，经取指同步跳转应用。
// [ARCH] 位置同时由 stage2.S 和 stage2.ld 定义，不能单独改链接地址。
/* Diagnostic alternate APAL receiver. The bootstrap places this in unused
 * instruction SRAM at 0x10002000. CPU RTL and the PAL binary stay unchanged.
 * Bytewise CRC avoids the original loader's shared buffer/table/timer path. */
#include <stdint.h>
#define REG(a) (*(volatile uint32_t *)(uintptr_t)(a))
#define APP 0x84000000u
static int get(void){while(!(REG(0x30000024)&1u)){}return REG(0x30000028)&255u;}
static void put(int c){while(!(REG(0x30000024)&2u)){}REG(0x30000020)=(unsigned)c;}
static void say(const char*s){while(*s)put(*s++);}
static uint32_t word(void){uint32_t v=0;for(unsigned i=0;i<32;i+=8)v|=(uint32_t)get()<<i;return v;}
static uint32_t step(uint32_t c,unsigned v){c^=v;for(unsigned i=0;i<8;i++)c=(c>>1)^(0xedb88320u&-(c&1u));return c;}
static uint32_t crc(uint32_t a,uint32_t n){uint32_t c=~0u;for(uint32_t i=0;i<n;i++)c=step(c,((volatile uint8_t*)(uintptr_t)a)[i]);return ~c;}
__attribute__((section(".text.entry"),noreturn)) void stage2(void){
    const char *ready="APAL_READY V01 100MHz\n";unsigned sync=0,loaded=0;
    say("APAL_STAGE2_READY\n");say(ready);
    for(;;){
        int c=get();if(c!="APAL"[sync]){sync=c=='A';continue;}if(++sync<4)continue;sync=0;
        uint32_t cmd=word(),a=word(),n=word(),expected=word();
        if(cmd==0 && !(a|n|expected)){say(ready);continue;}
        // [ARCH] 长度非零、单块上限和地址窗口同时成立才进入写入。
        // [ARCH] 先按接收字节累计 CRC，再从目标内存回读复核。
        // [ARCH] 主机只在 K 确认后推进装载进度。
        if(cmd==1 && n && n<=1024 && ((a>=APP&&a<0x84800000u&&n<=0x84800000u-a)||(a>=0x85800000u&&a<0x87c00000u&&n<=0x87c00000u-a))){
            uint32_t check=~0u;
            for(unsigned i=0;i<n;i++){unsigned b=get();((volatile uint8_t*)(uintptr_t)a)[i]=(uint8_t)b;check=step(check,b);}
            if(~check==expected && crc(a,n)==expected){loaded|=a==APP;put('K');}else put('N');
        // [ARCH] 最终跳转还要求整段 CRC 匹配，不能只信每块的局部校验。
        // [ARCH] GO 之后执行写入/取指同步，避免旧缓存指令影响入口。
        // [ARCH] 不在尚未校验的任意地址执行。
        }else if(cmd==2 && a==APP && n && n<=0x800000u && loaded && crc(a,n)==expected){
            say("APAL_GO\n");__asm__ volatile("fence rw,rw\n.word 0x0000100f":::"memory");
            ((void(*)(void))(uintptr_t)APP)();for(;;){}
        }else put('N');
    }
}
