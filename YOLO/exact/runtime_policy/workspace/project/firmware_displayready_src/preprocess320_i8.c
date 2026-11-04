#include "preprocess320_i8.h"

static uint16_t pixel_at(const volatile uint8_t *source, uint32_t offset) {
    return (uint16_t)source[offset] |
           (uint16_t)((uint16_t)source[offset + 1u] << 8);
}

static uint8_t red8(uint16_t pixel) {
    uint8_t v = (uint8_t)((pixel >> 11) & 31u);
    return (uint8_t)((v << 3) | (v >> 2));
}

static uint8_t green8(uint16_t pixel) {
    uint8_t v = (uint8_t)((pixel >> 5) & 63u);
    return (uint8_t)((v << 2) | (v >> 4));
}

static uint8_t blue8(uint16_t pixel) {
    uint8_t v = (uint8_t)(pixel & 31u);
    return (uint8_t)((v << 3) | (v >> 2));
}

#if defined(__GNUC__) && (__BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__)
/* DDR is normal byte-addressable storage. GCC may_alias keeps these wider
 * volatile accesses legal even when the caller's buffer has byte type.
 * Runtime alignment guards below retain the original path for other inputs.
 */
typedef uint16_t soc_pp_alias16 __attribute__((__may_alias__));
typedef uint32_t soc_pp_alias32 __attribute__((__may_alias__));

static inline __attribute__((always_inline)) uint32_t quantized_four_sample_pixel(
        const volatile soc_pp_alias16 *source, uint32_t pixel_offset,
        const int8_t table[256]) {
    const uint16_t a=source[pixel_offset],b=source[pixel_offset+1u];
    const uint16_t c=source[pixel_offset+SOC_PP320_SOURCE_WIDTH];
    const uint16_t d=source[pixel_offset+SOC_PP320_SOURCE_WIDTH+1u];
    const uint8_t r=(uint8_t)((red8(a)+red8(b)+red8(c)+red8(d)+2u)>>2);
    const uint8_t g=(uint8_t)((green8(a)+green8(b)+green8(c)+green8(d)+2u)>>2);
    const uint8_t bl=(uint8_t)((blue8(a)+blue8(b)+blue8(c)+blue8(d)+2u)>>2);
    return (uint32_t)(uint8_t)table[r] |
           ((uint32_t)(uint8_t)table[g]<<8) |
           ((uint32_t)(uint8_t)table[bl]<<16);
}

static void preprocess_aligned(const volatile uint8_t *source,
        volatile int8_t *destination,const int8_t table[256]) {
    const volatile soc_pp_alias16 *pixels=(const volatile soc_pp_alias16 *)(const volatile void *)source;
    volatile soc_pp_alias32 *words=(volatile soc_pp_alias32 *)(volatile void *)destination;
    const uint32_t row_words=SOC_PP320_TARGET_WIDTH*3u/4u;
    const uint32_t p=(uint8_t)table[114];
    const uint32_t pad=p|(p<<8)|(p<<16)|(p<<24);
    for(uint32_t y=0;y<SOC_PP320_TARGET_HEIGHT;++y) {
        volatile soc_pp_alias32 *out=words+y*row_words;
        if(y<SOC_PP320_ACTIVE_TOP||y>=SOC_PP320_ACTIVE_TOP+SOC_PP320_ACTIVE_HEIGHT) {
            for(uint32_t i=0;i<row_words;++i)out[i]=pad;
        } else {
            const uint32_t row=(4u*(y-SOC_PP320_ACTIVE_TOP)+1u)*SOC_PP320_SOURCE_WIDTH+1u;
            for(uint32_t x=0;x<SOC_PP320_TARGET_WIDTH;x+=4u) {
                const uint32_t offset=row+4u*x;
                const uint32_t a=quantized_four_sample_pixel(pixels,offset,table);
                const uint32_t b=quantized_four_sample_pixel(pixels,offset+4u,table);
                /* Commit each word as soon as both contributing pixels are
                 * ready. Keeping four expanded samples alive at once causes
                 * large spill traffic on RV32 despite fewer image accesses.
                 */
                out[0]=a|(b<<24);
                const uint32_t c=quantized_four_sample_pixel(pixels,offset+8u,table);
                out[1]=(b>>8)|(c<<16);
                const uint32_t d=quantized_four_sample_pixel(pixels,offset+12u,table);
                out[2]=(c>>16)|(d<<8);
                out+=3;
            }
        }
    }
}
#endif

void soc_preprocess_rgb565_320_i8(const volatile uint8_t *source,
                                    volatile int8_t *destination,
                                    const int8_t rgb8_to_i8[256]) {
#if defined(__GNUC__) && (__BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__)
    if((((uintptr_t)source&1u)==0u)&&(((uintptr_t)destination&3u)==0u)&&
       (SOC_PP320_TARGET_WIDTH%4u==0u)) {
        preprocess_aligned(source,destination,rgb8_to_i8);
        return;
    }
#endif
    const uint32_t row_bytes = SOC_PP320_TARGET_WIDTH * 3u;
    const uint32_t source_row_bytes = SOC_PP320_SOURCE_WIDTH * 2u;
    const int8_t pad = rgb8_to_i8[114];

    for (uint32_t y = 0; y < SOC_PP320_TARGET_HEIGHT; ++y) {
        uint32_t target_row = y * row_bytes;
        if (y < SOC_PP320_ACTIVE_TOP ||
            y >= SOC_PP320_ACTIVE_TOP + SOC_PP320_ACTIVE_HEIGHT) {
            for (uint32_t i = 0; i < row_bytes; ++i) {
                destination[target_row + i] = pad;
            }
            continue;
        }

        /* OpenCV INTER_LINEAR at exact 4:1 scale samples source coordinates
         * 4*x+1.5, 4*y+1.5. Each expanded RGB8 channel is the nearest
         * integer to the average of the four surrounding source samples.
         */
        uint32_t source_row = (4u * (y - SOC_PP320_ACTIVE_TOP) + 1u) * source_row_bytes;
        for (uint32_t x = 0; x < SOC_PP320_TARGET_WIDTH; ++x) {
            uint32_t offset = source_row + (4u * x + 1u) * 2u;
            uint16_t p00 = pixel_at(source, offset);
            uint16_t p01 = pixel_at(source, offset + 2u);
            uint16_t p10 = pixel_at(source, offset + source_row_bytes);
            uint16_t p11 = pixel_at(source, offset + source_row_bytes + 2u);
            uint32_t target = target_row + 3u * x;
            uint8_t r = (uint8_t)((red8(p00) + red8(p01) + red8(p10) + red8(p11) + 2u) >> 2);
            uint8_t g = (uint8_t)((green8(p00) + green8(p01) + green8(p10) + green8(p11) + 2u) >> 2);
            uint8_t b = (uint8_t)((blue8(p00) + blue8(p01) + blue8(p10) + blue8(p11) + 2u) >> 2);
            destination[target] = rgb8_to_i8[r];
            destination[target + 1u] = rgb8_to_i8[g];
            destination[target + 2u] = rgb8_to_i8[b];
        }
    }
}
