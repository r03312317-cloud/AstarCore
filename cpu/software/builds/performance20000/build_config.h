#define ITERATIONS 20000
#define CPU_HZ 130000000
#define TIMER_HZ 130000000
#define MMIO_BASE 805306368
#define TOTAL_DATA_SIZE 2000
#define PERFORMANCE_RUN 1
#define VALIDATION_RUN 0
#define PROFILE_RUN 0
#define PRINT_DERIVED_SCORES 1
#define BUILD_ID "RV32CM130_I2W2_161204bf31efb32d"
#define FLAGS_STR "-O3 -funroll-loops -funroll-all-loops -mbranch-cost=1 --param max-inline-insns-auto=200 -march=rv32im_zicsr_zba_zbb_zbc_zbs -mabi=ilp32 -mno-relax -ffreestanding -fno-builtin -fno-common -fno-pic -fno-stack-protector -nostdlib -static -mrelax -mtune=sifive-7-series -falign-functions=32 -falign-loops=4 -falign-jumps=4 -falign-labels=4 -mbranch-cost=2 -mbranch-cost=1 -msmall-data-limit=16 -O2 --param=max-inline-insns-auto=80 -falign-jumps=8 -falign-functions=16"
#define COMPILER_VERSION "riscv-none-elf-gcc.EXE (xPack GNU RISC-V Embedded GCC x86_64) 15.2.0"
#define MEMORY_DESCRIPTION "64KiB SRAM; I16KiB/2way; D8KiB/2way               "
#define CPU_DESCRIPTION "RV32 RV32 130 H12/I12 RV32IM_Zicsr_Zba_Zbb_Zbc_Zbs"
