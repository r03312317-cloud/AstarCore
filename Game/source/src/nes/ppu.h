// [ARCH] 软件 PPU 寄存器和生命周期合同。
// [ARCH] 读写寄存器的状态副作用由 ppuio 接口实现。
#ifndef PPU_H
#define PPU_H

#include "common.h"

typedef struct {
  // [ARCH] 控制寄存器影响模式表选择、地址递增与 NMI 条件。
  byte PPUCTRL;   // $2000 write only
  // [ARCH] 绘制使能/显示相关状态，由模拟寄存器写入更新。
  byte PPUMASK;   // $2001 write only
  // [ARCH] 读取带清状态等副作用，不是任意可写的一般变量。
  byte PPUSTATUS; // $2002 read only
  // [ARCH] 精灵 RAM 当前访问位置，写数据后按原规则推进。
  byte OAMADDR;   // $2003 write only
  // [ARCH] 精灵数据寄存器的模拟状态，图案像素仍从 CHR/PPU RAM 读取。
  byte OAMDATA;   // $2004
  // [ARCH] 滚动寄存器接收相位与具体 X/Y 值需配套解释。
  word PPUSCROLL;
  // [ARCH] 水平/垂直滚动按交替字节写入，不直接等于物理输出坐标。
  byte PPUSCROLL_X, PPUSCROLL_Y; // $2005 write only x2
  // [ARCH] 两次写入形成完整 PPU 虚拟地址，不能当作 FPGA 指针。
  word PPUADDR;   // $2006 write only x2
  // [ARCH] PPU 数据访问相关状态，读取规则由 ppuio 路径实现。
  word PPUDATA;   // $2007

  // [ARCH] 追踪下一滚动字节的接收相位。
  bool scroll_received_x;
  // [ARCH] 追踪 PPU 地址两字节写入的相位。
  bool addr_received_high_byte;
  // [ARCH] 保留原引擎启动等待状态，不表示实体 DDR 已校准。
  bool ready;

  // [ARCH] 名称表镜像的模拟模式，不是 DDR 控制器镜像。
  int mirroring, mirroring_xor;

  // [ARCH] 软件扫描位置，不表示真实 HDMI 此刻扫描到同一像素。
  int x, scanline;
} PPU_STATE;

void ppu_init();

byte ppu_ram_read(word address);
void ppu_ram_write(word address, byte data);
byte ppuio_read(word address);
void ppuio_write(word address, byte data);

bool ppu_generates_nmi();

void ppu_set_mirroring(byte mirroring);

void ppu_cycle();
void ppu_copy(word address, byte *source, int length);
void ppu_sprram_write(byte data);

#endif

