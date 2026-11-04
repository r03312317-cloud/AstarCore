#include "preprocess5mp_v2.h"

static uint16_t pixel_at(const volatile uint8_t *source, uint32_t offset) {
    return (uint16_t)source[offset] | (uint16_t)((uint16_t)source[offset + 1u] << 8);
}

static uint8_t channel(uint16_t pixel, uint32_t which) {
    if (which == 0u) {
        uint32_t v = (pixel >> 11) & 31u;
        return (uint8_t)((v << 3) | (v >> 2));
    }
    if (which == 1u) {
        uint32_t v = (pixel >> 5) & 63u;
        return (uint8_t)((v << 2) | (v >> 4));
    }
    uint32_t v = pixel & 31u;
    return (uint8_t)((v << 3) | (v >> 2));
}

uint32_t soc_preprocess5mp_rgb565_v2(const volatile uint8_t *source,
                                        uint32_t source_bytes, uint32_t source_stride,
                                        volatile int8_t *destination,
                                        uint32_t destination_bytes,
                                        const int8_t rgb8_to_i8[256]) {
    if (!source || !destination || !rgb8_to_i8 ||
        source_stride < SOC_V2_SOURCE_ROW_BYTES || (source_stride & 1u) ||
        (uint64_t)source_stride * SOC_V2_SOURCE_H > source_bytes ||
        destination_bytes < SOC_V2_OUTPUT_BYTES) return SOC_V2_BAD_LAYOUT;
    const int8_t pad = rgb8_to_i8[114];
    for (uint32_t y = 0; y < SOC_V2_MODEL_H; ++y) {
        uint32_t dest_row = y * SOC_V2_MODEL_W * 3u;
        if (y < SOC_V2_ACTIVE_TOP || y >= SOC_V2_ACTIVE_TOP + SOC_V2_ACTIVE_H) {
            for (uint32_t i = 0; i < SOC_V2_MODEL_W * 3u; ++i)
                destination[dest_row + i] = pad;
            continue;
        }
        uint32_t sy_num = 162u * (y - SOC_V2_ACTIVE_TOP) + 71u;
        uint32_t y0 = sy_num / 20u, b = sy_num % 20u;
        uint32_t row0 = y0 * source_stride, row1 = (y0 + 1u) * source_stride;
        for (uint32_t x = 0; x < SOC_V2_MODEL_W; ++x) {
            uint32_t sx_num = 162u * x + 71u;
            uint32_t x0 = sx_num / 20u, a = sx_num % 20u;
            uint32_t column = 2u * x0;
            uint16_t p00 = pixel_at(source, row0 + column);
            uint16_t p01 = pixel_at(source, row0 + column + 2u);
            uint16_t p10 = pixel_at(source, row1 + column);
            uint16_t p11 = pixel_at(source, row1 + column + 2u);
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
    return SOC_V2_OK;
}
