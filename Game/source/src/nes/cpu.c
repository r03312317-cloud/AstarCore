// [ARCH] 这里的 CPU_STATE 是软件 6502，不是 RV32 的流水线状态。
// [ARCH] 256 项表选择寻址器、语义处理器、名称和基础预算。
// [ARCH] 一条指令先取操作码、再寻址/执行，随后扣减预算。
// [ARCH] cpu_cycles 保留原无符号扣减实现，不作为 FPGA FPS 时基。
// [ARCH] 实板性能使用 RV32 mcycle，两种计数定义必须分开。
// [ARCH] 零/负标志查表更新，其他标志按处理器语义更新。
// [ARCH] 前 2 KiB RAM 镜像和 0x0100 栈页属于被模拟地址空间。
// [ARCH] 当前 ROM 已作状态/图像回归，不代表完整 6502/NES 兼容测试。
#include "cpu.h"
#include "cpu-internal.h"
#include "memory.h"
#include "ppu.h"
#include "common.h"

CPU_STATE cpu;

// CPU Memory

byte CPU_RAM[0x8000];

byte cpu_ram_read(word address) {
  return CPU_RAM[address & 0x7FF];
}

void cpu_ram_write(word address, byte data) {
  CPU_RAM[address & 0x7FF] = data;
}

static byte op_code;             // Current instruction code
int op_value, op_address; // Arguments for current instruction
int op_cycles;            // Additional instruction cycles used (e.g. when paging occurs)
static unsigned long long cpu_cycles;  // Total CPU Cycles Since Power Up (wraps)

static void (*cpu_op_address_mode[256])();       // Array of address modes
static void (*cpu_op_handler[256])();            // Array of instruction function pointers
static bool cpu_op_in_base_instruction_set[256]; // true if instruction is in base 6502 instruction set
static char *cpu_op_name[256];                   // Instruction names
static int cpu_op_cycles[256];                   // CPU cycles used by instructions

static const byte cpu_zn_flag_table[256] = {
  zero_flag,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
  negative_flag,negative_flag,negative_flag,negative_flag,negative_flag,negative_flag,negative_flag,negative_flag,
  negative_flag,negative_flag,negative_flag,negative_flag,negative_flag,negative_flag,negative_flag,negative_flag,
  negative_flag,negative_flag,negative_flag,negative_flag,negative_flag,negative_flag,negative_flag,negative_flag,
  negative_flag,negative_flag,negative_flag,negative_flag,negative_flag,negative_flag,negative_flag,negative_flag,
  negative_flag,negative_flag,negative_flag,negative_flag,negative_flag,negative_flag,negative_flag,negative_flag,
  negative_flag,negative_flag,negative_flag,negative_flag,negative_flag,negative_flag,negative_flag,negative_flag,
  negative_flag,negative_flag,negative_flag,negative_flag,negative_flag,negative_flag,negative_flag,negative_flag,
  negative_flag,negative_flag,negative_flag,negative_flag,negative_flag,negative_flag,negative_flag,negative_flag,
  negative_flag,negative_flag,negative_flag,negative_flag,negative_flag,negative_flag,negative_flag,negative_flag,
  negative_flag,negative_flag,negative_flag,negative_flag,negative_flag,negative_flag,negative_flag,negative_flag,
  negative_flag,negative_flag,negative_flag,negative_flag,negative_flag,negative_flag,negative_flag,negative_flag,
  negative_flag,negative_flag,negative_flag,negative_flag,negative_flag,negative_flag,negative_flag,negative_flag,
  negative_flag,negative_flag,negative_flag,negative_flag,negative_flag,negative_flag,negative_flag,negative_flag,
  negative_flag,negative_flag,negative_flag,negative_flag,negative_flag,negative_flag,negative_flag,negative_flag,
  negative_flag,negative_flag,negative_flag,negative_flag,negative_flag,negative_flag,negative_flag,negative_flag,
  negative_flag,negative_flag,negative_flag,negative_flag,negative_flag,negative_flag,negative_flag,negative_flag,
};

// Interrupt Addresses

word cpu_nmi_interrupt_address()   { return memory_readw(0xFFFA); }
word cpu_reset_interrupt_address() { return memory_readw(0xFFFC); }
word cpu_irq_interrupt_address()   { return memory_readw(0xFFFE); }

// Stack Routines

void cpu_stack_pushb(byte data) { memory_writeb(0x100 + cpu.SP--, data);       }
void cpu_stack_pushw(word data) { memory_writew(0xFF + cpu.SP, data); cpu.SP -= 2; }
byte cpu_stack_popb()           { return memory_readb(0x100 + ++cpu.SP);       }
word cpu_stack_popw()           { cpu.SP += 2; return memory_readw(0xFF + cpu.SP); }

// CPU Instructions

void ____FE____() { /* Instruction for future Extension */ }

#define cpu_flag_set(flag) common_bit_set(cpu.P, flag)
#define cpu_modify_flag(flag, value) common_modify_bitb(&cpu.P, flag, value)
#define cpu_set_flag(flag) common_set_bitb(&cpu.P, flag)
#define cpu_unset_flag(flag) common_unset_bitb(&cpu.P, flag)

#define cpu_update_zn_flags(value) cpu.P = (cpu.P & ~(zero_flag | negative_flag)) | cpu_zn_flag_table[value]

#define cpu_branch(flag) if (flag) cpu.PC = op_address;
#define cpu_compare(reg) \
  int result = reg - op_value; \
  cpu_modify_flag(carry_bp, result >= 0); \
  cpu_modify_flag(zero_bp, result == 0); \
  cpu_modify_flag(negative_bp, (result >> 7) & 1);


// CPU Instructions

// NOP

// [ARCH] 空操作处理器仍由表中预算参与时间推进。
void cpu_op_nop() {}

// Addition

// [ARCH] 累加器带进位加法，分别更新进位、溢出与 Z/N。
void cpu_op_adc() {
  int result = cpu.A + op_value + (cpu_flag_set(carry_bp) ? 1 : 0);
  cpu_modify_flag(carry_bp, !!(result & 0x100));
  cpu_modify_flag(overflow_bp, !!(~(cpu.A ^ op_value) & (cpu.A ^ result) & 0x80));
  cpu.A = result & 0xFF;
  cpu_update_zn_flags(cpu.A);
}

// Subtraction

// [ARCH] 累加器减法沿用 6502 的借位/进位约定。
void cpu_op_sbc() {
  int result = cpu.A - op_value - (cpu_flag_set(carry_bp) ? 0 : 1);
  cpu_modify_flag(carry_bp, !(result & 0x100));
  cpu_modify_flag(overflow_bp, !!((cpu.A ^ op_value) & (cpu.A ^ result) & 0x80));
  cpu.A = result & 0xFF;
  cpu_update_zn_flags(cpu.A);
}

// Bit Manipulation Operations

// [ARCH] 对累加器执行按位与并更新 Z/N。
void cpu_op_and() { cpu_update_zn_flags(cpu.A &= op_value); }
// [ARCH] 测试 A 与操作数，并按实现更新对应状态位。
void cpu_op_bit() {
  cpu_modify_flag(zero_bp, !(cpu.A & op_value));
  cpu.P = (cpu.P & 0x3F) | (0xC0 & op_value);
}
// [ARCH] 对累加器执行按位异或并更新 Z/N。
void cpu_op_eor() { cpu_update_zn_flags(cpu.A ^= op_value); }
// [ARCH] 对累加器执行按位或并更新 Z/N。
void cpu_op_ora() { cpu_update_zn_flags(cpu.A |= op_value); }
// [ARCH] 移位/循环移位保留原来的进位输入输出；内存版还需写回目标。
void cpu_op_asla() {
  cpu_modify_flag(carry_bp, cpu.A & 0x80);
  cpu.A <<= 1;
  cpu_update_zn_flags(cpu.A);
}
// [ARCH] 移位/循环移位保留原来的进位输入输出；内存版还需写回目标。
void cpu_op_asl() {
  cpu_modify_flag(carry_bp, op_value & 0x80);
  op_value <<= 1;
  op_value &= 0xFF;
  cpu_update_zn_flags(op_value);
  memory_writeb(op_address, op_value);
}
// [ARCH] 移位/循环移位保留原来的进位输入输出；内存版还需写回目标。
void cpu_op_lsra() {
  int value = cpu.A >> 1;
  cpu_modify_flag(carry_bp, cpu.A & 0x01);
  cpu.A = value & 0xFF;
  cpu_update_zn_flags(value);
}
// [ARCH] 移位/循环移位保留原来的进位输入输出；内存版还需写回目标。
void cpu_op_lsr() {
  cpu_modify_flag(carry_bp, op_value & 0x01);
  op_value >>= 1;
  op_value &= 0xFF;
  memory_writeb(op_address, op_value);
  cpu_update_zn_flags(op_value);
}

// [ARCH] 移位/循环移位保留原来的进位输入输出；内存版还需写回目标。
void cpu_op_rola() {
  int value = cpu.A << 1;
  value |= cpu_flag_set(carry_bp) ? 1 : 0;
  cpu_modify_flag(carry_bp, value > 0xFF);
  cpu.A = value & 0xFF;
  cpu_update_zn_flags(cpu.A);
}
// [ARCH] 移位/循环移位保留原来的进位输入输出；内存版还需写回目标。
void cpu_op_rol() {
  op_value <<= 1;
  op_value |= cpu_flag_set(carry_bp) ? 1 : 0;
  cpu_modify_flag(carry_bp, op_value > 0xFF);
  op_value &= 0xFF;
  memory_writeb(op_address, op_value);
  cpu_update_zn_flags(op_value);
}
// [ARCH] 移位/循环移位保留原来的进位输入输出；内存版还需写回目标。
void cpu_op_rora() {
  unsigned char carry = cpu_flag_set(carry_bp);
  cpu_modify_flag(carry_bp, cpu.A & 0x01);
  cpu.A = (cpu.A >> 1) | (carry << 7);
  cpu_modify_flag(zero_bp, cpu.A == 0);
  cpu_modify_flag(negative_bp, !!carry);
}
// [ARCH] 移位/循环移位保留原来的进位输入输出；内存版还需写回目标。
void cpu_op_ror() {
  unsigned char carry = cpu_flag_set(carry_bp);
  cpu_modify_flag(carry_bp, op_value & 0x01);
  op_value = ((op_value >> 1) | (carry << 7)) & 0xFF;
  cpu_modify_flag(zero_bp, op_value == 0);
  cpu_modify_flag(negative_bp, !!carry);
  memory_writeb(op_address, op_value);
}

// Loading

// [ARCH] 把寻址得到的值装入 A，随后更新 Z/N。
void cpu_op_lda() { cpu_update_zn_flags(cpu.A = op_value); }
// [ARCH] 把寻址得到的值装入 X，随后更新 Z/N。
void cpu_op_ldx() { cpu_update_zn_flags(cpu.X = op_value); }
// [ARCH] 把寻址得到的值装入 Y，随后更新 Z/N。
void cpu_op_ldy() { cpu_update_zn_flags(cpu.Y = op_value); }

// Storing

// [ARCH] 把 A 写入寻址给出的目标，不能扩大为宿主物理写。
void cpu_op_sta() { memory_writeb(op_address, cpu.A); }
// [ARCH] 把 X 写入 NES 虚拟目标地址。
void cpu_op_stx() { memory_writeb(op_address, cpu.X); }
// [ARCH] 把 Y 写入 NES 虚拟目标地址。
void cpu_op_sty() { memory_writeb(op_address, cpu.Y); }

// Transfering

// [ARCH] 6502 内部寄存器传送，是否更新标志按该处理器原实现保留。
void cpu_op_tax() { cpu_update_zn_flags(cpu.X = cpu.A);  }
// [ARCH] 6502 内部寄存器传送，是否更新标志按该处理器原实现保留。
void cpu_op_txa() { cpu_update_zn_flags(cpu.A = cpu.X);  }
// [ARCH] 6502 内部寄存器传送，是否更新标志按该处理器原实现保留。
void cpu_op_tay() { cpu_update_zn_flags(cpu.Y = cpu.A);  }
// [ARCH] 6502 内部寄存器传送，是否更新标志按该处理器原实现保留。
void cpu_op_tya() { cpu_update_zn_flags(cpu.A = cpu.Y);  }
// [ARCH] 6502 内部寄存器传送，是否更新标志按该处理器原实现保留。
void cpu_op_tsx() { cpu_update_zn_flags(cpu.X = cpu.SP); }
// [ARCH] 6502 内部寄存器传送，是否更新标志按该处理器原实现保留。
void cpu_op_txs() { cpu.SP = cpu.X; }

// Branching Positive

// [ARCH] 按对应状态位的正/反条件决定是否把模拟 PC 改为相对目标。
void cpu_op_bcs() { cpu_branch(cpu_flag_set(carry_bp));     }
// [ARCH] 按对应状态位的正/反条件决定是否把模拟 PC 改为相对目标。
void cpu_op_beq() { cpu_branch(cpu_flag_set(zero_bp));      }
// [ARCH] 按对应状态位的正/反条件决定是否把模拟 PC 改为相对目标。
void cpu_op_bmi() { cpu_branch(cpu_flag_set(negative_bp));  }
// [ARCH] 按对应状态位的正/反条件决定是否把模拟 PC 改为相对目标。
void cpu_op_bvs() { cpu_branch(cpu_flag_set(overflow_bp));  }

// Branching Negative

// [ARCH] 按对应状态位的正/反条件决定是否把模拟 PC 改为相对目标。
void cpu_op_bne() { cpu_branch(!cpu_flag_set(zero_bp));     }
// [ARCH] 按对应状态位的正/反条件决定是否把模拟 PC 改为相对目标。
void cpu_op_bcc() { cpu_branch(!cpu_flag_set(carry_bp));    }
// [ARCH] 按对应状态位的正/反条件决定是否把模拟 PC 改为相对目标。
void cpu_op_bpl() { cpu_branch(!cpu_flag_set(negative_bp)); }
// [ARCH] 按对应状态位的正/反条件决定是否把模拟 PC 改为相对目标。
void cpu_op_bvc() { cpu_branch(!cpu_flag_set(overflow_bp)); }

// Jumping

// [ARCH] 修改模拟 PC，目标由前面的寻址器生成。
void cpu_op_jmp() { cpu.PC = op_address; }

// Subroutines

// [ARCH] 按原栈顺序保存返回位置，再更新模拟 PC。
void cpu_op_jsr() { cpu_stack_pushw(cpu.PC - 1); cpu.PC = op_address; }
// [ARCH] 从模拟栈恢复返回位置并应用原来的 PC 修正。
void cpu_op_rts() { cpu.PC = cpu_stack_popw() + 1; }

// Interruptions

// [ARCH] 保留此轻量引擎原有的软件中断处理，不在注释整理中修订。
void cpu_op_brk() {
  cpu_stack_pushw(cpu.PC - 1);
  cpu_stack_pushb(cpu.P);
  cpu.P |= unused_flag | break_flag;
  cpu.PC = cpu_nmi_interrupt_address();
}
// [ARCH] 从模拟栈恢复状态与 PC，属于被模拟的中断返回。
void cpu_op_rti() { cpu.P = cpu_stack_popb() | unused_flag; cpu.PC = cpu_stack_popw(); }

// Flags

// [ARCH] 只修改指定 6502 状态位，不改变 RV32 的硬件 CSR。
void cpu_op_clc() { cpu_unset_flag(carry_bp);     }
// [ARCH] 只修改指定 6502 状态位，不改变 RV32 的硬件 CSR。
void cpu_op_cld() { cpu_unset_flag(decimal_bp);   }
// [ARCH] 只修改指定 6502 状态位，不改变 RV32 的硬件 CSR。
void cpu_op_cli() { cpu_unset_flag(interrupt_bp); }
// [ARCH] 只修改指定 6502 状态位，不改变 RV32 的硬件 CSR。
void cpu_op_clv() { cpu_unset_flag(overflow_bp);  }
// [ARCH] 只修改指定 6502 状态位，不改变 RV32 的硬件 CSR。
void cpu_op_sec() { cpu_set_flag(carry_bp);       }
// [ARCH] 只修改指定 6502 状态位，不改变 RV32 的硬件 CSR。
void cpu_op_sed() { cpu_set_flag(decimal_bp);     }
// [ARCH] 只修改指定 6502 状态位，不改变 RV32 的硬件 CSR。
void cpu_op_sei() { cpu_set_flag(interrupt_bp);   }

// Comparison

// [ARCH] 比较 A 与操作数，不写回减法结果，只更新相应标志。
void cpu_op_cmp() { cpu_compare(cpu.A); }
// [ARCH] 比较 X 与操作数，寄存器值保持不变。
void cpu_op_cpx() { cpu_compare(cpu.X); }
// [ARCH] 比较 Y 与操作数，寄存器值保持不变。
void cpu_op_cpy() { cpu_compare(cpu.Y); }

// Increment

// [ARCH] 对寻址目标做字节增量并写回，更新 Z/N。
void cpu_op_inc() {
  byte result = op_value + 1;
  memory_writeb(op_address, result);
  cpu_update_zn_flags(result);
}
// [ARCH] 字节寄存器按本机宽度增减，随后更新 Z/N。
void cpu_op_inx() { cpu_update_zn_flags(++cpu.X); }
// [ARCH] 字节寄存器按本机宽度增减，随后更新 Z/N。
void cpu_op_iny() { cpu_update_zn_flags(++cpu.Y); }

// Decrement

// [ARCH] 对寻址目标做字节减量并写回，更新 Z/N。
void cpu_op_dec() {
  byte result = op_value - 1;
  memory_writeb(op_address, result);
  cpu_update_zn_flags(result);
}
// [ARCH] 字节寄存器按本机宽度增减，随后更新 Z/N。
void cpu_op_dex() { cpu_update_zn_flags(--cpu.X); }
// [ARCH] 字节寄存器按本机宽度增减，随后更新 Z/N。
void cpu_op_dey() { cpu_update_zn_flags(--cpu.Y); }

// Stack

// [ARCH] 通过模拟栈传送累加器或状态字节，不使用 RISC-V 宿主调用栈。
void cpu_op_php() { cpu_stack_pushb(cpu.P | 0x30); }
// [ARCH] 通过模拟栈传送累加器或状态字节，不使用 RISC-V 宿主调用栈。
void cpu_op_pha() { cpu_stack_pushb(cpu.A); }
// [ARCH] 通过模拟栈传送累加器或状态字节，不使用 RISC-V 宿主调用栈。
void cpu_op_pla() { cpu.A = cpu_stack_popb(); cpu_update_zn_flags(cpu.A); }
// [ARCH] 通过模拟栈传送累加器或状态字节，不使用 RISC-V 宿主调用栈。
void cpu_op_plp() { cpu.P = (cpu_stack_popb() & 0xEF) | 0x20; }


// Extended Instruction Set

// [ARCH] 保留上游的扩展操作码组合语义，不据此声称全部扩展已通过实板兼容性测试。
void cpu_op_aso() { cpu_op_asl(); cpu_op_ora(); }
// [ARCH] 保留上游的扩展操作码组合语义，不据此声称全部扩展已通过实板兼容性测试。
void cpu_op_axa() { memory_writeb(op_address, cpu.A & cpu.X & (op_address >> 8)); }
// [ARCH] 保留上游的扩展操作码组合语义，不据此声称全部扩展已通过实板兼容性测试。
void cpu_op_axs() { memory_writeb(op_address, cpu.A & cpu.X); }
void cpu_op_dcm()
{
  op_value--;
  op_value &= 0xFF;
  memory_writeb(op_address, op_value);
  cpu_op_cmp();
}
void cpu_op_ins()
{
  op_value = (op_value + 1) & 0xFF;
  memory_writeb(op_address, op_value);
  cpu_op_sbc();
}
// [ARCH] 保留上游的扩展操作码组合语义，不据此声称全部扩展已通过实板兼容性测试。
void cpu_op_lax() { cpu_update_zn_flags(cpu.A = cpu.X = op_value); }
// [ARCH] 保留上游的扩展操作码组合语义，不据此声称全部扩展已通过实板兼容性测试。
void cpu_op_lse() { cpu_op_lsr(); cpu_op_eor(); }
// [ARCH] 保留上游的扩展操作码组合语义，不据此声称全部扩展已通过实板兼容性测试。
void cpu_op_rla() { cpu_op_rol(); cpu_op_and(); }
// [ARCH] 保留上游的扩展操作码组合语义，不据此声称全部扩展已通过实板兼容性测试。
void cpu_op_rra() { cpu_op_ror(); cpu_op_adc(); }


// Base 6502 instruction set

#define CPU_OP_BIS(o, c, f, n, a) \
  cpu_op_cycles[0x##o] = c; \
  cpu_op_handler[0x##o] = cpu_op_##f; \
  cpu_op_name[0x##o] = n; \
  cpu_op_address_mode[0x##o] = cpu_address_##a; \
  cpu_op_in_base_instruction_set[0x##o] = true;

// Not implemented instructions

#define CPU_OP_NII(o, a) \
  cpu_op_cycles[0x##o] = 1; \
  cpu_op_handler[0x##o] = ____FE____; \
  cpu_op_name[0x##o] = "NOP"; \
  cpu_op_address_mode[0x##o] = cpu_address_##a; \
  cpu_op_in_base_instruction_set[0x##o] = false;

// Extended instruction set found in other CPUs and implemented for compatibility

#define CPU_OP_EIS(o, c, f, n, a) \
  cpu_op_cycles[0x##o] = c; \
  cpu_op_handler[0x##o] = cpu_op_##f; \
  cpu_op_name[0x##o] = n; \
  cpu_op_address_mode[0x##o] = cpu_address_##a; \
  cpu_op_in_base_instruction_set[0x##o] = false;

// CPU Lifecycle

void cpu_init() {
  // [ARCH] 操作码 0x00：BRK，implied 寻址，基础预算 7；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(00, 7, brk, "BRK", implied)
  // [ARCH] 操作码 0x01：ORA，indirect_x 寻址，基础预算 6；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(01, 6, ora, "ORA", indirect_x)
  // [ARCH] 操作码 0x05：ORA，zero_page 寻址，基础预算 3；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(05, 3, ora, "ORA", zero_page)
  // [ARCH] 操作码 0x06：ASL，zero_page 寻址，基础预算 5；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(06, 5, asl, "ASL", zero_page)
  // [ARCH] 操作码 0x08：PHP，implied 寻址，基础预算 3；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(08, 3, php, "PHP", implied)
  // [ARCH] 操作码 0x09：ORA，immediate 寻址，基础预算 2；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(09, 2, ora, "ORA", immediate)
  // [ARCH] 操作码 0x0A：ASL，implied 寻址，基础预算 2；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(0A, 2, asla,"ASL", implied)
  // [ARCH] 操作码 0x0D：ORA，absolute 寻址，基础预算 4；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(0D, 4, ora, "ORA", absolute)
  // [ARCH] 操作码 0x0E：ASL，absolute 寻址，基础预算 6；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(0E, 6, asl, "ASL", absolute)
  // [ARCH] 操作码 0x10：BPL，relative 寻址，基础预算 2；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(10, 2, bpl, "BPL", relative)
  // [ARCH] 操作码 0x11：ORA，indirect_y 寻址，基础预算 5；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(11, 5, ora, "ORA", indirect_y)
  // [ARCH] 操作码 0x15：ORA，zero_page_x 寻址，基础预算 4；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(15, 4, ora, "ORA", zero_page_x)
  // [ARCH] 操作码 0x16：ASL，zero_page_x 寻址，基础预算 6；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(16, 6, asl, "ASL", zero_page_x)
  // [ARCH] 操作码 0x18：CLC，implied 寻址，基础预算 2；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(18, 2, clc, "CLC", implied)
  // [ARCH] 操作码 0x19：ORA，absolute_y 寻址，基础预算 4；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(19, 4, ora, "ORA", absolute_y)
  // [ARCH] 操作码 0x1D：ORA，absolute_x 寻址，基础预算 4；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(1D, 4, ora, "ORA", absolute_x)
  // [ARCH] 操作码 0x1E：ASL，absolute_x 寻址，基础预算 7；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(1E, 7, asl, "ASL", absolute_x)
  // [ARCH] 操作码 0x20：JSR，absolute 寻址，基础预算 6；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(20, 6, jsr, "JSR", absolute)
  // [ARCH] 操作码 0x21：AND，indirect_x 寻址，基础预算 6；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(21, 6, and, "AND", indirect_x)
  // [ARCH] 操作码 0x24：BIT，zero_page 寻址，基础预算 3；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(24, 3, bit, "BIT", zero_page)
  // [ARCH] 操作码 0x25：AND，zero_page 寻址，基础预算 3；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(25, 3, and, "AND", zero_page)
  // [ARCH] 操作码 0x26：ROL，zero_page 寻址，基础预算 5；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(26, 5, rol, "ROL", zero_page)
  // [ARCH] 操作码 0x28：PLP，implied 寻址，基础预算 4；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(28, 4, plp, "PLP", implied)
  // [ARCH] 操作码 0x29：AND，immediate 寻址，基础预算 2；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(29, 2, and, "AND", immediate)
  // [ARCH] 操作码 0x2A：ROL，implied 寻址，基础预算 2；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(2A, 2, rola,"ROL", implied)
  // [ARCH] 操作码 0x2C：BIT，absolute 寻址，基础预算 4；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(2C, 4, bit, "BIT", absolute)
  // [ARCH] 操作码 0x2D：AND，absolute 寻址，基础预算 2；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(2D, 2, and, "AND", absolute)
  // [ARCH] 操作码 0x2E：ROL，absolute 寻址，基础预算 6；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(2E, 6, rol, "ROL", absolute)
  // [ARCH] 操作码 0x30：BMI，relative 寻址，基础预算 2；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(30, 2, bmi, "BMI", relative)
  // [ARCH] 操作码 0x31：AND，indirect_y 寻址，基础预算 5；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(31, 5, and, "AND", indirect_y)
  // [ARCH] 操作码 0x35：AND，zero_page_x 寻址，基础预算 4；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(35, 4, and, "AND", zero_page_x)
  // [ARCH] 操作码 0x36：ROL，zero_page_x 寻址，基础预算 6；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(36, 6, rol, "ROL", zero_page_x)
  // [ARCH] 操作码 0x38：SEC，implied 寻址，基础预算 2；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(38, 2, sec, "SEC", implied)
  // [ARCH] 操作码 0x39：AND，absolute_y 寻址，基础预算 4；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(39, 4, and, "AND", absolute_y)
  // [ARCH] 操作码 0x3D：AND，absolute_x 寻址，基础预算 4；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(3D, 4, and, "AND", absolute_x)
  // [ARCH] 操作码 0x3E：ROL，absolute_x 寻址，基础预算 7；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(3E, 7, rol, "ROL", absolute_x)
  // [ARCH] 操作码 0x40：RTI，implied 寻址，基础预算 6；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(40, 6, rti, "RTI", implied)
  // [ARCH] 操作码 0x41：EOR，indirect_x 寻址，基础预算 6；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(41, 6, eor, "EOR", indirect_x)
  // [ARCH] 操作码 0x45：EOR，zero_page 寻址，基础预算 3；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(45, 3, eor, "EOR", zero_page)
  // [ARCH] 操作码 0x46：LSR，zero_page 寻址，基础预算 5；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(46, 5, lsr, "LSR", zero_page)
  // [ARCH] 操作码 0x48：PHA，implied 寻址，基础预算 3；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(48, 3, pha, "PHA", implied)
  // [ARCH] 操作码 0x49：EOR，immediate 寻址，基础预算 2；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(49, 2, eor, "EOR", immediate)
  // [ARCH] 操作码 0x4A：LSR，implied 寻址，基础预算 2；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(4A, 2, lsra,"LSR", implied)
  // [ARCH] 操作码 0x4C：JMP，absolute 寻址，基础预算 3；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(4C, 3, jmp, "JMP", absolute)
  // [ARCH] 操作码 0x4D：EOR，absolute 寻址，基础预算 4；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(4D, 4, eor, "EOR", absolute)
  // [ARCH] 操作码 0x4E：LSR，absolute 寻址，基础预算 6；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(4E, 6, lsr, "LSR", absolute)
  // [ARCH] 操作码 0x50：BVC，relative 寻址，基础预算 2；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(50, 2, bvc, "BVC", relative)
  // [ARCH] 操作码 0x51：EOR，indirect_y 寻址，基础预算 5；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(51, 5, eor, "EOR", indirect_y)
  // [ARCH] 操作码 0x55：EOR，zero_page_x 寻址，基础预算 4；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(55, 4, eor, "EOR", zero_page_x)
  // [ARCH] 操作码 0x56：LSR，zero_page_x 寻址，基础预算 6；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(56, 6, lsr, "LSR", zero_page_x)
  // [ARCH] 操作码 0x58：CLI，implied 寻址，基础预算 2；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(58, 2, cli, "CLI", implied)
  // [ARCH] 操作码 0x59：EOR，absolute_y 寻址，基础预算 4；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(59, 4, eor, "EOR", absolute_y)
  // [ARCH] 操作码 0x5D：EOR，absolute_x 寻址，基础预算 4；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(5D, 4, eor, "EOR", absolute_x)
  // [ARCH] 操作码 0x5E：LSR，absolute_x 寻址，基础预算 7；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(5E, 7, lsr, "LSR", absolute_x)
  // [ARCH] 操作码 0x60：RTS，implied 寻址，基础预算 6；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(60, 6, rts, "RTS", implied)
  // [ARCH] 操作码 0x61：ADC，indirect_x 寻址，基础预算 6；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(61, 6, adc, "ADC", indirect_x)
  // [ARCH] 操作码 0x65：ADC，zero_page 寻址，基础预算 3；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(65, 3, adc, "ADC", zero_page)
  // [ARCH] 操作码 0x66：ROR，zero_page 寻址，基础预算 5；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(66, 5, ror, "ROR", zero_page)
  // [ARCH] 操作码 0x68：PLA，implied 寻址，基础预算 4；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(68, 4, pla, "PLA", implied)
  // [ARCH] 操作码 0x69：ADC，immediate 寻址，基础预算 2；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(69, 2, adc, "ADC", immediate)
  // [ARCH] 操作码 0x6A：ROR，implied 寻址，基础预算 2；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(6A, 2, rora,"ROR", implied)
  // [ARCH] 操作码 0x6C：JMP，indirect 寻址，基础预算 5；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(6C, 5, jmp, "JMP", indirect)
  // [ARCH] 操作码 0x6D：ADC，absolute 寻址，基础预算 4；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(6D, 4, adc, "ADC", absolute)
  // [ARCH] 操作码 0x6E：ROR，absolute 寻址，基础预算 6；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(6E, 6, ror, "ROR", absolute)
  // [ARCH] 操作码 0x70：BVS，relative 寻址，基础预算 2；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(70, 2, bvs, "BVS", relative)
  // [ARCH] 操作码 0x71：ADC，indirect_y 寻址，基础预算 5；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(71, 5, adc, "ADC", indirect_y)
  // [ARCH] 操作码 0x75：ADC，zero_page_x 寻址，基础预算 4；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(75, 4, adc, "ADC", zero_page_x)
  // [ARCH] 操作码 0x76：ROR，zero_page_x 寻址，基础预算 6；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(76, 6, ror, "ROR", zero_page_x)
  // [ARCH] 操作码 0x78：SEI，implied 寻址，基础预算 2；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(78, 2, sei, "SEI", implied)
  // [ARCH] 操作码 0x79：ADC，absolute_y 寻址，基础预算 4；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(79, 4, adc, "ADC", absolute_y)
  // [ARCH] 操作码 0x7D：ADC，absolute_x 寻址，基础预算 4；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(7D, 4, adc, "ADC", absolute_x)
  // [ARCH] 操作码 0x7E：ROR，absolute_x 寻址，基础预算 7；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(7E, 7, ror, "ROR", absolute_x)
  // [ARCH] 操作码 0x81：STA，indirect_x 寻址，基础预算 6；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(81, 6, sta, "STA", indirect_x)
  // [ARCH] 操作码 0x84：STY，zero_page 寻址，基础预算 3；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(84, 3, sty, "STY", zero_page)
  // [ARCH] 操作码 0x85：STA，zero_page 寻址，基础预算 3；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(85, 3, sta, "STA", zero_page)
  // [ARCH] 操作码 0x86：STX，zero_page 寻址，基础预算 3；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(86, 3, stx, "STX", zero_page)
  // [ARCH] 操作码 0x88：DEY，implied 寻址，基础预算 2；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(88, 2, dey, "DEY", implied)
  // [ARCH] 操作码 0x8A：TXA，implied 寻址，基础预算 2；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(8A, 2, txa, "TXA", implied)
  // [ARCH] 操作码 0x8C：STY，absolute 寻址，基础预算 4；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(8C, 4, sty, "STY", absolute)
  // [ARCH] 操作码 0x8D：STA，absolute 寻址，基础预算 4；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(8D, 4, sta, "STA", absolute)
  // [ARCH] 操作码 0x8E：STX，absolute 寻址，基础预算 4；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(8E, 4, stx, "STX", absolute)
  // [ARCH] 操作码 0x90：BCC，relative 寻址，基础预算 2；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(90, 2, bcc, "BCC", relative)
  // [ARCH] 操作码 0x91：STA，indirect_y 寻址，基础预算 6；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(91, 6, sta, "STA", indirect_y)
  // [ARCH] 操作码 0x94：STY，zero_page_x 寻址，基础预算 4；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(94, 4, sty, "STY", zero_page_x)
  // [ARCH] 操作码 0x95：STA，zero_page_x 寻址，基础预算 4；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(95, 4, sta, "STA", zero_page_x)
  // [ARCH] 操作码 0x96：STX，zero_page_y 寻址，基础预算 4；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(96, 4, stx, "STX", zero_page_y)
  // [ARCH] 操作码 0x98：TYA，implied 寻址，基础预算 2；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(98, 2, tya, "TYA", implied)
  // [ARCH] 操作码 0x99：STA，absolute_y 寻址，基础预算 5；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(99, 5, sta, "STA", absolute_y)
  // [ARCH] 操作码 0x9A：TXS，implied 寻址，基础预算 2；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(9A, 2, txs, "TXS", implied)
  // [ARCH] 操作码 0x9D：STA，absolute_x 寻址，基础预算 5；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(9D, 5, sta, "STA", absolute_x)
  // [ARCH] 操作码 0xA0：LDY，immediate 寻址，基础预算 2；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(A0, 2, ldy, "LDY", immediate)
  // [ARCH] 操作码 0xA1：LDA，indirect_x 寻址，基础预算 6；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(A1, 6, lda, "LDA", indirect_x)
  // [ARCH] 操作码 0xA2：LDX，immediate 寻址，基础预算 2；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(A2, 2, ldx, "LDX", immediate)
  // [ARCH] 操作码 0xA4：LDY，zero_page 寻址，基础预算 3；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(A4, 3, ldy, "LDY", zero_page)
  // [ARCH] 操作码 0xA5：LDA，zero_page 寻址，基础预算 3；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(A5, 3, lda, "LDA", zero_page)
  // [ARCH] 操作码 0xA6：LDX，zero_page 寻址，基础预算 3；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(A6, 3, ldx, "LDX", zero_page)
  // [ARCH] 操作码 0xA8：TAY，implied 寻址，基础预算 2；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(A8, 2, tay, "TAY", implied)
  // [ARCH] 操作码 0xA9：LDA，immediate 寻址，基础预算 2；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(A9, 2, lda, "LDA", immediate)
  // [ARCH] 操作码 0xAA：TAX，implied 寻址，基础预算 2；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(AA, 2, tax, "TAX", implied)
  // [ARCH] 操作码 0xAC：LDY，absolute 寻址，基础预算 4；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(AC, 4, ldy, "LDY", absolute)
  // [ARCH] 操作码 0xAD：LDA，absolute 寻址，基础预算 4；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(AD, 4, lda, "LDA", absolute)
  // [ARCH] 操作码 0xAE：LDX，absolute 寻址，基础预算 4；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(AE, 4, ldx, "LDX", absolute)
  // [ARCH] 操作码 0xB0：BCS，relative 寻址，基础预算 2；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(B0, 2, bcs, "BCS", relative)
  // [ARCH] 操作码 0xB1：LDA，indirect_y 寻址，基础预算 5；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(B1, 5, lda, "LDA", indirect_y)
  // [ARCH] 操作码 0xB4：LDY，zero_page_x 寻址，基础预算 4；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(B4, 4, ldy, "LDY", zero_page_x)
  // [ARCH] 操作码 0xB5：LDA，zero_page_x 寻址，基础预算 4；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(B5, 4, lda, "LDA", zero_page_x)
  // [ARCH] 操作码 0xB6：LDX，zero_page_y 寻址，基础预算 4；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(B6, 4, ldx, "LDX", zero_page_y)
  // [ARCH] 操作码 0xB8：CLV，implied 寻址，基础预算 2；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(B8, 2, clv, "CLV", implied)
  // [ARCH] 操作码 0xB9：LDA，absolute_y 寻址，基础预算 4；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(B9, 4, lda, "LDA", absolute_y)
  // [ARCH] 操作码 0xBA：TSX，implied 寻址，基础预算 2；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(BA, 2, tsx, "TSX", implied)
  // [ARCH] 操作码 0xBC：LDY，absolute_x 寻址，基础预算 4；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(BC, 4, ldy, "LDY", absolute_x)
  // [ARCH] 操作码 0xBD：LDA，absolute_x 寻址，基础预算 4；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(BD, 4, lda, "LDA", absolute_x)
  // [ARCH] 操作码 0xBE：LDX，absolute_y 寻址，基础预算 4；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(BE, 4, ldx, "LDX", absolute_y)
  // [ARCH] 操作码 0xC0：CPY，immediate 寻址，基础预算 2；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(C0, 2, cpy, "CPY", immediate)
  // [ARCH] 操作码 0xC1：CMP，indirect_x 寻址，基础预算 6；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(C1, 6, cmp, "CMP", indirect_x)
  // [ARCH] 操作码 0xC4：CPY，zero_page 寻址，基础预算 3；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(C4, 3, cpy, "CPY", zero_page)
  // [ARCH] 操作码 0xC5：CMP，zero_page 寻址，基础预算 3；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(C5, 3, cmp, "CMP", zero_page)
  // [ARCH] 操作码 0xC6：DEC，zero_page 寻址，基础预算 5；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(C6, 5, dec, "DEC", zero_page)
  // [ARCH] 操作码 0xC8：INY，implied 寻址，基础预算 2；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(C8, 2, iny, "INY", implied)
  // [ARCH] 操作码 0xC9：CMP，immediate 寻址，基础预算 2；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(C9, 2, cmp, "CMP", immediate)
  // [ARCH] 操作码 0xCA：DEX，implied 寻址，基础预算 2；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(CA, 2, dex, "DEX", implied)
  // [ARCH] 操作码 0xCC：CPY，absolute 寻址，基础预算 4；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(CC, 4, cpy, "CPY", absolute)
  // [ARCH] 操作码 0xCD：CMP，absolute 寻址，基础预算 4；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(CD, 4, cmp, "CMP", absolute)
  // [ARCH] 操作码 0xCE：DEC，absolute 寻址，基础预算 6；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(CE, 6, dec, "DEC", absolute)
  // [ARCH] 操作码 0xD0：BNE，relative 寻址，基础预算 2；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(D0, 2, bne, "BNE", relative)
  // [ARCH] 操作码 0xD1：CMP，indirect_y 寻址，基础预算 5；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(D1, 5, cmp, "CMP", indirect_y)
  // [ARCH] 操作码 0xD5：CMP，zero_page_x 寻址，基础预算 4；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(D5, 4, cmp, "CMP", zero_page_x)
  // [ARCH] 操作码 0xD6：DEC，zero_page_x 寻址，基础预算 6；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(D6, 6, dec, "DEC", zero_page_x)
  // [ARCH] 操作码 0xD8：CLD，implied 寻址，基础预算 2；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(D8, 2, cld, "CLD", implied)
  // [ARCH] 操作码 0xD9：CMP，absolute_y 寻址，基础预算 4；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(D9, 4, cmp, "CMP", absolute_y)
  // [ARCH] 操作码 0xDD：CMP，absolute_x 寻址，基础预算 4；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(DD, 4, cmp, "CMP", absolute_x)
  // [ARCH] 操作码 0xDE：DEC，absolute_x 寻址，基础预算 7；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(DE, 7, dec, "DEC", absolute_x)
  // [ARCH] 操作码 0xE0：CPX，immediate 寻址，基础预算 2；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(E0, 2, cpx, "CPX", immediate)
  // [ARCH] 操作码 0xE1：SBC，indirect_x 寻址，基础预算 6；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(E1, 6, sbc, "SBC", indirect_x)
  // [ARCH] 操作码 0xE4：CPX，zero_page 寻址，基础预算 3；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(E4, 3, cpx, "CPX", zero_page)
  // [ARCH] 操作码 0xE5：SBC，zero_page 寻址，基础预算 3；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(E5, 3, sbc, "SBC", zero_page)
  // [ARCH] 操作码 0xE6：INC，zero_page 寻址，基础预算 5；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(E6, 5, inc, "INC", zero_page)
  // [ARCH] 操作码 0xE8：INX，implied 寻址，基础预算 2；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(E8, 2, inx, "INX", implied)
  // [ARCH] 操作码 0xE9：SBC，immediate 寻址，基础预算 2；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(E9, 2, sbc, "SBC", immediate)
  // [ARCH] 操作码 0xEA：NOP，implied 寻址，基础预算 2；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(EA, 2, nop, "NOP", implied)
  // [ARCH] 操作码 0xEC：CPX，absolute 寻址，基础预算 4；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(EC, 4, cpx, "CPX", absolute)
  // [ARCH] 操作码 0xED：SBC，absolute 寻址，基础预算 4；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(ED, 4, sbc, "SBC", absolute)
  // [ARCH] 操作码 0xEE：INC，absolute 寻址，基础预算 6；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(EE, 6, inc, "INC", absolute)
  // [ARCH] 操作码 0xF0：BEQ，relative 寻址，基础预算 2；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(F0, 2, beq, "BEQ", relative)
  // [ARCH] 操作码 0xF1：SBC，indirect_y 寻址，基础预算 5；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(F1, 5, sbc, "SBC", indirect_y)
  // [ARCH] 操作码 0xF5：SBC，zero_page_x 寻址，基础预算 4；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(F5, 4, sbc, "SBC", zero_page_x)
  // [ARCH] 操作码 0xF6：INC，zero_page_x 寻址，基础预算 6；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(F6, 6, inc, "INC", zero_page_x)
  // [ARCH] 操作码 0xF8：SED，implied 寻址，基础预算 2；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(F8, 2, sed, "SED", implied)
  // [ARCH] 操作码 0xF9：SBC，absolute_y 寻址，基础预算 4；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(F9, 4, sbc, "SBC", absolute_y)
  // [ARCH] 操作码 0xFD：SBC，absolute_x 寻址，基础预算 4；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(FD, 4, sbc, "SBC", absolute_x)
  // [ARCH] 操作码 0xFE：INC，absolute_x 寻址，基础预算 7；附加预算由 op_cycles 单独计入。
  CPU_OP_BIS(FE, 7, inc, "INC", absolute_x)

  // [ARCH] 操作码 0x03：SLO，indirect_x 寻址，基础预算 8；附加预算由 op_cycles 单独计入。
  CPU_OP_EIS(03, 8, aso, "SLO", indirect_x)
  // [ARCH] 操作码 0x07：SLO，zero_page 寻址，基础预算 5；附加预算由 op_cycles 单独计入。
  CPU_OP_EIS(07, 5, aso, "SLO", zero_page)
  // [ARCH] 操作码 0x0F：SLO，absolute 寻址，基础预算 6；附加预算由 op_cycles 单独计入。
  CPU_OP_EIS(0F, 6, aso, "SLO", absolute)
  // [ARCH] 操作码 0x13：SLO，indirect_y 寻址，基础预算 8；附加预算由 op_cycles 单独计入。
  CPU_OP_EIS(13, 8, aso, "SLO", indirect_y)
  // [ARCH] 操作码 0x17：SLO，zero_page_x 寻址，基础预算 6；附加预算由 op_cycles 单独计入。
  CPU_OP_EIS(17, 6, aso, "SLO", zero_page_x)
  // [ARCH] 操作码 0x1B：SLO，absolute_y 寻址，基础预算 7；附加预算由 op_cycles 单独计入。
  CPU_OP_EIS(1B, 7, aso, "SLO", absolute_y)
  // [ARCH] 操作码 0x1F：SLO，absolute_x 寻址，基础预算 7；附加预算由 op_cycles 单独计入。
  CPU_OP_EIS(1F, 7, aso, "SLO", absolute_x)
  // [ARCH] 操作码 0x23：RLA，indirect_x 寻址，基础预算 8；附加预算由 op_cycles 单独计入。
  CPU_OP_EIS(23, 8, rla, "RLA", indirect_x)
  // [ARCH] 操作码 0x27：RLA，zero_page 寻址，基础预算 5；附加预算由 op_cycles 单独计入。
  CPU_OP_EIS(27, 5, rla, "RLA", zero_page)
  // [ARCH] 操作码 0x2F：RLA，absolute 寻址，基础预算 6；附加预算由 op_cycles 单独计入。
  CPU_OP_EIS(2F, 6, rla, "RLA", absolute)
  // [ARCH] 操作码 0x33：RLA，indirect_y 寻址，基础预算 8；附加预算由 op_cycles 单独计入。
  CPU_OP_EIS(33, 8, rla, "RLA", indirect_y)
  // [ARCH] 操作码 0x37：RLA，zero_page_x 寻址，基础预算 6；附加预算由 op_cycles 单独计入。
  CPU_OP_EIS(37, 6, rla, "RLA", zero_page_x)
  // [ARCH] 操作码 0x3B：RLA，absolute_y 寻址，基础预算 7；附加预算由 op_cycles 单独计入。
  CPU_OP_EIS(3B, 7, rla, "RLA", absolute_y)
  // [ARCH] 操作码 0x3F：RLA，absolute_x 寻址，基础预算 7；附加预算由 op_cycles 单独计入。
  CPU_OP_EIS(3F, 7, rla, "RLA", absolute_x)
  // [ARCH] 操作码 0x43：SRE，indirect_x 寻址，基础预算 8；附加预算由 op_cycles 单独计入。
  CPU_OP_EIS(43, 8, lse, "SRE", indirect_x)
  // [ARCH] 操作码 0x47：SRE，zero_page 寻址，基础预算 5；附加预算由 op_cycles 单独计入。
  CPU_OP_EIS(47, 5, lse, "SRE", zero_page)
  // [ARCH] 操作码 0x4F：SRE，absolute 寻址，基础预算 6；附加预算由 op_cycles 单独计入。
  CPU_OP_EIS(4F, 6, lse, "SRE", absolute)
  // [ARCH] 操作码 0x53：SRE，indirect_y 寻址，基础预算 8；附加预算由 op_cycles 单独计入。
  CPU_OP_EIS(53, 8, lse, "SRE", indirect_y)
  // [ARCH] 操作码 0x57：SRE，zero_page_x 寻址，基础预算 6；附加预算由 op_cycles 单独计入。
  CPU_OP_EIS(57, 6, lse, "SRE", zero_page_x)
  // [ARCH] 操作码 0x5B：SRE，absolute_y 寻址，基础预算 7；附加预算由 op_cycles 单独计入。
  CPU_OP_EIS(5B, 7, lse, "SRE", absolute_y)
  // [ARCH] 操作码 0x5F：SRE，absolute_x 寻址，基础预算 7；附加预算由 op_cycles 单独计入。
  CPU_OP_EIS(5F, 7, lse, "SRE", absolute_x)
  // [ARCH] 操作码 0x63：RRA，indirect_x 寻址，基础预算 8；附加预算由 op_cycles 单独计入。
  CPU_OP_EIS(63, 8, rra, "RRA", indirect_x)
  // [ARCH] 操作码 0x67：RRA，zero_page 寻址，基础预算 5；附加预算由 op_cycles 单独计入。
  CPU_OP_EIS(67, 5, rra, "RRA", zero_page)
  // [ARCH] 操作码 0x6F：RRA，absolute 寻址，基础预算 6；附加预算由 op_cycles 单独计入。
  CPU_OP_EIS(6F, 6, rra, "RRA", absolute)
  // [ARCH] 操作码 0x73：RRA，indirect_y 寻址，基础预算 8；附加预算由 op_cycles 单独计入。
  CPU_OP_EIS(73, 8, rra, "RRA", indirect_y)
  // [ARCH] 操作码 0x77：RRA，zero_page_x 寻址，基础预算 6；附加预算由 op_cycles 单独计入。
  CPU_OP_EIS(77, 6, rra, "RRA", zero_page_x)
  // [ARCH] 操作码 0x7B：RRA，absolute_y 寻址，基础预算 7；附加预算由 op_cycles 单独计入。
  CPU_OP_EIS(7B, 7, rra, "RRA", absolute_y)
  // [ARCH] 操作码 0x7F：RRA，absolute_x 寻址，基础预算 7；附加预算由 op_cycles 单独计入。
  CPU_OP_EIS(7F, 7, rra, "RRA", absolute_x)
  // [ARCH] 操作码 0x83：SAX，indirect_x 寻址，基础预算 6；附加预算由 op_cycles 单独计入。
  CPU_OP_EIS(83, 6, axs, "SAX", indirect_x)
  // [ARCH] 操作码 0x87：SAX，zero_page 寻址，基础预算 3；附加预算由 op_cycles 单独计入。
  CPU_OP_EIS(87, 3, axs, "SAX", zero_page)
  // [ARCH] 操作码 0x8F：SAX，absolute 寻址，基础预算 4；附加预算由 op_cycles 单独计入。
  CPU_OP_EIS(8F, 4, axs, "SAX", absolute)
  // [ARCH] 操作码 0x93：SAX，indirect_y 寻址，基础预算 6；附加预算由 op_cycles 单独计入。
  CPU_OP_EIS(93, 6, axa, "SAX", indirect_y)
  // [ARCH] 操作码 0x97：SAX，zero_page_y 寻址，基础预算 4；附加预算由 op_cycles 单独计入。
  CPU_OP_EIS(97, 4, axs, "SAX", zero_page_y)
  // [ARCH] 操作码 0x9F：SAX，absolute_y 寻址，基础预算 5；附加预算由 op_cycles 单独计入。
  CPU_OP_EIS(9F, 5, axa, "SAX", absolute_y)
  // [ARCH] 操作码 0xA3：LAX，indirect_x 寻址，基础预算 6；附加预算由 op_cycles 单独计入。
  CPU_OP_EIS(A3, 6, lax, "LAX", indirect_x)
  // [ARCH] 操作码 0xA7：LAX，zero_page 寻址，基础预算 3；附加预算由 op_cycles 单独计入。
  CPU_OP_EIS(A7, 3, lax, "LAX", zero_page)
  // [ARCH] 操作码 0xAF：LAX，absolute 寻址，基础预算 4；附加预算由 op_cycles 单独计入。
  CPU_OP_EIS(AF, 4, lax, "LAX", absolute)
  // [ARCH] 操作码 0xB3：LAX，indirect_y 寻址，基础预算 5；附加预算由 op_cycles 单独计入。
  CPU_OP_EIS(B3, 5, lax, "LAX", indirect_y)
  // [ARCH] 操作码 0xB7：LAX，zero_page_y 寻址，基础预算 4；附加预算由 op_cycles 单独计入。
  CPU_OP_EIS(B7, 4, lax, "LAX", zero_page_y)
  // [ARCH] 操作码 0xBF：LAX，absolute_y 寻址，基础预算 4；附加预算由 op_cycles 单独计入。
  CPU_OP_EIS(BF, 4, lax, "LAX", absolute_y)
  // [ARCH] 操作码 0xC3：DCP，indirect_x 寻址，基础预算 8；附加预算由 op_cycles 单独计入。
  CPU_OP_EIS(C3, 8, dcm, "DCP", indirect_x)
  // [ARCH] 操作码 0xC7：DCP，zero_page 寻址，基础预算 5；附加预算由 op_cycles 单独计入。
  CPU_OP_EIS(C7, 5, dcm, "DCP", zero_page)
  // [ARCH] 操作码 0xCF：DCP，absolute 寻址，基础预算 6；附加预算由 op_cycles 单独计入。
  CPU_OP_EIS(CF, 6, dcm, "DCP", absolute)
  // [ARCH] 操作码 0xD3：DCP，indirect_y 寻址，基础预算 8；附加预算由 op_cycles 单独计入。
  CPU_OP_EIS(D3, 8, dcm, "DCP", indirect_y)
  // [ARCH] 操作码 0xD7：DCP，zero_page_x 寻址，基础预算 6；附加预算由 op_cycles 单独计入。
  CPU_OP_EIS(D7, 6, dcm, "DCP", zero_page_x)
  // [ARCH] 操作码 0xDB：DCP，absolute_y 寻址，基础预算 7；附加预算由 op_cycles 单独计入。
  CPU_OP_EIS(DB, 7, dcm, "DCP", absolute_y)
  // [ARCH] 操作码 0xDF：DCP，absolute_x 寻址，基础预算 7；附加预算由 op_cycles 单独计入。
  CPU_OP_EIS(DF, 7, dcm, "DCP", absolute_x)
  // [ARCH] 操作码 0xE3：ISB，indirect_x 寻址，基础预算 8；附加预算由 op_cycles 单独计入。
  CPU_OP_EIS(E3, 8, ins, "ISB", indirect_x)
  // [ARCH] 操作码 0xE7：ISB，zero_page 寻址，基础预算 5；附加预算由 op_cycles 单独计入。
  CPU_OP_EIS(E7, 5, ins, "ISB", zero_page)
  // [ARCH] 操作码 0xEB：SBC，immediate 寻址，基础预算 2；附加预算由 op_cycles 单独计入。
  CPU_OP_EIS(EB, 2, sbc, "SBC", immediate)
  // [ARCH] 操作码 0xEF：ISB，absolute 寻址，基础预算 6；附加预算由 op_cycles 单独计入。
  CPU_OP_EIS(EF, 6, ins, "ISB", absolute)
  // [ARCH] 操作码 0xF3：ISB，indirect_y 寻址，基础预算 8；附加预算由 op_cycles 单独计入。
  CPU_OP_EIS(F3, 8, ins, "ISB", indirect_y)
  // [ARCH] 操作码 0xF7：ISB，zero_page_x 寻址，基础预算 6；附加预算由 op_cycles 单独计入。
  CPU_OP_EIS(F7, 6, ins, "ISB", zero_page_x)
  // [ARCH] 操作码 0xFB：ISB，absolute_y 寻址，基础预算 7；附加预算由 op_cycles 单独计入。
  CPU_OP_EIS(FB, 7, ins, "ISB", absolute_y)
  // [ARCH] 操作码 0xFF：ISB，absolute_x 寻址，基础预算 7；附加预算由 op_cycles 单独计入。
  CPU_OP_EIS(FF, 7, ins, "ISB", absolute_x)

  CPU_OP_NII(04, zero_page)
  CPU_OP_NII(0C, absolute)
  CPU_OP_NII(14, zero_page_x)
  CPU_OP_NII(1A, implied)
  CPU_OP_NII(1C, absolute_x)
  CPU_OP_NII(34, zero_page_x)
  CPU_OP_NII(3A, implied)
  CPU_OP_NII(3C, absolute_x)
  CPU_OP_NII(44, zero_page)
  CPU_OP_NII(54, zero_page_x)
  CPU_OP_NII(5A, implied)
  CPU_OP_NII(5C, absolute_x)
  CPU_OP_NII(64, zero_page)
  CPU_OP_NII(74, zero_page_x)
  CPU_OP_NII(7A, implied)
  CPU_OP_NII(7C, absolute_x)
  CPU_OP_NII(80, immediate)
  CPU_OP_NII(D4, zero_page_x)
  CPU_OP_NII(DA, implied)
  CPU_OP_NII(DC, absolute_x)
  CPU_OP_NII(F4, zero_page_x)
  CPU_OP_NII(FA, implied)
  CPU_OP_NII(FC, absolute_x)

  cpu.P = 0x24;
  cpu.SP = 0x00;
  cpu.A = cpu.X = cpu.Y = 0;
}

// [ARCH] 从模拟复位向量建立 PC，按原实现调整 SP 和状态位。
// [ARCH] 不会复位 FPGA、RV32 缓存或 DDR。
// [ARCH] 模拟与实体复位的作用域必须区分。
void cpu_reset() {
  cpu.PC = cpu_reset_interrupt_address();
  cpu.SP -= 3;
  cpu.P |= interrupt_flag;
}

// [ARCH] 只按当前 PPU 的 NMI 条件进入原实现中断路径。
// [ARCH] 压入的是模拟 PC/状态，目标向量来自模拟 ROM。
// [ARCH] 这不触发 RISC-V 的机器态异常。
void cpu_interrupt() {
  if (ppu_generates_nmi()) {
    cpu.P |= interrupt_flag;
    cpu_unset_flag(unused_bp);
    cpu_stack_pushw(cpu.PC);
    cpu_stack_pushb(cpu.P);
    cpu.PC = cpu_nmi_interrupt_address();
  }
}

unsigned long long cpu_clock() {
  return cpu_cycles;
}

// [ARCH] 先调用寻址器，再调用语义处理器。
// [ARCH] 基础预算与附加预算一起扣除，随后清附加预算。
// [ARCH] cpu_clock 的原引擎统计不能拿来计算实板 FPS。
void cpu_run(long cycles) {
  cycles /= 3;
  while (cycles > 0) {
    op_code = memory_readb(cpu.PC++);
    if (cpu_op_address_mode[op_code] == NULL) {
    }
    else {
      cpu_op_address_mode[op_code]();
      cpu_op_handler[op_code]();
    }
    cycles -= cpu_op_cycles[op_code] + op_cycles;
    cpu_cycles -= cpu_op_cycles[op_code] + op_cycles;
    op_cycles = 0;
  }
}

