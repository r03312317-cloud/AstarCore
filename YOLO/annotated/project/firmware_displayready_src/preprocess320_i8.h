#ifndef SOC_REAL_MODEL_PREPROCESS320_I8_H
#define SOC_REAL_MODEL_PREPROCESS320_I8_H

#include <stdint.h>

/* OV5640 DDR frame: RGB565 pixels, little-endian bytes, 1280 x 720. */
#define SOC_PP320_SOURCE_WIDTH 1280u
#define SOC_PP320_SOURCE_HEIGHT 720u
#define SOC_PP320_SOURCE_BYTES 1843200u

/* YOLOv5 fixed-square input: RGB, HWC, signed INT8, 320 x 320. */
#define SOC_PP320_TARGET_WIDTH 320u
#define SOC_PP320_TARGET_HEIGHT 320u
#define SOC_PP320_TARGET_BYTES 307200u
#define SOC_PP320_ACTIVE_TOP 70u
#define SOC_PP320_ACTIVE_HEIGHT 180u

/* Every output RGB8 value is converted through rgb8_to_i8. Generate this
 * table from the model's input scale and zero point; use the same table
 * for letterbox value 114. Source and destination ranges must not overlap.
 * This function does not capture a frame or start NPU inference.
 */
void soc_preprocess_rgb565_320_i8(const volatile uint8_t *source,
                                    volatile int8_t *destination,
                                    const int8_t rgb8_to_i8[256]);

#endif
