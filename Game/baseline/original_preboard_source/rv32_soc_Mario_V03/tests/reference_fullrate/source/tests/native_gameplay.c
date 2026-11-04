#include "mario_port.h"
#include "cpu-internal.h"
#include <stdio.h>
#include <string.h>
#include <assert.h>
#include <stdlib.h>
static uint8_t buttons;
static unsigned test_frame,presents;
static uint32_t image_hash;
static _Alignas(16) uint16_t guarded[640*360+16];
static uint16_t *screen=guarded+8;
void ioe_init(void){}
void putch(char c){putchar(c);}
AM_TIMER_UPTIME_T am_read_AM_TIMER_UPTIME(void){return (AM_TIMER_UPTIME_T){(uint64_t)test_frame*16667};}
AM_GPU_CONFIG_T am_read_AM_GPU_CONFIG(void){return (AM_GPU_CONFIG_T){256,240};}
AM_INPUT_KEYBRD_T am_read_AM_INPUT_KEYBRD(void){return mario_input_event(buttons);}
void am_write_AM_GPU_FBDRAW(AM_GPU_FBDRAW_T r) {
    assert(r.x==0&&r.y==0&&r.w==256&&r.h==240&&r.pixels);
    mario_render(r.pixels,screen);presents++;
    image_hash=2166136261u;
    for(unsigned i=0;i<640*360;i++){image_hash=(image_hash^(screen[i]&255u))*16777619u;image_hash=(image_hash^(screen[i]>>8))*16777619u;}
    for(unsigned i=0;i<8;i++)assert(guarded[i]==0x6bad&&guarded[640*360+8+i]==0x6bad);
}
static void picture(const char *directory,unsigned frame) {
    char path[1024];snprintf(path,sizeof(path),"%s/frame_%04u.ppm",directory,frame);
    FILE *f=fopen(path,"wb");assert(f);fprintf(f,"P6\n640 360\n255\n");
    for(unsigned i=0;i<640*360;i++) {
        unsigned c=screen[i],r=(c>>11)&31,g=(c>>5)&63,b=c&31;
        unsigned char rgb[3]={(r<<3)|(r>>2),(g<<2)|(g>>4),(b<<3)|(b>>2)};fwrite(rgb,1,3,f);
    }
    fclose(f);
}
int main(int argc,char **argv) {
    assert(argc==2);for(unsigned i=0;i<8;i++)guarded[i]=guarded[640*360+8+i]=0x6bad;
    assert(mario_boot()==0);char path[1024];snprintf(path,sizeof(path),"%s/trace.csv",argv[1]);
    FILE *trace=fopen(path,"wb");assert(trace);fprintf(trace,"frame,buttons,mode,task,x,y,state,world,level,presents,lives,image_hash,ram_crc,cpu_pc\n");
    for(test_frame=0;test_frame<1000;test_frame++) {
        buttons=0;
        if(test_frame>=90&&test_frame<93)buttons=1;
        if(test_frame>=300&&test_frame<320)buttons=8;
        if(test_frame>=335&&test_frame<355)buttons=16;
        if(test_frame>=440&&test_frame<460)buttons=4;
        if((test_frame>=470&&test_frame<473)||(test_frame>=540&&test_frame<543))buttons=1;
        if(test_frame>=485&&test_frame<505)buttons=8;
        if(test_frame>=560&&test_frame<1000)buttons=8;
        mario_step();
        fprintf(trace,"%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u\n",test_frame,buttons,CPU_RAM[0x770],CPU_RAM[0x772],((unsigned)CPU_RAM[0x6d]<<8)|CPU_RAM[0x86],CPU_RAM[0xce],CPU_RAM[0x1d],CPU_RAM[0x75f],CPU_RAM[0x75c],presents,CPU_RAM[0x75a],image_hash,mario_state_crc(),cpu.PC);
        if(test_frame==3||test_frame==60||test_frame==299||test_frame==334||test_frame==349||test_frame==420||test_frame==465||test_frame==650)picture(argv[1],test_frame);
    }
    fclose(trace);printf("MARIO_NATIVE_CAPTURE_DONE frames=%u presented=%u\n",test_frame,presents);return 0;
}
