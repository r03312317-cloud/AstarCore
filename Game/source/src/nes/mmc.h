// [ARCH] ROM 映射接口的实际 mapper 准入由 mario_boot 限制。
// [ARCH] PRG/CHR 的地址属于 NES 布局。
#include "common.h"

extern byte mmc_id;

byte mmc_read(word address);
void mmc_write(word address, byte data);
void mmc_copy(word address, byte *source, int length);
void mmc_append_chr_rom_page(byte *source);

