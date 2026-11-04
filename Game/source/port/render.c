// [ARCH] 源图保存已经解析每像素调色板的 8 位颜色索引。
// [ARCH] 256×240 最近邻放大为居中的 480×360，左右各 80 像素黑边。
// [ARCH] 输出为 640×360 RGB565，每个 32 位写含两个相邻像素。
// [ARCH] 每块物理缓冲各有一份旧源图，通常是两次发布之前的内容。
// [ARCH] 按一行内 16 个源像素比较，仅重写变化块。
// [ARCH] 不能用上一模拟帧替代某块目标自己的历史。
// [ARCH] 偶数源行输出两行，奇数源行一行，总共 360 行。
// [ARCH] 16 个源像素展开为 30 个目标像素，保持原始采样位置。
// [ARCH] 目标换成新地址时重新初始化黑边与历史。
// [ARCH] 不重复行时 row1 不越过对象有效范围。
// [ARCH] 双像素调色板减少颜色拼接指令。
// [ARCH] 显示所有权的确认由 board.c 完成。
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
        // [ARCH] 行放大采用 2、1 交替，保持 240→360 的精确输出数量。
        // [ARCH] 与列方向 16→30 的块展开共同实现原最近邻采样。
        // [ARCH] 黑边不属于 NES 源画布，但必须在首次使用目标时初始化。
        unsigned repeats=(y&1u)?1u:2u;
        volatile uint32_t *row0=(volatile uint32_t *)(void *)(destination+output_y*640);
        volatile uint32_t *row1=row0+(repeats==2?320:0);
        if(!initialized[bank]) {
            for(unsigned r=0;r<repeats;r++)for(unsigned x=0;x<40;x++)row0[r*320+x]=row0[r*320+280+x]=0;
        }
        /* Nearest-neighbour 16:30 expansion, exactly floor(x*256/480).
         * Palette lookup gives two identical RGB565 pixels directly. */
        // [ARCH] 块比较以当前目标自己的历史为准。
        // [ARCH] 相等块跳过真实 DDR 写，源图本身仍逐帧更新。
        // [ARCH] 如果只维护一份全局历史，另一个两帧前的物理缓冲会留下残影。
        for(unsigned group=0;group<16;group++) {
            const uint8_t *p=s+group*16;
            const uint32_t *now=(const uint32_t *)(const void *)p;
            uint32_t *before=(uint32_t *)(void *)(old+group*16);
            if(initialized[bank]&&now[0]==before[0]&&now[1]==before[1]&&now[2]==before[2]&&now[3]==before[3])continue;
            volatile uint32_t *d=row0+40+group*15,*d2=row1+40+group*15;
            for(unsigned x=0;x<7;x++) {uint32_t c=fce_palette565_dual[p[x]];d[x]=c;if(repeats==2)d2[x]=c;}
            uint32_t previous=fce_palette565_dual[p[7]]&0xffffu;
            for(unsigned x=8;x<16;x++) {uint32_t c=fce_palette565_dual[p[x]],v=previous|(c&0xffff0000u);d[x-1]=v;if(repeats==2)d2[x-1]=v;previous=c&0xffffu;}
            // [ARCH] 只有这个目标块完成写入后才更新对应历史。
            // [ARCH] 历史记录的是源索引，避免重复保存更大的 RGB565 全帧。
            // [ARCH] 另一块物理缓冲的历史不能在此一并更新。
            before[0]=now[0];before[1]=now[1];before[2]=now[2];before[3]=now[3];
        }
        output_y+=repeats;
    }
    initialized[bank]=true;
}
