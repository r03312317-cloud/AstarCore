#include "soc_display.h"
/* Restore the original 4:3 display aspect, including DOS non-square pixels:
 * 320x200 -> 480x360, with 80 black columns at each side of the 640x360 window. */
void soc_scale_rgb565(const uint16_t *src,unsigned w,unsigned h,unsigned pitch,volatile uint16_t *dst) {
    if(!src||!w||!h||pitch<w)return;
    /* Division on RV32 is expensive. Reuse the 480 horizontal samples for
     * every row, and combine pixels into aligned 32-bit DDR stores. */
    unsigned sample[480];
    for(unsigned x=0;x<480;x++)sample[x]=x*w/480;
    for(unsigned y=0;y<360;y++) {
        volatile uint16_t *row=dst+y*640;const uint16_t*s=src+(y*h/360)*pitch;
        if(((uintptr_t)row&3u)==0) {
            volatile uint32_t *packed=(volatile uint32_t *)(void *)row;
            for(unsigned x=0;x<40;x++)packed[x]=packed[280+x]=0;
            for(unsigned x=0;x<240;x++)packed[40+x]=(uint32_t)s[sample[2*x]]|((uint32_t)s[sample[2*x+1]]<<16);
        } else {
            /* Preserve the public helper's halfword-aligned host use. */
            for(unsigned x=0;x<80;x++)row[x]=row[560+x]=0;
            for(unsigned x=0;x<480;x++)row[80+x]=s[sample[x]];
        }
    }
}
void soc_input_update(soc_input_t*s,uint8_t b,uint32_t now,soc_key_event emit,void*opaque) {
    for(unsigned i=0;i<4;i++)if((b^s->previous)&(1u<<i))emit(i+1,(b>>i)&1u,opaque);
    if((b&16u)&&!(s->previous&16u)){s->pressed_at=now;s->escape=0;}
    if((b&16u)&&!s->escape&&(uint32_t)(now-s->pressed_at)>=800){emit(6,1,opaque);s->escape=1;}
    if(!(b&16u)&&(s->previous&16u)) {
        if(s->escape)emit(6,0,opaque);else{emit(5,1,opaque);emit(5,0,opaque);}
        s->escape=0;
    }
    s->previous=b;
}
