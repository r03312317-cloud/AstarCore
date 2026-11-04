// [ARCH] RISC-V 主循环逐帧推进 NES、限制最高速率并输出性能样本。
// [ARCH] 每秒记录模拟帧差、确认换帧差和真实机器周期差。
// [ARCH] 采样分母不包含下载或固件传输。
// [ARCH] 第 4 帧 RAM CRC/PC 与冻结参考交叉核对。
// [ARCH] 60 帧间隔限制是上限，不表示实板达到 60 FPS。
// [ARCH] 阶段周期累计清零不重置游戏状态。
// [ARCH] MODE=1 汇总仍可能包含暂停，活动游玩片段需单独筛选。
// [ARCH] 这里的 CPU 阶段指 6502 模拟开销，实际执行者仍是 RV32。
#include "mario_port.h"
#include "soc_port.h"
#include "cpu-internal.h"
#include <stdio.h>
#include "mario_profile.h"
int main(void) {
    puts("SOC_MARIO_V03 DDR ENTRY; I2W2 RV32IM 100MHz; ITCM TEXT");
    ioe_init();
    if(mario_boot()){puts("MARIO_ROM_REJECTED");return 1;}
    puts("MARIO_ROM_OK; LITENES_READY; AUDIO_DISABLED");
    puts("BUTTON0=JUMP 1=START 2=RUN 3=LEFT 4=RIGHT; LEFT+RIGHT=DOWN");
    uint64_t last=soc_cycles();unsigned last_frame=0,last_video=0;
    for(;;) {
        uint64_t start=soc_cycles();mario_step();
        if(mario_frame()==4)printf("MARIO_CHECKPOINT RAM=%08lx PC=%04x\n",(unsigned long)mario_state_crc(),cpu.PC);
        while(soc_cycles()-start<100000000u/60u){}
        uint64_t now=soc_cycles();
        if(now-last>=100000000u) {
            unsigned n=mario_frame();
            unsigned video=mario_present_count();struct mario_costs c=mario_costs;mario_costs=(struct mario_costs){0};
            printf("MARIO_FRAME=%u DELTA=%u CYCLES=%lu MODE=%u X=%u Y=%u VID=%u VDELTA=%u CYCLE_HI=%lu CYCLE_LO=%lu TASK=%u LIVES=%u\n",n,n-last_frame,(unsigned long)(now-last),CPU_RAM[0x770],((unsigned)CPU_RAM[0x6d]<<8)|CPU_RAM[0x86],CPU_RAM[0xce],video,video-last_video,(unsigned long)(now>>32),(unsigned long)now,CPU_RAM[0x772],CPU_RAM[0x75a]);
            printf("MARIO_COST CPU=%lu BG=%lu SPR=%lu SCALE=%lu PUB=%lu INPUT=%lu CLEAR=%lu\n",(unsigned long)c.cpu,(unsigned long)c.bg,(unsigned long)c.sprite,(unsigned long)c.scale,(unsigned long)c.publish,(unsigned long)c.input,(unsigned long)c.clear);
            last=now;last_frame=n;last_video=video;
        }
    }
}
