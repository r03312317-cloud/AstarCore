// [ARCH] 小型 AM 兼容层连接时间、键盘与整帧 GPU 请求。
// [ARCH] GPU 源请求必须为完整 256×240 索引画布。
// [ARCH] 获取后台缓冲前先确认前次发布。
// [ARCH] 完成 RGB565 缩放后才排队提交，缩放完成不是硬件换帧完成。
// [ARCH] MARIO_VIDEO_READY 只在至少一次换帧确认后输出。
// [ARCH] 发布等待和缩放分开累计性能开销。
// [ARCH] 键盘日志只在有边沿事件时打印。
#include "mario_port.h"
#include "soc_port.h"
#include <stdio.h>
#include "mario_profile.h"
static unsigned ready;
// [ARCH] 初始化板级显示/按键边界。
// [ARCH] 这里不创建操作系统任务或图形服务器。
// [ARCH] AM 兼容只覆盖游戏实际使用的接口。
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
    PROF_BEGIN(wait0);uint16_t *destination=soc_video_back();PROF_END(publish,wait0);
    if(!destination){puts("MARIO_VIDEO_TIMEOUT");return;}
    if(!ready&&soc_video_completed()){ready=1;puts("MARIO_VIDEO_READY");}
    PROF_BEGIN(scale0);mario_render(r.pixels,destination);PROF_END(scale,scale0);
    PROF_BEGIN(publish0);int error=soc_video_publish();PROF_END(publish,publish0);
    if(error){puts("MARIO_VIDEO_TIMEOUT");return;}
}
unsigned mario_present_count(void){return soc_video_completed();}
