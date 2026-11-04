// 架构导读：display_cmos2。
// 连接 CMOS2 图像结果与显示帧缓冲。
#include "display_cmos2.h"
#if defined(__GNUC__) && (__BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__)
// 数据布局定义：typedef uint32_t soc_display_alias32 __attribute__((__may_alias__));；字段顺序与本文件使用它的接口保持一致。
typedef uint32_t soc_display_alias32 __attribute__((__may_alias__));
#endif
// 服务函数 soc_display_resize_cmos2。
// 接口参数：const volatile uint8_t *source,volatile uint16_t *destination；返回值及副作用由下列函数体定义。
// 参数入口：source, destination；类型、指针限定及返回约定沿用下列声明。
void soc_display_resize_cmos2(const volatile uint8_t *source,volatile uint16_t *destination) {
#if defined(__GNUC__) && (__BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__)
    // 控制边界：(((uintptr_t)source|(uintptr_t)destination)&3u)==0u；仅在该条件成立时进入本分支。
    if((((uintptr_t)source|(uintptr_t)destination)&3u)==0u) {
        const volatile soc_display_alias32 *pixels=(const volatile soc_display_alias32 *)(const volatile void *)source;
        volatile soc_display_alias32 *out=(volatile soc_display_alias32 *)(volatile void *)destination;
        // 迭代边界：uint32_t y=0;y<340u;y++；地址和计数随循环体中的原始更新前进。
        for(uint32_t y=0;y<340u;y++) {
            const uint32_t sy=(36u*y+18u)/17u;
            const volatile soc_display_alias32 *row=pixels+sy*640u;
            // 迭代边界：uint32_t x=0;x<680u;x+=2u；地址和计数随循环体中的原始更新前进。
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
    // 迭代边界：uint32_t y=0;y<340u;y++；地址和计数随循环体中的原始更新前进。
    for(uint32_t y=0;y<340u;y++) {
        const uint32_t sy=(36u*y+18u)/17u;
        // 迭代边界：uint32_t x=0;x<680u;x++；地址和计数随循环体中的原始更新前进。
        for(uint32_t x=0;x<680u;x++) {
            const uint32_t sx=(32u*x+16u)/17u,a=(sy*1280u+sx)*2u;
            destination[y*680u+x]=(uint16_t)((uint16_t)source[a]|((uint16_t)source[a+1u]<<8));
        }
    }
}
// 服务函数 soc_display_map_cmos2。
// 接口参数：const uint32_t q16[4],uint32_t xy[2]；返回值及副作用由下列函数体定义。
// 参数入口：q16, xy；类型、指针限定及返回约定沿用下列声明。
void soc_display_map_cmos2(const uint32_t q16[4],uint32_t xy[2]) {
    uint32_t p[4];
    for(uint32_t i=0;i<4u;i++) {
        uint32_t q=q16[i];
        // 控制边界：i&1u；仅在该条件成立时进入本分支。
        if(i&1u)q=q>(70u<<16)?q-(70u<<16):0u;
        const uint32_t limit=(i&1u)?180u:320u,dimension=(i&1u)?340u:680u;
        const uint32_t qmax=limit<<16,denominator=((i&1u)?9u:8u)<<16;
        // 控制边界：q>qmax；仅在该条件成立时进入本分支。
        if(q>qmax)q=qmax;
        /* 680/320=17/8, 340/180=17/9; clamped q*17 fits uint32. */
        p[i]=(q*17u+(i>=2u?denominator-1u:0u))/denominator;
        // 控制边界：p[i]>dimension；仅在该条件成立时进入本分支。
        if(p[i]>dimension)p[i]=dimension;
    }
    xy[0]=p[0]|(p[1]<<16);xy[1]=p[2]|(p[3]<<16);
}
