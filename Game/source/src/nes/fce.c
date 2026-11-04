// [ARCH] 管理 ROM 布局、6502/PPU 初始化与画布输出。
// [ARCH] mapper 实际准入还受 mario_boot 的严格检查。
// [ARCH] 画布用 8 位索引，PPU 已解析每像素调色板变化。
// [ARCH] 64 项调色板预计算为双 RGB565 像素值。
// [ARCH] 初始化用黑色索引 13，不能把索引 0 直接等同于 RGB 零。
// [ARCH] FRAME_SKIP=0 取消隔帧输出，不代表实板达到 60 FPS。
// [ARCH] fce_canvas_row 使背景扫描行直接访问有效画布。
// [ARCH] 输出后清理画布，避免透明区域继承旧像素。
// [ARCH] 历史 fce_run 保留，实际逐帧入口由 port/runtime.c 调度。
#include "fce.h"
#include "cpu.h"
#include "memory.h"
#include "ppu.h"
#include "psg.h"
#include <klib.h>
#include "mario_profile.h"

static int frame_cnt;
static inline bool candraw() { return frame_cnt % (1 + FRAME_SKIP) == 0; }

/* Store immutable NES palette indices, preserving per-pixel palette changes
 * already resolved by the PPU. Each published color is still RGB565. */
static _Alignas(4) uint8_t canvas[SCR_W * SCR_H];
uint32_t fce_palette565_dual[64];
uint8_t *fce_canvas_row(unsigned y) {
  return y<SCR_H&&candraw()?canvas+y*SCR_W:NULL;
}

void draw(int x, int y, int idx) {
  if (x >= 0 && x < SCR_W && y >= 0 && y < SCR_H && candraw()) {
    canvas[y * SCR_W + x] = (uint8_t)idx;
  }
}

typedef struct {
  char signature[4];
  byte prg_block_count;
  byte chr_block_count;
  word rom_type;
  byte reserved[8];
} ines_header;

static byte *buf;
static ines_header *fce_rom_header;

byte *romread(int size) {
  byte *ret = buf;
  buf += size;
  return ret;
}

// [ARCH] 按 iNES 头字段切分 PRG/CHR。
// [ARCH] 头解析中的保留 mapper 路径不代表实际入口全部准入。
// [ARCH] mario_boot 另外限定本演示的具体 ROM 配置。
int fce_load_rom(char *rom) {
  buf = (byte*)rom;
  fce_rom_header = (ines_header*)romread(sizeof(ines_header));

  if (memcmp(fce_rom_header->signature, "NES\x1A", 4)) {
    return -1;
  }

  mmc_id = ((fce_rom_header->rom_type & 0xF0) >> 4);

  int prg_size = fce_rom_header->prg_block_count * 0x4000;

  byte *blk = romread(prg_size);

  if (mmc_id == 0 || mmc_id == 3) {
    // if there is only one PRG block, we must repeat it twice
    if (fce_rom_header->prg_block_count == 1) {
      mmc_copy(0x8000, blk, 0x4000);
      mmc_copy(0xC000, blk, 0x4000);
    }
    else {
      mmc_copy(0x8000, blk, 0x8000);
    }
  }
  else {
    return -1;
  }

  // Copying CHR pages into MMC and PPU
  int i;
  for (i = 0; i < fce_rom_header->chr_block_count; i++) {
    byte *blk = romread(0x2000);
    mmc_append_chr_rom_page(blk);

    if (i == 0) {
      ppu_copy(0x0000, blk, 0x2000);
    }
  }

  return 0;
}

// [ARCH] 生成双像素 RGB565 查表并设置初始黑色索引。
// [ARCH] 随后建立模拟 CPU/PPU 状态与镜像方式。
// [ARCH] 初始画布内容与非零目标缓冲测试共同约束首帧正确性。
void fce_init() {
  for (unsigned i=0;i<64;i++) {
    uint32_t c=palette[i],p=((c>>8)&0xf800)|((c>>5)&0x07e0)|((c>>3)&31);
    fce_palette565_dual[i]=p|(p<<16);
  }
  /* The original zeroed RGB canvas is black before its first clear. */
  memset(canvas,13,sizeof(canvas));
  cpu_init();
  ppu_init();
  ppu_set_mirroring(fce_rom_header->rom_type & 1);
  cpu_reset();
}

static int gtime;

static inline int uptime_ms() {
  return io_read(AM_TIMER_UPTIME).us / 1000;
}

void wait_for_frame() {
  int cur = uptime_ms();
  while (cur - gtime < 1000 / FPS) {
    cur = uptime_ms();
  }
  gtime = cur;
}

// FCE Lifecycle
static MARIO_DDR_LOOP void clear_canvas(uint32_t value) {
  uint32_t *words=(uint32_t *)(void *)canvas;
  for (int i=0;i<SCR_W*SCR_H/4;i++)words[i]=value;
}

void fce_run() {
  gtime = uptime_ms();
  int nr_draw = 0;
  uint32_t last = gtime;
  while(1) {
    wait_for_frame();
    int scanlines = 262;

    while (scanlines-- > 0) {
      ppu_cycle();
      psg_detect_key();
    }

    nr_draw ++;
    int upt = uptime_ms();
    if (upt - last > 1000) {
      last = upt;
      for (int i = 0; i < 80; i++) putch('\b');
      printf("(System time: %ds) FPS = %d.", upt / 1000, nr_draw);
      nr_draw = 0;
    }
  }
}

void fce_update_screen() {
  frame_cnt++;
  if (!candraw()) return;

  int idx = ppu_ram_read(0x3F00);
  uint32_t bgc = (uint32_t)(uint8_t)idx*0x01010101u;

  AM_GPU_CONFIG_T cfg = io_read(AM_GPU_CONFIG);
  int xpad = (cfg.width  - SCR_W) / 2;
  int ypad = (cfg.height - SCR_H) / 2;
  panic_on(xpad < 0 || ypad < 0, "screen too small");

  io_write(AM_GPU_FBDRAW, xpad, ypad, canvas, SCR_W, SCR_H, true);

  PROF_BEGIN(clear0);
  clear_canvas(bgc);
  PROF_END(clear,clear0);
}

