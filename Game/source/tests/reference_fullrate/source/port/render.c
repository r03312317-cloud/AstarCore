#include "mario_port.h"
static uint16_t rgb565(uint32_t c){return (uint16_t)(((c>>8)&0xf800)|((c>>5)&0x07e0)|((c>>3)&31));}
/* NES 256x240 is displayed in a 4:3 480x360 viewport, x=80..559. */
void mario_render(const uint32_t *pixels,volatile uint16_t *destination) {
    unsigned sample[480];for(unsigned x=0;x<480;x++)sample[x]=x*256/480;
    for(unsigned y=0;y<360;y++) {
        const uint32_t *s=pixels+(y*240/360)*256;
        volatile uint32_t *d=(volatile uint32_t *)(void *)(destination+y*640);
        for(unsigned x=0;x<40;x++)d[x]=d[280+x]=0;
        for(unsigned x=0;x<240;x++)d[40+x]=(uint32_t)rgb565(s[sample[2*x]])|((uint32_t)rgb565(s[sample[2*x+1]])<<16);
    }
}
