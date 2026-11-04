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
