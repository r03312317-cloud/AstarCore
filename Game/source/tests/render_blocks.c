#include "mario_port.h"
#include "fce.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

uint32_t fce_palette565_dual[64];
static _Alignas(4) uint8_t source[256*240];
static _Alignas(16) uint16_t surfaces[2][640*360+16];
static uint32_t rng=0x51eed123u;
static uint32_t next(void){rng^=rng<<13;rng^=rng>>17;rng^=rng<<5;return rng;}
static uint16_t color(unsigned index){uint32_t c=palette[index];return ((c>>8)&0xf800)|((c>>5)&0x7e0)|((c>>3)&31);}
int main(void){
    for(unsigned i=0;i<64;i++){uint32_t c=color(i);fce_palette565_dual[i]=c|(c<<16);}
    for(unsigned b=0;b<2;b++)for(unsigned i=0;i<640*360+16;i++)surfaces[b][i]=0x6bad;
    memset(source,13,sizeof(source));
    for(unsigned frame=0;frame<130;frame++){
        if(frame%19==2)for(unsigned i=0;i<sizeof(source);i++)source[i]=next()&63;
        else if(frame%11!=0&&frame>1){
            for(unsigned n=0;n<35;n++)source[next()%sizeof(source)]=next()&63;
            /* Last row, clipping edges, and 16-pixel block boundaries. */
            source[239*256+(frame%2?255:0)]=next()&63;
            source[(frame*17%240)*256+15]=next()&63;
            source[(frame*17%240)*256+16]=next()&63;
        }
        unsigned bank=frame&1;uint16_t *out=surfaces[bank]+8;
        mario_render(source,out);
        for(unsigned y=0;y<360;y++)for(unsigned x=0;x<640;x++){
            uint16_t expected=x<80||x>=560?0:color(source[(y*240/360)*256+(x-80)*256/480]);
            if(out[y*640+x]!=expected){fprintf(stderr,"pixel mismatch frame=%u x=%u y=%u\n",frame,x,y);return 1;}
        }
        for(unsigned b=0;b<2;b++)for(unsigned i=0;i<8;i++)assert(surfaces[b][i]==0x6bad&&surfaces[b][640*360+8+i]==0x6bad);
    }
    puts("DIRTY_BLOCK_RENDER_PASS frames=130 surfaces=2 pixel_comparisons=29952000");return 0;
}
