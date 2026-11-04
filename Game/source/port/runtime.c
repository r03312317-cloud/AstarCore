// [ARCH] 帧级入口负责 ROM 校验、初始化与扫描线推进。
// [ARCH] 只准入随包的 40976 字节 mapper0/NROM 配置。
// [ARCH] PRG/CHR 检查先于原引擎装载。
// [ARCH] 一个模拟帧包含 262 条扫描线。
// [ARCH] 每 16 行轮询按键，一帧约 17 次，并保持第一次轮询相位。
// [ARCH] 减少的是带屏障 MMIO 的次数，不修改手柄协议。
// [ARCH] frames 是模拟帧数，不是 HDMI 完整帧计数。
// [ARCH] CRC 只覆盖约定的前 0x800 字节 CPU_RAM。
#include "mario_port.h"
#include "fce.h"
#include "ppu.h"
#include "psg.h"
#include "cpu-internal.h"
#include "soc_port.h"
#include "mario_profile.h"
#include <string.h>
extern const unsigned char rom_mario_nes[];
extern const unsigned int rom_mario_nes_len;
static unsigned frames;
// [ARCH] 先验证随包 ROM 的签名、PRG/CHR 数量和 mapper 限制。
// [ARCH] 拒绝不匹配配置，不能以成功装入任意文件替代兼容性检查。
// [ARCH] 然后才建立 PPU/6502 状态与手柄初值。
int mario_boot(void) {
    const unsigned char *r=rom_mario_nes;
    /* This port intentionally accepts the bundled NROM-256/8KiB CHR fixture.
     * The upstream mapper 3 path has only one CHR slot and is not enabled. */
    if(rom_mario_nes_len!=40976||memcmp(r,"NES\032",4)||r[4]!=2||r[5]!=1||
       (r[6]&0xfe)||r[7])return -1;
    if(fce_load_rom((char *)(uintptr_t)r))return -2;
    fce_init();psg_init();frames=0;return 0;
}
// [ARCH] 完整推进一帧扫描线后增加 frames。
// [ARCH] 实体输入按固定扫描线相位轮询。
// [ARCH] 模拟帧和已发布图像的计数分别保留。
void mario_step(void) {
    for(unsigned scanline=0;scanline<262;scanline++) {
        ppu_cycle();
        /* Each board read requires an ordering barrier on this core. Poll
         * every 16 scanlines, keeping the original first-poll phase. */
        if((scanline&15u)==0){PROF_BEGIN(t);psg_detect_key();PROF_END(input,t);}
    }
    frames++;
}
unsigned mario_frame(void){return frames;}
uint32_t mario_state_crc(void){return soc_crc32(CPU_RAM,0x800);}
