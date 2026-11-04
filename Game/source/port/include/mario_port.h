// [ARCH] 连接引擎与板级的启动、单帧、状态和缩放接口。
// [ARCH] 模拟帧数与已确认发布数必须分开统计。
// [ARCH] 调用者负责目标缓冲所有权，render 只负责写入图像。
#ifndef MARIO_PORT_H
#define MARIO_PORT_H
#include "am.h"
int mario_boot(void);
void mario_step(void);
unsigned mario_frame(void);
uint32_t mario_state_crc(void);
unsigned mario_present_count(void);
AM_INPUT_KEYBRD_T mario_input_event(uint8_t raw);
void mario_render(const uint8_t *pixels,volatile uint16_t *destination);
#endif
