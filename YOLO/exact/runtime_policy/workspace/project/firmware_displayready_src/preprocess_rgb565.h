#ifndef SOC_PREPROCESS_RGB565_H
#define SOC_PREPROCESS_RGB565_H

#include <stdint.h>

/* v1 input contract: little-endian RGB565 1280x720, high camera byte first.
 * Output: RGB888 HWC 640x640. Two-by-two bilinear half-scale and centered
 * 140-row letterbox with RGB=(114,114,114). The model importer must use this
 * exact transform when calibrating/validating its input tensor.
 */
#define SOC_FRAME_WIDTH 1280u
#define SOC_FRAME_HEIGHT 720u
#define SOC_FRAME_BYTES (SOC_FRAME_WIDTH*SOC_FRAME_HEIGHT*2u)
#define SOC_TENSOR_WIDTH 640u
#define SOC_TENSOR_HEIGHT 640u
#define SOC_TENSOR_BYTES (SOC_TENSOR_WIDTH*SOC_TENSOR_HEIGHT*3u)
#define SOC_PREPROCESS_ID 0x4c423634u /* "LB64" */

void soc_preprocess_rgb565(const volatile uint8_t *source,
                            volatile uint8_t *destination);

#endif
