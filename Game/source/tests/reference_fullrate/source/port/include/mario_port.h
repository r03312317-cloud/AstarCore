#ifndef MARIO_PORT_H
#define MARIO_PORT_H
#include "am.h"
int mario_boot(void);
void mario_step(void);
unsigned mario_frame(void);
uint32_t mario_state_crc(void);
AM_INPUT_KEYBRD_T mario_input_event(uint8_t raw);
void mario_render(const uint32_t *pixels,volatile uint16_t *destination);
#endif
