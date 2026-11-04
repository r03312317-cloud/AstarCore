// [ARCH] 分派模拟 RAM、PPU 寄存器、手柄与 ROM 地址空间。
// [ARCH] 16 位 NES 虚拟地址不同于 RISC-V 32 位物理地址。
// [ARCH] 字访问拆成小端顺序的两个字节。
// [ARCH] PPU/手柄访问有副作用，不能用普通指针读取替代。
#include "memory.h"
#include "cpu.h"
#include "ppu.h"
#include "psg.h"

byte memory_readb(word address) {
  switch (address >> 13) {
    case 0: return cpu_ram_read(address & 0x07FF);
    case 1: return ppuio_read(address);
    case 2: return psgio_read(address);
    case 3: return cpu_ram_read(address & 0x1FFF);
    default: return mmc_read(address);
  }
}

void memory_writeb(word address, byte data) {
  // DMA transfer
  int i;
  if (address == 0x4014) {
    for (i = 0; i < 256; i++) {
      ppu_sprram_write(cpu_ram_read((0x100 * data) + i));
    }
    return;
  }
  switch (address >> 13) {
    case 0: return cpu_ram_write(address & 0x07FF, data);
    case 1: return ppuio_write(address, data);
    case 2: return psgio_write(address, data);
    case 3: return cpu_ram_write(address & 0x1FFF, data);
    default: return mmc_write(address, data);
  }
}

// [ARCH] 按原虚拟地址顺序读取低字节和高字节。
// [ARCH] 可能经过带副作用的设备分派。
// [ARCH] 不改成宿主未对齐指针强转。
word memory_readw(word address) {
  return memory_readb(address) + (memory_readb(address + 1) << 8);
}

// [ARCH] 拆成两个小端字节写入原模拟地址空间。
// [ARCH] 两个地址可能触发各自设备语义。
// [ARCH] 写入不是对 FPGA 物理 DDR 的直接整字操作。
void memory_writew(word address, word data) {
  memory_writeb(address, data & 0xFF);
  memory_writeb(address + 1, data >> 8);
}

