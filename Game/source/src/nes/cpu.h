// [ARCH] 定义模拟 6502 的初始化、复位、中断和预算执行接口。
// [ARCH] 预算由 PPU 扫描线调度，不等于 RV32 实际周期。
#include "common.h"

#ifndef CPU_H
#define CPU_H

byte cpu_ram_read(word address);
void cpu_ram_write(word address, byte data);

void cpu_init();
void cpu_reset();
void cpu_interrupt();
void cpu_run(long cycles);

// CPU cycles that passed since power up
unsigned long long cpu_clock();

#endif

