#include "preprocess_rgb565.h"

static uint16_t pixel_at(const volatile uint8_t *source, uint32_t byte_offset) {
    return (uint16_t)source[byte_offset] | (uint16_t)((uint16_t)source[byte_offset+1u] << 8);
}

static uint8_t red(uint16_t pixel) {
    uint8_t v=(uint8_t)((pixel >> 11) & 31u);
    return (uint8_t)((v << 3) | (v >> 2));
}
static uint8_t green(uint16_t pixel) {
    uint8_t v=(uint8_t)((pixel >> 5) & 63u);
    return (uint8_t)((v << 2) | (v >> 4));
}
static uint8_t blue(uint16_t pixel) {
    uint8_t v=(uint8_t)(pixel & 31u);
    return (uint8_t)((v << 3) | (v >> 2));
}

void soc_preprocess_rgb565(const volatile uint8_t *source,
                            volatile uint8_t *destination) {
    for(uint32_t y=0;y<SOC_TENSOR_HEIGHT;y++) {
        uint32_t output_row=y*SOC_TENSOR_WIDTH*3u;
        if(y<140u || y>=500u) {
            for(uint32_t x=0;x<SOC_TENSOR_WIDTH*3u;x++)
                destination[output_row+x]=114u;
            continue;
        }
        uint32_t input_row=(y-140u)*2u*SOC_FRAME_WIDTH*2u;
        for(uint32_t x=0;x<SOC_TENSOR_WIDTH;x++) {
            uint32_t offset=input_row+x*4u;
            uint16_t p00=pixel_at(source,offset);
            uint16_t p01=pixel_at(source,offset+2u);
            uint16_t p10=pixel_at(source,offset+SOC_FRAME_WIDTH*2u);
            uint16_t p11=pixel_at(source,offset+SOC_FRAME_WIDTH*2u+2u);
            uint32_t target=output_row+x*3u;
            destination[target]=(uint8_t)((red(p00)+red(p01)+red(p10)+red(p11)+2u)>>2);
            destination[target+1u]=(uint8_t)((green(p00)+green(p01)+green(p10)+green(p11)+2u)>>2);
            destination[target+2u]=(uint8_t)((blue(p00)+blue(p01)+blue(p10)+blue(p11)+2u)>>2);
        }
    }
}
