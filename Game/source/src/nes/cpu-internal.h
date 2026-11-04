// [ARCH] 定义软件 6502 的架构寄存器、标志和寻址中间量。
// [ARCH] CPU_RAM 的测试 CRC 只覆盖明确约定范围。
// [ARCH] 实际硬件主核在 soc/rtl/rv32/core。
#ifndef CPU_INTERNAL_H
#define CPU_INTERNAL_H

#include "common.h"

typedef enum {
  // [ARCH] carry 是状态位掩码，可与整个 P 状态字节按位组合。
  carry_flag     = 0x01,
  // [ARCH] zero 是状态位掩码，可与整个 P 状态字节按位组合。
  zero_flag      = 0x02,
  // [ARCH] interrupt 是状态位掩码，可与整个 P 状态字节按位组合。
  interrupt_flag = 0x04,
  // [ARCH] decimal 是状态位掩码，可与整个 P 状态字节按位组合。
  decimal_flag   = 0x08,
  // [ARCH] break 是状态位掩码，可与整个 P 状态字节按位组合。
  break_flag     = 0x10,
  // [ARCH] unused 是状态位掩码，可与整个 P 状态字节按位组合。
  unused_flag    = 0x20,
  // [ARCH] overflow 是状态位掩码，可与整个 P 状态字节按位组合。
  overflow_flag  = 0x40,
  // [ARCH] negative 是状态位掩码，可与整个 P 状态字节按位组合。
  negative_flag  = 0x80
} cpu_p_flag;

typedef enum {
  // [ARCH] carry 是位编号，供要求位置参数的位操作函数使用；不要传成掩码。
  carry_bp      = 0,
  // [ARCH] zero 是位编号，供要求位置参数的位操作函数使用；不要传成掩码。
  zero_bp       = 1,
  // [ARCH] interrupt 是位编号，供要求位置参数的位操作函数使用；不要传成掩码。
  interrupt_bp  = 2,
  // [ARCH] decimal 是位编号，供要求位置参数的位操作函数使用；不要传成掩码。
  decimal_bp    = 3,
  // [ARCH] break 是位编号，供要求位置参数的位操作函数使用；不要传成掩码。
  break_bp      = 4,
  // [ARCH] unused 是位编号，供要求位置参数的位操作函数使用；不要传成掩码。
  unused_bp     = 5,
  // [ARCH] overflow 是位编号，供要求位置参数的位操作函数使用；不要传成掩码。
  overflow_bp   = 6,
  // [ARCH] negative 是位编号，供要求位置参数的位操作函数使用；不要传成掩码。
  negative_bp   = 7
} cpu_p_bp;

typedef struct {
  word PC; // Program Counter,
  byte SP; // Stack Pointer,
  byte A, X, Y; // Registers
  byte P; // Flag Register
} CPU_STATE;

extern CPU_STATE cpu;

extern byte CPU_RAM[0x8000];
extern int op_value, op_address; // Arguments for current instruction
extern int op_cycles;            // Additional instruction cycles used (e.g. when paging occurs)

byte cpu_ram_read(word address);
void cpu_ram_write(word address, byte data);

// Interrupt Addresses
word cpu_nmi_interrupt_address();
word cpu_reset_interrupt_address();
word cpu_irq_interrupt_address();

// CPU Adressing Modes
void cpu_address_implied();
void cpu_address_immediate();
void cpu_address_zero_page();
void cpu_address_zero_page_x();
void cpu_address_zero_page_y();
void cpu_address_absolute();
void cpu_address_absolute_x();
void cpu_address_absolute_y();
void cpu_address_relative();
void cpu_address_indirect();
void cpu_address_indirect_x();
void cpu_address_indirect_y();

#endif

