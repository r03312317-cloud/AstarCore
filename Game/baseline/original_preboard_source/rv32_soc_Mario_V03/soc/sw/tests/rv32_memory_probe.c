/* Runs on the imported RV32 RTL, not a host imitation of its memory bus. */
#include <stdint.h>
#include "game_regs.h"
#define REG(a) (*(volatile uint32_t *)(a))
static volatile uint32_t seeded = 0x13579bdfu;
static volatile uint32_t memory[8192];
static void put(char c) {
    while (!(REG(MMIO_UART_STATUS) & 2u)) {}
    REG(MMIO_UART_TX) = (uint32_t)c;
}
static void say(const char *s) { while (*s) put(*s++); }
static void fail(char n) {
    say("RV32_MEMORY_FAIL ");put(n);put('\n');
    for (;;) __asm__ volatile("nop");
}
extern uint32_t rv32_ic_a(uint32_t),rv32_ic_b(uint32_t),rv32_ic_c(uint32_t),rv32_ic_cross(uint32_t);
static void sync_code(void) {
    /* FENCE data writeback followed by architectural FENCE.I (Zifencei). */
    __asm__ volatile("fence rw,rw\n.word 0x0000100f" ::: "memory");
}
static void instruction_cache_probe(void) {
    uintptr_t a=(uintptr_t)rv32_ic_a,b=(uintptr_t)rv32_ic_b,c=(uintptr_t)rv32_ic_c;
    if(b-a!=8192u || c-b!=8192u || ((uintptr_t)rv32_ic_cross&63u)!=60u)fail('8');
    for(uint32_t i=0;i<64;i++) {
        if(rv32_ic_a(i)!=i+49u || rv32_ic_b(i)!=i+67u ||
           rv32_ic_a(i)!=i+49u || rv32_ic_c(i)!=i+83u ||
           rv32_ic_a(i)!=i+49u || rv32_ic_b(i)!=i+67u ||
           rv32_ic_cross(i)!=i+7u)fail('8');
    }
    say("RV32_ICACHE_2WAY_OK\n");
    volatile uint32_t *code=(volatile uint32_t *)a;
    uint32_t original=*code;
    *code=0x00750513u; /* addi a0,a0,7 */
    sync_code();
    if(rv32_ic_a(13)!=20u)fail('9');
    *code=original;sync_code();
    if(rv32_ic_a(13)!=62u)fail('9');
    say("RV32_FENCEI_CODE_SYNC_OK\n");
}
int main(void) {
    say("RV32_MEMORY_BEGIN\n");
    if (seeded != 0x13579bdfu) fail('0');
    if (REG(MMIO_CLOCK_HZ) != 100000000u) fail('1');
    if (REG(MMIO_GAME_INPUT) != 0x47494e31u || REG(MMIO_GAME_VIDEO) != 0x47564944u) fail('2');
    for (uint32_t i=0;i<8192;i++) memory[i]=(i*0x10204081u)^0xa55a9c36u;
    __asm__ volatile("fence rw,rw" ::: "memory");
    for (uint32_t i=0;i<8192;i++) if(memory[i]!=((i*0x10204081u)^0xa55a9c36u)) fail('3');
    memory[0]=0x12345678u;
    ((volatile uint8_t *)memory)[1]=0xabu;
    ((volatile uint16_t *)memory)[1]=0xcdefu;
    if(memory[0]!=0xcdefab78u) fail('4');
    if(((volatile int8_t *)memory)[1]!=-85 || ((volatile uint16_t *)memory)[1]!=0xcdefu) fail('5');
    say("RV32_SRAM_OK\n");
    instruction_cache_probe();
    volatile uint32_t *fb=(volatile uint32_t *)FB0_ADDR;
    for(uint32_t i=0;i<16;i++)fb[i]=0x11223344u+i;
    ((volatile uint8_t *)fb)[5]=0xa5;
    ((volatile uint16_t *)fb)[5]=0x7b6c;
    for(uint32_t i=0;i<16;i++) {
        uint32_t expected=0x11223344u+i;
        if(i==1)expected=0x1122a545u;
        if(i==2)expected=0x7b6c3346u;
        if(fb[i]!=expected)fail('6');
    }
    say("RV32_DDR_UNCACHED_OK\n");
    volatile uint32_t *cached=(volatile uint32_t *)0x84000000u;
    for(uint32_t i=0;i<3072;i++)cached[i]=0x5aa5dead^i;
    __asm__ volatile("fence rw,rw" ::: "memory");
    for(uint32_t i=0;i<3072;i++)if(cached[i]!=(0x5aa5dead^i))fail('7');
    say("RV32_DDR_CACHED_OK\nRV32_MEMORY_PASS\n");
    for (;;) __asm__ volatile("nop");
}
