#ifndef SOC_DISPLAY_RESIZE_H
#define SOC_DISPLAY_RESIZE_H
#include <stdint.h>
#define SOC_DISPLAY_BYTES (640u*480u*2u)
/* Matches S2 soc_display_downscale_5mp: pixel-center nearest, RGB565LE. */
void soc_display_resize5mp(const volatile uint8_t *source,
                            volatile uint16_t *destination);
void soc_display_map_box(const uint32_t model_q16[4],uint32_t display_xy[2]);
#endif
