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
        if(cmd==1 && n && n<=1024 && ((a>=APP&&a<0x84800000u&&n<=0x84800000u-a)||(a>=0x85800000u&&a<0x87c00000u&&n<=0x87c00000u-a))){
            uint32_t check=~0u;
            for(unsigned i=0;i<n;i++){unsigned b=get();((volatile uint8_t*)(uintptr_t)a)[i]=(uint8_t)b;check=step(check,b);}
            if(~check==expected && crc(a,n)==expected){loaded|=a==APP;put('K');}else put('N');
        }else if(cmd==2 && a==APP && n && n<=0x800000u && loaded && crc(a,n)==expected){
            say("APAL_GO\n");__asm__ volatile("fence rw,rw\n.word 0x0000100f":::"memory");
            ((void(*)(void))(uintptr_t)APP)();for(;;){}
        }else put('N');
    }
}
