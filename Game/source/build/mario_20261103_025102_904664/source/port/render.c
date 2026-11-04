#include "mario_port.h"
#include "fce.h"
#include "mario_profile.h"
/* NES 256x240 is displayed in a 4:3 480x360 viewport, x=80..559. */
MARIO_DDR_LOOP void mario_render(const uint8_t *pixels,volatile uint16_t *destination) {
    /* The two scanout surfaces retain their contents between publications.
     * Track source indices separately for each surface: its previous image
     * is two publications old, not the immediately preceding game image. */
    static _Alignas(4) uint8_t previous_pixels[2][SCR_W*SCR_H];
    static volatile uint16_t *surfaces[2];
    static bool initialized[2];
    unsigned bank=destination==surfaces[0]?0u:destination==surfaces[1]?1u:surfaces[0]?1u:0u;
    if(surfaces[bank]!=destination){surfaces[bank]=destination;initialized[bank]=false;}
    unsigned output_y=0;
    for(unsigned y=0;y<240;y++) {
        const uint8_t *s=pixels+y*256;
        uint8_t *old=previous_pixels[bank]+y*256;
        unsigned repeats=(y&1u)?1u:2u;
        volatile uint32_t *row0=(volatile uint32_t *)(void *)(destination+output_y*640);
        volatile uint32_t *row1=row0+(repeats==2?320:0);
        if(!initialized[bank]) {
            for(unsigned r=0;r<repeats;r++)for(unsigned x=0;x<40;x++)row0[r*320+x]=row0[r*320+280+x]=0;
        }
        /* Nearest-neighbour 16:30 expansion, exactly floor(x*256/480).
         * Palette lookup gives two identical RGB565 pixels directly. */
        for(unsigned group=0;group<16;group++) {
            const uint8_t *p=s+group*16;
            const uint32_t *now=(const uint32_t *)(const void *)p;
            uint32_t *before=(uint32_t *)(void *)(old+group*16);
            if(initialized[bank]&&now[0]==before[0]&&now[1]==before[1]&&now[2]==before[2]&&now[3]==before[3])continue;
            volatile uint32_t *d=row0+40+group*15,*d2=row1+40+group*15;
            for(unsigned x=0;x<7;x++) {uint32_t c=fce_palette565_dual[p[x]];d[x]=c;if(repeats==2)d2[x]=c;}
            uint32_t previous=fce_palette565_dual[p[7]]&0xffffu;
            for(unsigned x=8;x<16;x++) {uint32_t c=fce_palette565_dual[p[x]],v=previous|(c&0xffff0000u);d[x-1]=v;if(repeats==2)d2[x-1]=v;previous=c&0xffffu;}
            before[0]=now[0];before[1]=now[1];before[2]=now[2];before[3]=now[3];
        }
        output_y+=repeats;
    }
    initialized[bank]=true;
}
