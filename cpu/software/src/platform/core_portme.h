/* Original FPGA platform glue. EEMBC algorithm files are unchanged. */
#ifndef CORE_PORTME_H
#define CORE_PORTME_H
#include <stddef.h>
#define HAS_FLOAT 1
#define HAS_TIME_H 0
#define USE_CLOCK 0
#define HAS_STDIO 0
#define HAS_PRINTF 0
/* The build supplies the exact toolchain identity (triple + version) so the
   "Compiler version" report line is unambiguous. */
#ifndef COMPILER_VERSION
#define COMPILER_VERSION "riscv-none-elf-gcc " __VERSION__
#endif
#define COMPILER_FLAGS FLAGS_STR
/* CoreMark reporting rules expect Stack/Static/Heap here, and require the
   memory:core ratio whenever CoreMark/MHz is reported. */
#define MEM_LOCATION "SRAM; I 16KiB 2-way; D 8KiB 2-way; mem:core 1:1             "
typedef signed short ee_s16;
typedef unsigned short ee_u16;
typedef signed int ee_s32;
typedef unsigned int ee_u32;
typedef unsigned char ee_u8;
typedef unsigned long long ee_u64;
typedef double ee_f32;
typedef __UINTPTR_TYPE__ ee_ptr_int;
typedef size_t ee_size_t;
#define align_mem(x) (void *)(4 + (((ee_ptr_int)(x)-1) & ~(ee_ptr_int)3))
#define CORETIMETYPE ee_u64
typedef ee_u64 CORE_TICKS;
#define SEED_METHOD SEED_VOLATILE
#define MEM_METHOD MEM_STATIC
#define MULTITHREAD 1
#define MAIN_HAS_NOARGC 1
#define MAIN_HAS_NORETURN 0
extern ee_u32 default_num_contexts;
typedef struct { ee_u8 portable_id; } core_portable;
void portable_init(core_portable *,int *,char *[]);
void portable_fini(core_portable *);
int ee_printf(const char *,...);
#ifndef PERFORMANCE_RUN
#define PERFORMANCE_RUN 0
#endif
#ifndef VALIDATION_RUN
#define VALIDATION_RUN 0
#endif
#ifndef PROFILE_RUN
#define PROFILE_RUN 0
#endif
#endif
