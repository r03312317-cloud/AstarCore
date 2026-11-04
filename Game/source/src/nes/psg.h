// [ARCH] 手柄事件与模拟 I/O 接口，当前不产生实体音频。
// [ARCH] AM 到 NES 键位由 input.c 与 psg.c 配合完成。
#ifndef PSG_H
#define PSG_H

#include "common.h"

#define KEY_A       J
#define KEY_B       K
#define KEY_SELECT  U
#define KEY_START   I
#define KEY_UP      W
#define KEY_DOWN    S
#define KEY_LEFT    A
#define KEY_RIGHT   D

byte psgio_read(word address);
void psgio_write(word address, byte data);
void psg_init();
void psg_detect_key();

#endif

