// 架构导读：preprocess5mp_v2。
// 保留的图像预处理软件/硬件兼容接口。
#ifndef SOC_VISION5MP_PREPROCESS_V2_H
#define SOC_VISION5MP_PREPROCESS_V2_H

#include <stdint.h>

/* New V2 contract. Keep the stage170 1280x720 V1 files unchanged. */
#define SOC_V2_SOURCE_W 2592u
#define SOC_V2_SOURCE_H 1944u
#define SOC_V2_SOURCE_ROW_BYTES 5184u
#define SOC_V2_SOURCE_BYTES 10077696u
#define SOC_V2_MODEL_W 320u
#define SOC_V2_MODEL_H 320u
#define SOC_V2_ACTIVE_TOP 40u
#define SOC_V2_ACTIVE_H 240u
#define SOC_V2_OUTPUT_BYTES 307200u

// 数据布局定义：enum { SOC_V2_OK = 0, SOC_V2_BAD_LAYOUT = 1 };；字段顺序与本文件使用它的接口保持一致。
enum { SOC_V2_OK = 0, SOC_V2_BAD_LAYOUT = 1 };

/* RGB565LE source with an explicit even row stride. The 256-byte LUT maps
 * expanded RGB8 to signed INT8; pad RGB8=114 is mapped through the same LUT.
 * All output bytes are written only after the layout check succeeds.
 */
uint32_t soc_preprocess5mp_rgb565_v2(const volatile uint8_t *source,
                                        uint32_t source_bytes, uint32_t source_stride,
                                        volatile int8_t *destination,
                                        uint32_t destination_bytes,
                                        const int8_t rgb8_to_i8[256]);

#endif
