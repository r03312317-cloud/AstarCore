// [ARCH] 软件 PPU 逐扫描线推进 6502 预算、绘制、vblank 与 NMI。
// [ARCH] 背景命中信息按行排列，改善缓存局部性。
// [ARCH] 512 字节位平面表组成每像素两位的模式行。
// [ARCH] 背景直接写有效画布行，同时保留精灵命中参考。
// [ARCH] 精灵翻转改变模式选择，索引 0 保留透明语义。
// [ARCH] 第 241 行进入 vblank，第 262 行结束本模拟帧。
// [ARCH] 寄存器读取可能清状态和锁存，不能当普通数组读取。
// [ARCH] OAM、名称表和滚动属于 NES 虚拟空间，不是 FPGA DDR 地址。
// [ARCH] 原引擎的近似和 FIXME 保留，不宣称完整周期精确实现。
// [ARCH] 本版仅整理注释，不改变优先级、命中或地址算法。
#include "ppu.h"
#include "cpu.h"
#include "fce.h"
#include "memory.h"
#include <klib.h>
#include "mario_profile.h"

//#define PROFILE
//#define HAS_US_TIMER

PPU_STATE ppu;

static bool ppu_2007_first_read;
static byte ppu_addr_latch;
static byte PPU_SPRRAM[0x100];
static byte PPU_RAM[0x4000];
static bool ppu_sprite_hit_occured = false;
static byte ppu_latch;

// PPU Constants
static const word ppu_base_nametable_addresses[4] = { 0x2000, 0x2400, 0x2800, 0x2C00 };

// For sprite-0-hit checks
static byte ppu_screen_background[248][264];

/* One packed row holds eight 2-bit pixels. Two 512-byte-table loads replace
 * sixteen byte-table loads per tile. Normal order starts at bit 14. */
static uint16_t ppu_pattern_bits[256];
static inline unsigned pattern_row(byte l,byte h) {
  return ppu_pattern_bits[l] | ((unsigned)ppu_pattern_bits[h]<<1);
}


// PPUCTRL Functions

word ppu_base_nametable_address()           { return ppu_base_nametable_addresses[ppu.PPUCTRL & 0x3];  }
byte ppu_vram_address_increment()           { return common_bit_set(ppu.PPUCTRL, 2) ? 32 : 1;          }
word ppu_sprite_pattern_table_address()     { return common_bit_set(ppu.PPUCTRL, 3) ? 0x1000 : 0x0000; }
word ppu_background_pattern_table_address() { return common_bit_set(ppu.PPUCTRL, 4) ? 0x1000 : 0x0000; }
byte ppu_sprite_height()                    { return common_bit_set(ppu.PPUCTRL, 5) ? 16 : 8;          }
bool ppu_generates_nmi()                    { return common_bit_set(ppu.PPUCTRL, 7);                   }

// PPUMASK Functions

bool ppu_renders_grayscale()                { return common_bit_set(ppu.PPUMASK, 0); }
bool ppu_shows_background_in_leftmost_8px() { return common_bit_set(ppu.PPUMASK, 1); }
bool ppu_shows_sprites_in_leftmost_8px()    { return common_bit_set(ppu.PPUMASK, 2); }
bool ppu_shows_background()                 { return common_bit_set(ppu.PPUMASK, 3); }
bool ppu_shows_sprites()                    { return common_bit_set(ppu.PPUMASK, 4); }
bool ppu_intensifies_reds()                 { return common_bit_set(ppu.PPUMASK, 5); }
bool ppu_intensifies_greens()               { return common_bit_set(ppu.PPUMASK, 6); }
bool ppu_intensifies_blues()                { return common_bit_set(ppu.PPUMASK, 7); }

void ppu_set_renders_grayscale(bool yesno)                { common_modify_bitb(&ppu.PPUMASK, 0, yesno); }
void ppu_set_shows_background_in_leftmost_8px(bool yesno) { common_modify_bitb(&ppu.PPUMASK, 1, yesno); }
void ppu_set_shows_sprites_in_leftmost_8px(bool yesno)    { common_modify_bitb(&ppu.PPUMASK, 2, yesno); }
void ppu_set_shows_background(bool yesno)                 { common_modify_bitb(&ppu.PPUMASK, 3, yesno); }
void ppu_set_shows_sprites(bool yesno)                    { common_modify_bitb(&ppu.PPUMASK, 4, yesno); }
void ppu_set_intensifies_reds(bool yesno)                 { common_modify_bitb(&ppu.PPUMASK, 5, yesno); }
void ppu_set_intensifies_greens(bool yesno)               { common_modify_bitb(&ppu.PPUMASK, 6, yesno); }
void ppu_set_intensifies_blues(bool yesno)                { common_modify_bitb(&ppu.PPUMASK, 7, yesno); }

// PPUSTATUS Functions

bool ppu_sprite_overflow()               { return common_bit_set(ppu.PPUSTATUS, 5); }
bool ppu_sprite_0_hit()                  { return common_bit_set(ppu.PPUSTATUS, 6); }
bool ppu_in_vblank()                     { return common_bit_set(ppu.PPUSTATUS, 7); }

void ppu_set_sprite_overflow(bool yesno) { common_modify_bitb(&ppu.PPUSTATUS, 5, yesno); }
void ppu_set_sprite_0_hit(bool yesno)    { common_modify_bitb(&ppu.PPUSTATUS, 6, yesno); }
void ppu_set_in_vblank(bool yesno)       { common_modify_bitb(&ppu.PPUSTATUS, 7, yesno); }


// RAM

word ppu_get_real_ram_address(word address) {
  if (address < 0x2000) { return address; }
  else if (address < 0x3F00) {
    if (address < 0x3000) { return address; }
    else { return address; }
  }
  else if (address < 0x4000) {
    address = 0x3F00 | (address & 0x1F);
    if (address == 0x3F10 || address == 0x3F14 || address == 0x3F18 || address == 0x3F1C)
      address -= 0x10;
    return address;
  }
  return 0xFFFF;
}

byte ppu_ram_read(word address) {
  return PPU_RAM[ppu_get_real_ram_address(address)];
}

void ppu_ram_write(word address, byte data) {
  PPU_RAM[ppu_get_real_ram_address(address)] = data;
}

// 3F01 = 0F (00001111)
// 3F02 = 2A (00101010)
// 3F03 = 09 (00001001)
// 3F04 = 07 (00000111)
// 3F05 = 0F (00001111)
// 3F06 = 30 (00110000)
// 3F07 = 27 (00100111)
// 3F08 = 15 (00010101)
// 3F09 = 0F (00001111)
// 3F0A = 30 (00110000)
// 3F0B = 02 (00000010)
// 3F0C = 21 (00100001)
// 3F0D = 0F (00001111)
// 3F0E = 30 (00110000)
// 3F0F = 00 (00000000)
// 3F11 = 0F (00001111)
// 3F12 = 16 (00010110)
// 3F13 = 12 (00010010)
// 3F14 = 37 (00110111)
// 3F15 = 0F (00001111)
// 3F16 = 12 (00010010)
// 3F17 = 16 (00010110)
// 3F18 = 37 (00110111)
// 3F19 = 0F (00001111)
// 3F1A = 17 (00010111)
// 3F1B = 11 (00010001)
// 3F1C = 35 (00110101)
// 3F1D = 0F (00001111)
// 3F1E = 17 (00010111)
// 3F1F = 11 (00010001)
// 3F20 = 2B (00101011)


// Rendering

MARIO_DDR_LOOP void ppu_draw_background_scanline(bool mirror) {
  const int line=ppu.scanline,scroll=ppu.PPUSCROLL_X;
  const word name_base=ppu_base_nametable_address()+(mirror?0x400:0);
  const word pattern_base=ppu_background_pattern_table_address();
  const unsigned name_row=name_base+((line>>3)<<5);
  const unsigned attribute_row=name_base+0x3c0+(line>>5)*8;
  const unsigned attribute_shift=(line>>2)&4;
  byte *background=ppu_screen_background[line];
  byte *destination=fce_canvas_row((unsigned)(line+1));
  int tile_x;
  for (tile_x = ppu_shows_background_in_leftmost_8px() ? 0 : 1; tile_x < 32; tile_x ++) {
    // Skipping off-screen pixels
    if (((tile_x << 3) - scroll + (mirror ? 256 : 0)) > 256)
      continue;

    int tile_index = ppu_ram_read(name_row+tile_x);
    word tile_address = pattern_base + 16 * tile_index;

    int y_in_tile = line & 0x7;
    byte l = ppu_ram_read(tile_address + y_in_tile);
    byte h = ppu_ram_read(tile_address + y_in_tile + 8);
    if(!(l|h))continue;
    unsigned row=pattern_row(l,h);
    unsigned attribute=ppu_ram_read(attribute_row+(tile_x>>2));
    unsigned palette_address=0x3f00+(((attribute>>(attribute_shift|(tile_x&2)))&3)<<2);
    byte colors[4]={0,0,0,0};
    if(destination){colors[1]=ppu_ram_read(palette_address+1);colors[2]=ppu_ram_read(palette_address+2);colors[3]=ppu_ram_read(palette_address+3);}

    int x;
    for (x = 0; x < 8; x ++) {
      byte color = (row>>14)&3;row<<=2;

      // Color 0 is transparent
      if (color != 0) {
        background[(tile_x<<3)+x]=color;
        int screen_x=(tile_x<<3)+x-scroll+(mirror?256:0);
        if(destination&&(unsigned)screen_x<SCR_W)destination[screen_x]=colors[color];
      }
    }
  }
}

void ppu_draw_sprite_scanline() {
  int scanline_sprite_count = 0;
  int n;
  for (n = 0; n < 0x100; n += 4) {
    byte sprite_x = PPU_SPRRAM[n + 3];
    byte sprite_y = PPU_SPRRAM[n];

    // Skip if sprite not on scanline
    if (sprite_y > ppu.scanline || sprite_y + ppu_sprite_height() < ppu.scanline)
      continue;

    scanline_sprite_count++;

    // PPU can't render > 8 sprites
    if (scanline_sprite_count > 8) {
      ppu_set_sprite_overflow(true);
      // break;
    }

    bool vflip = PPU_SPRRAM[n + 2] & 0x80;
    bool hflip = PPU_SPRRAM[n + 2] & 0x40;

    word tile_address = ppu_sprite_pattern_table_address() + 16 * PPU_SPRRAM[n + 1];
    int y_in_tile = ppu.scanline & 0x7;
    byte l = ppu_ram_read(tile_address + (vflip ? (7 - y_in_tile) : y_in_tile));
    byte h = ppu_ram_read(tile_address + (vflip ? (7 - y_in_tile) : y_in_tile) + 8);
    unsigned row=pattern_row(l,h);

    byte palette_attribute = PPU_SPRRAM[n + 2] & 0x3;
    word palette_address = 0x3F10 + (palette_attribute << 2);
    int x;
    for (x = 0; x < 8; x ++) {
      int color = (row>>((hflip?x:7-x)*2))&3;

      // Color 0 is transparent
      if (color != 0) {
        int screen_x = sprite_x + x;
        int idx = ppu_ram_read(palette_address + color);

        // FIXME: we do not distinguish bbg and fg here to improve performance
        if (PPU_SPRRAM[n + 2] & 0x20) {
          draw(screen_x, sprite_y + y_in_tile + 1, idx); // bbg
        }
        else {
          draw(screen_x, sprite_y + y_in_tile + 1, idx); // fg
        }

        // Checking sprite 0 hit
        if (ppu_shows_background() && !ppu_sprite_hit_occured && n == 0 && ppu_screen_background[sprite_y + y_in_tile][screen_x] == color) {
          ppu_set_sprite_0_hit(true);
          ppu_sprite_hit_occured = true;
        }
      }
    }
  }
}

// PPU Lifecycle

void ppu_run(int cycles) {
  while (cycles-- > 0) { ppu_cycle(); }
}

static uint32_t background_time, sprite_time, cpu_time;
#ifdef PROFILE
#ifdef HAS_US_TIMER
# define TIMER_UNIT "us"
# define time_read(x) read_us(&x)
# define time_diff(t1, t0) us_timediff(&t1, &t0)
# define TIME_TYPE amtime
#else
# define TIMER_UNIT "ms"
# define time_read(x) x = uptime()
# define time_diff(t1, t0) (t1 - t0)
# define TIME_TYPE uint32_t
#endif
#else
# define time_read(x)
# define time_diff(t1, t0) 0
#endif

// [ARCH] 将一个扫描线周期拆成 CPU、背景、CPU、精灵、CPU 片段。
// [ARCH] 阶段采样使用 RV32 真实机器计数。
// [ARCH] 这些片段预算沿用原轻量引擎，不能宣称完整周期精确 NES。
void ppu_cycle() {
#ifdef PROFILE
  TIME_TYPE t0, t1, t2, t3, t4, t5;
#endif

  if (!ppu.ready && cpu_clock() > 29658)
    ppu.ready = true;

  time_read(t0);
  PROF_BEGIN(cpu0);
  cpu_run(256);
  PROF_END(cpu,cpu0);
  time_read(t1);

  ppu.scanline++;

  PROF_BEGIN(bg0);
  if (ppu.scanline < SCR_H && ppu_shows_background()) {
    ppu_draw_background_scanline(false);
    ppu_draw_background_scanline(true);
  }
  PROF_END(bg,bg0);

  time_read(t2);
  PROF_BEGIN(cpu1);
  cpu_run(85 - 16);
  PROF_END(cpu,cpu1);
  time_read(t3);

  PROF_BEGIN(spr0);
  if (ppu.scanline < SCR_H && ppu_shows_sprites()) {
    ppu_draw_sprite_scanline();
  }
  PROF_END(sprite,spr0);

  time_read(t4);
  PROF_BEGIN(cpu2);
  cpu_run(16);
  PROF_END(cpu,cpu2);
  time_read(t5);

  cpu_time += time_diff(t1, t0) + time_diff(t3, t2) + time_diff(t5, t4);
  background_time += time_diff(t2, t1);
  sprite_time += time_diff(t4, t3);

  // [ARCH] 进入模拟垂直消隐并处理 NMI。
  // [ARCH] 这是被模拟机的时序事件，不等于真实 HDMI 正在发生同一条扫描线。
  // [ARCH] 实体换帧由后续 GPU 适配与扫描控制器完成。
  if (ppu.scanline == 241) {
    ppu_set_in_vblank(true);
    ppu_set_sprite_0_hit(false);
    cpu_interrupt();
  }
  // [ARCH] 结束一帧时复位扫描线与相关状态，并调用最终画布输出。
  // [ARCH] FRAME_SKIP=0 时正常逐帧提交。
  // [ARCH] 真实发布确认稍后在板级双缓冲协议中完成。
  else if (ppu.scanline == 262) {
    ppu.scanline = -1;
    ppu_sprite_hit_occured = false;
    ppu_set_in_vblank(false);

    time_read(t0);
    fce_update_screen();
    time_read(t1);

#ifdef PROFILE
    uint32_t total = cpu_time + background_time + sprite_time + time_diff(t1, t0);
    printf("Time: cpu + bg + spr + scr = (%d + %d + %d + %d)\t= %d %s\n",
        cpu_time, background_time, sprite_time, time_diff(t1, t0), total, TIMER_UNIT);
#endif
    cpu_time = 0;
    background_time = 0;
    sprite_time = 0;
  }
}

void ppu_copy(word address, byte *source, int length) {
  memcpy(&PPU_RAM[address], source, length);
}

// [ARCH] 模拟 PPU 寄存器读取可能清 vblank、锁存或推进地址。
// [ARCH] 相同地址连续读取不一定返回同一状态。
// [ARCH] 与普通 RAM 访问相比，不能随意缓存或合并。
byte ppuio_read(word address) {
  ppu.PPUADDR &= 0x3FFF;
  switch (address & 7) {
    case 2:
      {
        byte value = ppu.PPUSTATUS;
        ppu_set_in_vblank(false);
        ppu_set_sprite_0_hit(false);
        ppu.scroll_received_x = 0;
        ppu.PPUSCROLL = 0;
        ppu.addr_received_high_byte = 0;
        ppu_latch = value;
        ppu_addr_latch = 0;
        ppu_2007_first_read = true;
        return value;
      }
    case 4: return ppu_latch = PPU_SPRRAM[ppu.OAMADDR];
    case 7:
      {
        byte data;

        if (ppu.PPUADDR < 0x3F00) {
          data = ppu_latch = ppu_ram_read(ppu.PPUADDR);
        }
        else {
          data = ppu_ram_read(ppu.PPUADDR);
          ppu_latch = 0;
        }

        if (ppu_2007_first_read) {
          ppu_2007_first_read = false;
        }
        else {
          ppu.PPUADDR += ppu_vram_address_increment();
        }
        return data;
      }
    default: return 0xFF;
  }
}

// [ARCH] PPU 地址和滚动寄存器分次接收字节，并维护相位状态。
// [ARCH] 写入数据与地址推进遵循此实现的原来路径。
// [ARCH] 这些都是 NES 虚拟寄存器，不直接访问 FPGA MMIO。
void ppuio_write(word address, byte data) {
  address &= 7;
  ppu_latch = data;
  ppu.PPUADDR &= 0x3FFF;
  switch(address) {
    case 0: if (ppu.ready) ppu.PPUCTRL = data; break;
    case 1: if (ppu.ready) ppu.PPUMASK = data; break;
    case 3: ppu.OAMADDR = data; break;
    case 4: PPU_SPRRAM[ppu.OAMADDR++] = data; break;
    case 5:
            {
              if (ppu.scroll_received_x)
                ppu.PPUSCROLL_Y = data;
              else
                ppu.PPUSCROLL_X = data;

              ppu.scroll_received_x ^= 1;
              break;
            }
    case 6:
            {
              if (!ppu.ready)
                return;

              if (ppu.addr_received_high_byte)
                ppu.PPUADDR = (ppu_addr_latch << 8) + data;
              else
                ppu_addr_latch = data;

              ppu.addr_received_high_byte ^= 1;
              ppu_2007_first_read = true;
              break;
            }
    case 7:
            {
              if (ppu.PPUADDR > 0x1FFF || ppu.PPUADDR < 0x4000) {
                ppu_ram_write(ppu.PPUADDR ^ ppu.mirroring_xor, data);
                ppu_ram_write(ppu.PPUADDR, data);
              }
              else {
                ppu_ram_write(ppu.PPUADDR, data);
              }
            }
  }
  ppu_latch = data;
}

// [ARCH] 建立图形寄存器初值与位平面小表。
// [ARCH] 预计算只改变宿主实现的工作量，不改变 ROM 中图案数据。
// [ARCH] 此后扫描线绘制共享该表。
void ppu_init() {
  ppu.PPUCTRL = ppu.PPUMASK = ppu.PPUSTATUS = ppu.OAMADDR = ppu.PPUSCROLL_X = ppu.PPUSCROLL_Y = ppu.PPUADDR = 0;
  ppu.PPUSTATUS |= 0xA0;
  ppu.PPUDATA = 0;
  ppu_2007_first_read = true;

  for (unsigned value = 0; value < 256; value++)
    for (unsigned bit = 0; bit < 8; bit++)
      ppu_pattern_bits[value] |= ((value >> bit) & 1) << (bit*2);
}

void ppu_sprram_write(byte data) {
  PPU_SPRRAM[ppu.OAMADDR++] = data;
}

void ppu_set_background_color(byte color) {
}

void ppu_set_mirroring(byte mirroring) {
  ppu.mirroring = mirroring;
  ppu.mirroring_xor = 0x400 << mirroring;
}

