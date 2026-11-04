// [ARCH] 寻址共享 op_value、op_address、op_cycles，供语义处理器消费。
// [ARCH] 立即数来自指令流，零页有效地址限制为 8 位。
// [ARCH] 绝对地址按小端组合，索引方式结合 X/Y。
// [ARCH] 相对偏移先按有符号解释，再加已经推进的 PC。
// [ARCH] 间接跳转保留原 6502 页尾取高字节行为。
// [ARCH] 本注释整理不修订原引擎寻址和周期近似。
#include "cpu.h"
#include "cpu-internal.h"
#include "memory.h"

// CPU Addressing Modes

// [ARCH] 先形成 op_address/op_value 并推进模拟 PC，语义处理器随后消费该结果。
void cpu_address_implied() { }

// [ARCH] 先形成 op_address/op_value 并推进模拟 PC，语义处理器随后消费该结果。
void cpu_address_immediate() {
  op_value = memory_readb(cpu.PC);
  cpu.PC++;
}

// [ARCH] 先形成 op_address/op_value 并推进模拟 PC，语义处理器随后消费该结果。
void cpu_address_zero_page() {
  op_address = memory_readb(cpu.PC);
  op_value = CPU_RAM[op_address];
  cpu.PC++;
}

// [ARCH] 先形成 op_address/op_value 并推进模拟 PC，语义处理器随后消费该结果。
void cpu_address_zero_page_x() {
  op_address = (memory_readb(cpu.PC) + cpu.X) & 0xFF;
  op_value = CPU_RAM[op_address];
  cpu.PC++;
}

// [ARCH] 先形成 op_address/op_value 并推进模拟 PC，语义处理器随后消费该结果。
void cpu_address_zero_page_y() {
  op_address = (memory_readb(cpu.PC) + cpu.Y) & 0xFF;
  op_value = CPU_RAM[op_address];
  cpu.PC++;
}

// [ARCH] 先形成 op_address/op_value 并推进模拟 PC，语义处理器随后消费该结果。
void cpu_address_absolute() {
  op_address = memory_readw(cpu.PC);
  op_value = memory_readb(op_address);
  cpu.PC += 2;
}

// [ARCH] 先形成 op_address/op_value 并推进模拟 PC，语义处理器随后消费该结果。
void cpu_address_absolute_x() {
  op_address = memory_readw(cpu.PC) + cpu.X;
  op_value = memory_readb(op_address);
  cpu.PC += 2;

  if ((op_address >> 8) != (cpu.PC >> 8)) {
    op_cycles++;
  }
}

// [ARCH] 先形成 op_address/op_value 并推进模拟 PC，语义处理器随后消费该结果。
void cpu_address_absolute_y() {
  op_address = (memory_readw(cpu.PC) + cpu.Y) & 0xFFFF;
  op_value = memory_readb(op_address);
  cpu.PC += 2;

  if ((op_address >> 8) != (cpu.PC >> 8)) {
    op_cycles++;
  }
}

// [ARCH] 先形成 op_address/op_value 并推进模拟 PC，语义处理器随后消费该结果。
void cpu_address_relative() {
  op_address = memory_readb(cpu.PC);
  cpu.PC++;
  if (op_address & 0x80)
    op_address -= 0x100;
  op_address += cpu.PC;

  if ((op_address >> 8) != (cpu.PC >> 8)) {
    op_cycles++;
  }
}

// [ARCH] 先形成 op_address/op_value 并推进模拟 PC，语义处理器随后消费该结果。
void cpu_address_indirect() {
  word arg_addr = memory_readw(cpu.PC);

  // The famous 6502 bug when instead of reading from $C0FF/$C100 it reads from $C0FF/$C000
  // [ARCH] 保留页尾高字节取回到同页开头的原 6502 间接跳转行为。
  // [ARCH] 这是兼容被模拟机而有意保留的寻址特性。
  // [ARCH] 不能为了宿主代码简洁而改成普通连续读字。
  if ((arg_addr & 0xFF) == 0xFF) {
    // Buggy code
    op_address = (memory_readb(arg_addr & 0xFF00) << 8) + memory_readb(arg_addr);
  }
  else {
    // Normal code
    op_address = memory_readw(arg_addr);
  }
  cpu.PC += 2;
}

// [ARCH] 先形成 op_address/op_value 并推进模拟 PC，语义处理器随后消费该结果。
void cpu_address_indirect_x() {
  byte arg_addr = memory_readb(cpu.PC);
  op_address = (memory_readb((arg_addr + cpu.X + 1) & 0xFF) << 8) | memory_readb((arg_addr + cpu.X) & 0xFF);
  op_value = memory_readb(op_address);
  cpu.PC++;
}

// [ARCH] 先形成 op_address/op_value 并推进模拟 PC，语义处理器随后消费该结果。
void cpu_address_indirect_y() {
  byte arg_addr = memory_readb(cpu.PC);
  op_address = (((memory_readb((arg_addr + 1) & 0xFF) << 8) | memory_readb(arg_addr)) + cpu.Y) & 0xFFFF;
  op_value = memory_readb(op_address);
  cpu.PC++;

  if ((op_address >> 8) != (cpu.PC >> 8)) {
    op_cycles++;
  }
}

