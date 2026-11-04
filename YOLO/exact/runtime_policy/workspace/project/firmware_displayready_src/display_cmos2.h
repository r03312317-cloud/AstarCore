#ifndef SOC_DISPLAY_CMOS2_H
#define SOC_DISPLAY_CMOS2_H
#include <stdint.h>
#define SOC_CMOS2_DISPLAY_BYTES (680u*340u*2u)
/* RGB565 source 1280x720; target 680x340; source center
 * sx=floor((32*x+16)/17), sy=floor((36*y+18)/17).
 * Compact coordinates map to the 720x480 carrier at offset (20,70). */
void soc_display_resize_cmos2(const volatile uint8_t *,volatile uint16_t *);
void soc_display_map_cmos2(const uint32_t q16[4],uint32_t compact_xy[2]);
#endif
