#ifndef SOC_DISPLAY_H
#define SOC_DISPLAY_H
#include <stdint.h>
void soc_scale_rgb565(const uint16_t *src,unsigned w,unsigned h,unsigned pitch_pixels,volatile uint16_t *dst);
typedef struct {uint8_t previous,escape;uint32_t pressed_at;} soc_input_t;
/* Keys 1..4: up/down/left/right; 5: enter; 6: escape. */
typedef void (*soc_key_event)(unsigned key,int down,void *opaque);
void soc_input_update(soc_input_t *s,uint8_t buttons,uint32_t now,soc_key_event emit,void *opaque);
#endif
