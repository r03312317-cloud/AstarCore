// 架构导读：preprocess5mp_v2。
// 保留的图像预处理软件/硬件兼容接口。
#include "preprocess5mp_v2.h"

// 服务函数 pixel_at。
// 接口参数：const volatile uint8_t *source, uint32_t offset；返回值及副作用由下列函数体定义。
// 参数入口：source, offset；类型、指针限定及返回约定沿用下列声明。
static uint16_t pixel_at(const volatile uint8_t *source, uint32_t offset) {
    // 返回当前检查/运算结果 (uint16_t)source[offset] | (uint16_t)((uint16_t)source[offset + 1u] << 8)，由调用者解释其状态或数值。
    return (uint16_t)source[offset] | (uint16_t)((uint16_t)source[offset + 1u] << 8);
}

// 服务函数 channel。
// 接口参数：uint16_t pixel, uint32_t which；返回值及副作用由下列函数体定义。
// 参数入口：pixel, which；类型、指针限定及返回约定沿用下列声明。
static uint8_t channel(uint16_t pixel, uint32_t which) {
    // 控制边界：which == 0u；仅在该条件成立时进入本分支。
    if (which == 0u) {
        uint32_t v = (pixel >> 11) & 31u;
        // 返回当前检查/运算结果 (uint8_t)((v << 3) | (v >> 2))，由调用者解释其状态或数值。
        return (uint8_t)((v << 3) | (v >> 2));
    }
    // 控制边界：which == 1u；仅在该条件成立时进入本分支。
    if (which == 1u) {
        uint32_t v = (pixel >> 5) & 63u;
        // 返回当前检查/运算结果 (uint8_t)((v << 2) | (v >> 4))，由调用者解释其状态或数值。
        return (uint8_t)((v << 2) | (v >> 4));
    }
    uint32_t v = pixel & 31u;
    // 返回当前检查/运算结果 (uint8_t)((v << 3) | (v >> 2))，由调用者解释其状态或数值。
    return (uint8_t)((v << 3) | (v >> 2));
}

// 服务函数 soc_preprocess5mp_rgb565_v2。
// 接口参数：const volatile uint8_t *source,；返回值及副作用由下列函数体定义。
// 参数入口：source, source_bytes, source_stride, destination, destination_bytes, rgb8_to_i8；类型、指针限定及返回约定沿用下列声明。
uint32_t soc_preprocess5mp_rgb565_v2(const volatile uint8_t *source,
                                        uint32_t source_bytes, uint32_t source_stride,
                                        volatile int8_t *destination,
                                        uint32_t destination_bytes,
                                        const int8_t rgb8_to_i8[256]) {
    // 控制边界：!source || !destination || !rgb8_to_i8 ||；仅在该条件成立时进入本分支。
    if (!source || !destination || !rgb8_to_i8 ||
        source_stride < SOC_V2_SOURCE_ROW_BYTES || (source_stride & 1u) ||
        (uint64_t)source_stride * SOC_V2_SOURCE_H > source_bytes ||
        destination_bytes < SOC_V2_OUTPUT_BYTES) return SOC_V2_BAD_LAYOUT;
    const int8_t pad = rgb8_to_i8[114];
    // 迭代边界：uint32_t y = 0; y < SOC_V2_MODEL_H; ++y；地址和计数随循环体中的原始更新前进。
    for (uint32_t y = 0; y < SOC_V2_MODEL_H; ++y) {
        uint32_t dest_row = y * SOC_V2_MODEL_W * 3u;
        // 控制边界：y < SOC_V2_ACTIVE_TOP || y >= SOC_V2_ACTIVE_TOP + SOC_V2_ACTIVE_H；仅在该条件成立时进入本分支。
        if (y < SOC_V2_ACTIVE_TOP || y >= SOC_V2_ACTIVE_TOP + SOC_V2_ACTIVE_H) {
            // 迭代边界：uint32_t i = 0; i < SOC_V2_MODEL_W * 3u; ++i；地址和计数随循环体中的原始更新前进。
            for (uint32_t i = 0; i < SOC_V2_MODEL_W * 3u; ++i)
                destination[dest_row + i] = pad;
            continue;
        }
        uint32_t sy_num = 162u * (y - SOC_V2_ACTIVE_TOP) + 71u;
        uint32_t y0 = sy_num / 20u, b = sy_num % 20u;
        uint32_t row0 = y0 * source_stride, row1 = (y0 + 1u) * source_stride;
        // 迭代边界：uint32_t x = 0; x < SOC_V2_MODEL_W; ++x；地址和计数随循环体中的原始更新前进。
        for (uint32_t x = 0; x < SOC_V2_MODEL_W; ++x) {
            uint32_t sx_num = 162u * x + 71u;
            uint32_t x0 = sx_num / 20u, a = sx_num % 20u;
            uint32_t column = 2u * x0;
            uint16_t p00 = pixel_at(source, row0 + column);
            uint16_t p01 = pixel_at(source, row0 + column + 2u);
            uint16_t p10 = pixel_at(source, row1 + column);
            uint16_t p11 = pixel_at(source, row1 + column + 2u);
            // 迭代边界：uint32_t c = 0; c < 3u; ++c；地址和计数随循环体中的原始更新前进。
            for (uint32_t c = 0; c < 3u; ++c) {
                uint32_t weighted = (20u - a) * (20u - b) * channel(p00, c) +
                                    a * (20u - b) * channel(p01, c) +
                                    (20u - a) * b * channel(p10, c) +
                                    a * b * channel(p11, c);
                uint32_t rgb8 = (weighted + 200u) / 400u;
                destination[dest_row + x * 3u + c] = rgb8_to_i8[rgb8];
            }
        }
    }
    // 返回当前检查/运算结果 SOC_V2_OK，由调用者解释其状态或数值。
    return SOC_V2_OK;
}
