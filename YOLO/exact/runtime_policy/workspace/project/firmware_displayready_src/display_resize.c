#include "display_resize.h"
void soc_display_resize5mp(const volatile uint8_t *source,
                            volatile uint16_t *destination) {
    for(uint32_t y=0;y<480u;y++) {
        uint32_t sy=((2u*y+1u)*81u)/40u;
        for(uint32_t x=0;x<640u;x++) {
            uint32_t sx=((2u*x+1u)*81u)/40u;
            uint32_t offset=(sy*2592u+sx)*2u;
            destination[y*640u+x]=(uint16_t)source[offset]|
                (uint16_t)((uint16_t)source[offset+1u]<<8);
        }
    }
}
void soc_display_map_box(const uint32_t q[4],uint32_t xy[2]) {
    uint32_t x1=q[0]>320u*65536u?320u*65536u:q[0];
    uint32_t x2=q[2]>320u*65536u?320u*65536u:q[2];
    uint32_t y1=q[1]>40u*65536u?q[1]-40u*65536u:0u;
    uint32_t y2=q[3]>40u*65536u?q[3]-40u*65536u:0u;
    if(y1>240u*65536u)y1=240u*65536u;
    if(y2>240u*65536u)y2=240u*65536u;
    x1=(2u*x1)>>16;y1=(2u*y1)>>16;
    x2=(2u*x2+65535u)>>16;y2=(2u*y2+65535u)>>16;
    xy[0]=(y1<<16)|x1;xy[1]=(y2<<16)|x2;
}
