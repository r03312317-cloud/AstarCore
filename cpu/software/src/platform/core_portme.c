/* Original RV32 FPGA adaptation; no benchmark algorithm modifications. */
#include "coremark.h"
#include <stdarg.h>
#ifdef NATIVE_ORACLE
#include <stdio.h>
#include <time.h>


#endif
#ifndef BUILD_ID
#define BUILD_ID "unrecorded"
#endif
#if VALIDATION_RUN
volatile ee_s32 seed1_volatile=0x3415,seed2_volatile=0x3415,seed3_volatile=0x66;
#elif PROFILE_RUN
volatile ee_s32 seed1_volatile=8,seed2_volatile=8,seed3_volatile=8;
#else
volatile ee_s32 seed1_volatile=0,seed2_volatile=0,seed3_volatile=0x66;
#endif
volatile ee_s32 seed4_volatile=ITERATIONS,seed5_volatile=0;
ee_u32 default_num_contexts=1;
static ee_u64 begun,ended;
#ifndef NATIVE_ORACLE
/* The RV32 implements four programmable 64-bit event counters.  Their
   definitions are completed cache-line refills, completed D-cache writebacks,
   and retired conditional branch mispredictions, respectively. */
static ee_u64 events_begin[4], events_end[4];
static ee_u32 events_available;

#define READ_EVENT64(name, low_csr, high_csr) \
static ee_u64 name(void) { \
    ee_u32 hi, lo, hi2; \
    do { \
        __asm__ volatile ("csrr %0, " #high_csr : "=r"(hi) :: "memory"); \
        __asm__ volatile ("csrr %0, " #low_csr : "=r"(lo) :: "memory"); \
        __asm__ volatile ("csrr %0, " #high_csr : "=r"(hi2) :: "memory"); \
    } while (hi != hi2); \
    return ((ee_u64)hi << 32) | lo; \
}
READ_EVENT64(read_event0, 0xb03, 0xb83)
READ_EVENT64(read_event1, 0xb04, 0xb84)
READ_EVENT64(read_event2, 0xb05, 0xb85)
READ_EVENT64(read_event3, 0xb06, 0xb86)

static void setup_events(void) {
    ee_u32 event, a, b, c, d;
    event=1; __asm__ volatile ("csrw 0x323, %0" :: "r"(event) : "memory");
    event=2; __asm__ volatile ("csrw 0x324, %0" :: "r"(event) : "memory");
    event=3; __asm__ volatile ("csrw 0x325, %0" :: "r"(event) : "memory");
    event=4; __asm__ volatile ("csrw 0x326, %0" :: "r"(event) : "memory");
    __asm__ volatile ("csrr %0, 0x323" : "=r"(a) :: "memory");
    __asm__ volatile ("csrr %0, 0x324" : "=r"(b) :: "memory");
    __asm__ volatile ("csrr %0, 0x325" : "=r"(c) :: "memory");
    __asm__ volatile ("csrr %0, 0x326" : "=r"(d) :: "memory");
    events_available=(a==1 && b==2 && c==3 && d==4);
}
static void read_events(ee_u64 values[4]) {
    values[0]=read_event0(); values[1]=read_event1();
    values[2]=read_event2(); values[3]=read_event3();
}
#endif
static ee_u64 now(void) {
#ifdef NATIVE_ORACLE
    struct timespec t; clock_gettime(CLOCK_MONOTONIC,&t);
    return (ee_u64)t.tv_sec*1000000ull+t.tv_nsec/1000;
#else
    /* Real external 64-bit FPGA cycle counter, coherent high/low/high read. */
    ee_u32 h,l,h2;
    do {
        h=*(volatile ee_u32 *)(MMIO_BASE+0x14u);
        l=*(volatile ee_u32 *)(MMIO_BASE+0x10u);
        h2=*(volatile ee_u32 *)(MMIO_BASE+0x14u);
    } while(h!=h2);
    return ((ee_u64)h<<32)|l;
#endif
}
/* Event counter reads bracket the CoreMark timer slightly; only the board's
   retired-instruction snapshots are taken at the same accepted timer reads. */
void start_time(void) {
#ifndef NATIVE_ORACLE
    read_events(events_begin);
#endif
    begun=now();
}
void stop_time(void) {
    ended=now();
#ifndef NATIVE_ORACLE
    read_events(events_end);
#endif
}
CORE_TICKS get_time(void) { return ended-begun; }
secs_ret time_in_secs(CORE_TICKS ticks) { return (secs_ret)ticks/(secs_ret)TIMER_HZ; }
void portable_init(core_portable *p,int *argc,char *argv[]) {
    (void)argc; (void)argv; p->portable_id=1;
    if(sizeof(ee_u32)!=4 || sizeof(ee_ptr_int)!=sizeof(void*)) ee_printf("ERROR! data types\n");
#ifndef NATIVE_ORACLE
    setup_events();
    ee_printf("CoreMark Start...\n");
    ee_printf("\nPANGO FPGA CoreMark\nBuild ID: %s\nCPU Hz: %u\n",BUILD_ID,CPU_HZ);
    ee_printf("Timer Hz: %u\n",TIMER_HZ);
    ee_printf("%s; %s\n",CPU_DESCRIPTION,MEMORY_DESCRIPTION);
#if VALIDATION_RUN
    ee_printf("Starting %u iterations; validation seeds 0x3415,0x3415,0x66\n",ITERATIONS);
#else
    ee_printf("Starting %u iterations; performance seeds 0,0,0x66\n",ITERATIONS);
#endif
#endif
}
static void fixed6(const char *label,ee_u64 millionths) {
    ee_printf("%s: %llu.%06u\n",label,millionths/1000000ull,(unsigned)(millionths%1000000ull));
}
void portable_fini(core_portable *p) {
    ee_u64 ticks=ended-begun;
    p->portable_id=0;
    ee_printf("CoreMark Done...\n");
    ee_printf("Exact start clocks: %llu\nExact stop clocks: %llu\nExact measured clocks: %llu\n",begun,ended,ticks);
    if(ticks && PRINT_DERIVED_SCORES) {
        fixed6("Exact seconds",ticks*1000000ull/TIMER_HZ);
        if (ticks / TIMER_HZ < 10)
            ee_printf("Diagnostic short run: not an official CoreMark result.\n");
        fixed6("Diagnostic iterations/sec",(ee_u64)ITERATIONS*TIMER_HZ*1000000ull/ticks);
#if !defined(NATIVE_ORACLE) && TIMER_HZ == CPU_HZ
        fixed6("Diagnostic CoreMark/MHz",(ee_u64)ITERATIONS*1000000000000ull/ticks);
#endif
    }
#ifndef NATIVE_ORACLE
    {
        volatile ee_u32 *mm=(volatile ee_u32 *)MMIO_BASE;
        ee_u32 abi=mm[0x34/4], reads=mm[0x30/4];
        ee_u64 first=((ee_u64)mm[0x24/4]<<32)|mm[0x20/4];
        ee_u64 last=((ee_u64)mm[0x2c/4]<<32)|mm[0x28/4];
        ee_printf("Total cycles (timer ticks): %llu\n",ticks);
        if(abi==0x52353231u && reads==2 && last>=first && ticks) {
            ee_u64 retired=last-first;
            ee_printf("Total instructions: %llu\n",retired);
            fixed6("IPC",(retired/ticks)*1000000ull+(retired%ticks)*1000000ull/ticks);
        } else {
            ee_printf("Total instructions: unavailable (counter ABI/read count)\n");
            ee_printf("IPC: unavailable\n");
        }
        if(events_available) {
            ee_printf("I-Cache line refills: %llu\n",events_end[0]-events_begin[0]);
            ee_printf("D-Cache line refills: %llu\n",events_end[1]-events_begin[1]);
            ee_printf("D-Cache writebacks: %llu\n",events_end[2]-events_begin[2]);
            ee_printf("Conditional branch misses: %llu\n",events_end[3]-events_begin[3]);
            ee_printf("Event counters include timer-read boundary overhead.\n");
        } else ee_printf("Cache and branch event counters: unavailable\n");
        ee_printf("Cache access rates / front-end and back-end stalls: unavailable\n");
    }
#endif
    ee_printf("RV32_DONE\n");
}
static void putch(char c) {
#ifdef NATIVE_ORACLE
    putchar(c);
#else
    if(c=='\n') *(volatile ee_u32 *)MMIO_BASE='\r';
    /* The peripheral grant stalls while TX is busy: no dropped characters. */
    *(volatile ee_u32 *)MMIO_BASE=(ee_u32)(unsigned char)c;
#endif
}
static void number(ee_u64 x,unsigned base,unsigned width,char pad) {
    char b[32]; unsigned n=0;
    do { unsigned digit=x%base; b[n++]=(char)(digit<10?'0'+digit:'a'+digit-10); x/=base; } while(x);
    while(width>n) { putch(pad); --width; }
    while(n) putch(b[--n]);
}
int ee_printf(const char *s,...) {
    va_list a; va_start(a,s);
    while(*s) {
        if(*s!='%') { putch(*s++); continue; }
        ++s; char pad=' '; unsigned width=0,length=0;
        if(*s=='0') { pad='0'; ++s; }
        while(*s>='0' && *s<='9') width=10*width+(unsigned)(*s++-'0');
        while(*s=='l') { ++length; ++s; }
        char c=*s++;
        if(c=='s') { const char *p=va_arg(a,const char *); while(*p) putch(*p++); }
        else if(c=='c') putch((char)va_arg(a,int));
        else if(c=='d' || c=='i') {
            long long x=length>1?va_arg(a,long long):length?va_arg(a,long):va_arg(a,int);
            if(x<0) { putch('-'); number(0ull-(ee_u64)x,10,width,pad); }
            else number((ee_u64)x,10,width,pad);
        } else if(c=='u' || c=='x') {
            ee_u64 x=length>1?va_arg(a,ee_u64):length?va_arg(a,unsigned long):va_arg(a,unsigned);
            number(x,c=='x'?16:10,width,pad);
        } else if(c=='f') {
            /* CoreMark's stock report lines use %f; the port has no libc, so
               render six fractional digits from the soft-float value. */
            double v=va_arg(a,double);
            if(v<0.0) { putch('-'); v=-v; }
            if(v>1.0e18) v=1.0e18;
            ee_u64 ip=(ee_u64)v;
            ee_u64 fr=(ee_u64)((v-(double)ip)*1000000.0+0.5);
            if(fr>=1000000ull) { fr-=1000000ull; ++ip; }
            number(ip,10,width,pad);
            putch('.');
            number(fr,10,6,'0');
        } else if(c=='%') putch('%');
    }
    va_end(a); return 0;
}
