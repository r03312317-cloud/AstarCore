#include "mario_port.h"
#include "soc_port.h"
#include <stdio.h>
static unsigned presented;
void ioe_init(void){soc_video_init();}
void putch(char c){soc_uart_putc(c);}
AM_TIMER_UPTIME_T am_read_AM_TIMER_UPTIME(void){return (AM_TIMER_UPTIME_T){soc_cycles()/100u};}
AM_GPU_CONFIG_T am_read_AM_GPU_CONFIG(void){return (AM_GPU_CONFIG_T){256,240};}
AM_INPUT_KEYBRD_T am_read_AM_INPUT_KEYBRD(void) {
    AM_INPUT_KEYBRD_T e=mario_input_event(soc_buttons());
    if(e.keycode)printf("MARIO_KEY=%d DOWN=%d FRAME=%u\n",e.keycode,e.keydown,mario_frame());
    return e;
}
void am_write_AM_GPU_FBDRAW(AM_GPU_FBDRAW_T r) {
    if(r.x||r.y||r.w!=256||r.h!=240||!r.pixels){puts("MARIO_VIDEO_BAD_REQUEST");return;}
    mario_render(r.pixels,soc_video_back());
    if(soc_video_publish()){puts("MARIO_VIDEO_TIMEOUT");return;}
    if(!presented++)puts("MARIO_VIDEO_READY");
}
