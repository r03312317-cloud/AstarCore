#include "display_cmos2.h"
#if defined(__GNUC__) && (__BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__)
typedef uint32_t soc_display_alias32 __attribute__((__may_alias__));
#endif
void soc_display_resize_cmos2(const volatile uint8_t *source,volatile uint16_t *destination) {
#if defined(__GNUC__) && (__BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__)
    if((((uintptr_t)source|(uintptr_t)destination)&3u)==0u) {
        const volatile soc_display_alias32 *pixels=(const volatile soc_display_alias32 *)(const volatile void *)source;
        volatile soc_display_alias32 *out=(volatile soc_display_alias32 *)(volatile void *)destination;
        for(uint32_t y=0;y<340u;y++) {
            const uint32_t sy=(36u*y+18u)/17u;
            const volatile soc_display_alias32 *row=pixels+sy*640u;
            for(uint32_t x=0;x<680u;x+=2u) {
                const uint32_t sx0=(32u*x+16u)/17u,sx1=(32u*(x+1u)+16u)/17u;
                const uint32_t a=(row[sx0>>1]>>((sx0&1u)*16u))&0xffffu;
                const uint32_t b=(row[sx1>>1]>>((sx1&1u)*16u))&0xffffu;
                out[y*340u+(x>>1)]=a|(b<<16);
            }
        }
        return;
    }
#endif
    for(uint32_t y=0;y<340u;y++) {
        const uint32_t sy=(36u*y+18u)/17u;
        for(uint32_t x=0;x<680u;x++) {
            const uint32_t sx=(32u*x+16u)/17u,a=(sy*1280u+sx)*2u;
            destination[y*680u+x]=(uint16_t)((uint16_t)source[a]|((uint16_t)source[a+1u]<<8));
        }
    }
}
void soc_display_map_cmos2(const uint32_t q16[4],uint32_t xy[2]) {
    uint32_t p[4];
    for(uint32_t i=0;i<4u;i++) {
        uint32_t q=q16[i];
        if(i&1u)q=q>(70u<<16)?q-(70u<<16):0u;
        const uint32_t limit=(i&1u)?180u:320u,dimension=(i&1u)?340u:680u;
        const uint32_t qmax=limit<<16,denominator=((i&1u)?9u:8u)<<16;
        if(q>qmax)q=qmax;
        /* 680/320=17/8, 340/180=17/9; clamped q*17 fits uint32. */
        p[i]=(q*17u+(i>=2u?denominator-1u:0u))/denominator;
        if(p[i]>dimension)p[i]=dimension;
    }
    xy[0]=p[0]|(p[1]<<16);xy[1]=p[2]|(p[3]<<16);
}
