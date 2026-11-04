// Linux 用户空间 GUI，运行于 FPGA CPU；电脑仅提供串口输入和日志显示。
// GUI 绘制 320 乘 180，但 Linux framebuffer ABI 保留 640 乘 360 和每行 1280 字节。
// 硬件把 ROI 放大两倍后居中显示，不能按显示器有效分辨率推算应用传输量。
// 内核版本和架构来自 uname，运行时间和内存来自当前系统的 proc 接口。
// 计数读取独立 shell 后台程序的文件，开始与停止需要用户从串口下达命令。
// 页面命令走私有 FIFO，应用不占用 UART shell 的标准输入。
// 本版为 LVGL 应用，不包含 Ubuntu 桌面或完整终端模拟器。
/* SPDX-License-Identifier: MIT
 * RV32 Linux GUI. LVGL 8.3.11, software RGB565 rendering.
 * --headless FILE --frames N writes an RGB565 image for host smoke tests.
 * --fb /dev/fb0 uses the actual Linux framebuffer; no desktop server required.
 * Commands arrive on a private FIFO, never by stealing the console's stdin.
 */
#define _POSIX_C_SOURCE 200809L
#include "lvgl.h"
#include <errno.h>
#include <fcntl.h>
#include <linux/fb.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/utsname.h>
#include <time.h>
#include <unistd.h>
/* The existing fbdev ABI exposes two 640x360 pages at a 1280-byte stride.
 * Only each page's top-left 320x180 region is drawn and scanned; hardware
 * expands that region 2x in both axes before HDMI output. */
#define WIDTH 320
#define HEIGHT 180
// ABI 页宽保持 640，不能因为 GUI 缩小为 320 就改变 Linux 驱动几何。
#define FB_PAGE_WIDTH 640
// 页偏移沿用 360 行 ABI，ROI 高度 180 只限制实际绘制和扫描范围。
#define FB_PAGE_HEIGHT 360
static uint8_t *pixels;
static size_t map_size, stride;
static uint8_t *fb_map;
static int fb_fd = -1;
static unsigned fb_back = 1;
static lv_area_t changed, previous;
static bool have_changed, have_previous;
static struct fb_var_screeninfo fb_var;
static volatile sig_atomic_t running = 1;
static lv_obj_t *home_page,*status_page,*home_info,*uptime_label,*memory_label,*counter_label,*counter_state;
static unsigned flush_count,current_page;
extern const lv_img_dsc_t soc_subtitle,soc_footer;
static int command_fd = -1;
static bool own_fifo;
static const char *fifo_path = "/run/rv32-gui/commands";
static void stop(int sig) { (void)sig; running = 0; }
// 以 CLOCK_MONOTONIC 计算应用节拍毫秒数，不把 FPGA 配置主频伪装成实时测量值。
static uint64_t monotonic_ms(void) {
    struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t);
    return (uint64_t)t.tv_sec * 1000 + t.tv_nsec / 1000000;
}
// 合并两个脏矩形的边界，供双缓冲时补齐上一次仍滞后的区域。
static void include_area(lv_area_t *dst, const lv_area_t *src) {
    if(src->x1<dst->x1)dst->x1=src->x1;
    if(src->y1<dst->y1)dst->y1=src->y1;
    if(src->x2>dst->x2)dst->x2=src->x2;
    if(src->y2>dst->y2)dst->y2=src->y2;
}
// 后缓冲可能比当前画布落后一帧，因此复制当前脏区与上一帧脏区的并集。
// 写入时保留 1280 字节 stride 以及 360 行页间距，不能按 ROI 紧密排列。
// 只有 pan ioctl 成功后才交换前后页；失败不应继续冒充拥有可写的旧前页。
// 把本次和上次脏区域复制到后缓冲，再以 FBIOPAN_DISPLAY 完成交接。
static void present(void) {
    if(!fb_map || !have_changed)return;
    lv_area_t area=changed;
    if(have_previous)include_area(&area,&previous);
    /* Back buffer can be one frame stale: copy current and previous damage. */
    for(int y=area.y1;y<=area.y2;y++)
        // 后缓冲复制使用页高和真实 stride，源 ROI 小于 ABI 页尺寸也不能压缩页间距。
        memcpy(fb_map+(fb_back*FB_PAGE_HEIGHT+(size_t)y)*stride+area.x1*2,
               pixels+(size_t)y*stride+area.x1*2,(area.x2-area.x1+1)*2);
    fb_var.yoffset=fb_back*FB_PAGE_HEIGHT;fb_var.activate=FB_ACTIVATE_VBL;
    // 该 ioctl 把已经画好的非活动页交给驱动；失败时停止本轮呈现，不能宣称换页成功。
    if(ioctl(fb_fd,FBIOPAN_DISPLAY,&fb_var)){perror("frame ownership transfer");running=0;return;}
    fb_back ^= 1; previous=changed; have_previous=true;have_changed=false;
}
// LVGL 一帧可能分成多个矩形刷新，先汇总脏区再在最后一个 flush 进行呈现。
// 边界检查防止错误矩形越过 320 乘 180 的实际绘制区域。
// flush ready 释放 LVGL 绘制缓冲，和驱动完成帧基址提交是两个不同层次的事件。
// 接收 LVGL 输出矩形，按真实 stride 写入绘制缓存；最后一次 flush 才提交一帧。
static void flush(lv_disp_drv_t *d, const lv_area_t *a, lv_color_t *src) {
    /* LVGL guarantees valid display areas. Still reject out-of-range input. */
    if (a->x1 >= 0 && a->y1 >= 0 && a->x2 < WIDTH && a->y2 < HEIGHT) {
        size_t n = (size_t)(a->x2 - a->x1 + 1) * sizeof(lv_color_t);
        for (int y = a->y1; y <= a->y2; ++y) {
            memcpy(pixels + (size_t)y * stride + (size_t)a->x1 * 2, src, n);
            src += a->x2 - a->x1 + 1;
        }
        ++flush_count;
        if(!have_changed){changed=*a;have_changed=true;}else include_area(&changed,a);
        if(lv_disp_flush_is_last(d))present();
    }
    // 每次 flush 都通知 LVGL 缓冲已可复用，成功提交整帧是另一件事。
    lv_disp_flush_ready(d);
}
// 创建 LVGL 文本对象并设置位置，文本内容后续可由系统信息刷新回调更新。
static lv_obj_t *label(lv_obj_t *parent, const char *text, int x, int y) {
    lv_obj_t *o = lv_label_create(parent); lv_label_set_text(o, text);
    lv_obj_set_pos(o, x, y); return o;
}
// 以 LVGL 基本图形构造界面对象，企鹅与背景是应用实时绘制的图形元素。
static lv_obj_t *shape(lv_obj_t *parent,int x,int y,int w,int h,uint32_t color,int radius) {
    lv_obj_t *o=lv_obj_create(parent);lv_obj_remove_style_all(o);lv_obj_clear_flag(o,LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_pos(o,x,y);lv_obj_set_size(o,w,h);
    lv_obj_set_style_bg_color(o,lv_color_hex(color),0);lv_obj_set_style_bg_opa(o,LV_OPA_COVER,0);
    lv_obj_set_style_radius(o,radius,0);return o;
}
// 设置文本颜色和字体，不参与系统信息采样或内核版本生成。
static void colored_text(lv_obj_t *o,uint32_t color,const lv_font_t *font) {
    lv_obj_set_style_text_color(o,lv_color_hex(color),0);lv_obj_set_style_text_font(o,font,0);
}
// MemAvailable 比 MemFree 更接近应用仍可使用的内存，因此已用量取 Total 减 Available。
// proc 文件读取失败时保留调用者给出的初始值，不能补造一个固定内存容量。
// 页面显示换算为 MiB，原始 proc 数字单位是 KiB。
// 从 /proc/meminfo 读取 MemTotal 和 MemAvailable，以两者之差显示已用内存。
static void memory_kib(unsigned long *total,unsigned long *used) {
    // 此读取来自当前文件系统或 proc 接口，失败分支需要保留明确的默认或错误显示。
    FILE *f = fopen("/proc/meminfo", "r"); if (!f) return;
    char line[160]; unsigned long all = 0, available = 0;
    while (fgets(line, sizeof line, f)) {
        unsigned long v;
        if (sscanf(line, "MemTotal: %lu", &v) == 1) all = v;
        if (sscanf(line, "MemAvailable: %lu", &v) == 1) available = v;
    }
    fclose(f);*total=all;*used=all>=available?all-available:0;
}
// 从当前 Linux 的 /proc/uptime 读取运行时间，不使用预录启动文本。
static unsigned long uptime_seconds(void) {
    FILE *f=fopen("/proc/uptime","r");unsigned long seconds=0;
    if(f){(void)fscanf(f,"%lu",&seconds);fclose(f);}return seconds;
}
// 把采样的秒数转为天 时 分 秒，显示格式不改变内核计时来源。
static void format_uptime(char *out,size_t size,unsigned long n) {
    snprintf(out,size,"%lud %02lu:%02lu:%02lu",n/86400,(n/3600)%24,(n/60)%60,n%60);
}
// 每次回调重新查询 uname 和 proc，首页内核版本不是硬编码的图片标签。
// 计数值和 running 标记分别读取，能区分数值保留与后台进程已经停止。
// 运行目录可由环境变量替换，默认仍是板上 Linux 的 run 目录。
// 此回调由 LVGL 的普通进程事件循环驱动，没有注册系统定时任务。
// 调用 uname 并读取 proc 和计数文件，同步更新首页及状态页的真实运行信息。
static void status_update(lv_timer_t *timer) {
    (void)timer;struct utsname u;char t[40],text[256],path[512];unsigned long total=0,used=0;
    unsigned long long count=0;bool running_counter=false;
    // 环境变量允许仿真与实板选择不同运行目录，默认路径仍位于板上 Linux。
    const char *demo_dir=getenv("RV32_DEMO_DIR");if(!demo_dir)demo_dir="/run/rv32-demo";
    memset(&u,0,sizeof u);if(uname(&u)){strcpy(u.release,"unavailable");strcpy(u.machine,"unavailable");}
    format_uptime(t,sizeof t,uptime_seconds());memory_kib(&total,&used);
    snprintf(path,sizeof path,"%s/counter",demo_dir);
    FILE *f=fopen(path,"r");if(f){(void)fscanf(f,"%llu",&count);fclose(f);}
    snprintf(path,sizeof path,"%s/running",demo_dir);running_counter=access(path,F_OK)==0;
    snprintf(text,sizeof text,"KERNEL  %s\nARCH     %s\nUPTIME %s",u.release,u.machine,t);
    lv_label_set_text(home_info,text);
    lv_label_set_text(uptime_label,t);
    snprintf(text,sizeof text,"%lu MiB / %lu MiB",used/1024,total/1024);lv_label_set_text(memory_label,text);
    snprintf(text,sizeof text,"%llu",count);lv_label_set_text(counter_label,text);
    lv_label_set_text(counter_state,running_counter?"RUNNING":"STOPPED");
    lv_obj_set_style_text_color(counter_state,lv_color_hex(running_counter?0x69dfb4:0x9eb0c0),0);
}
// 页面通过隐藏标志切换，不退出 Linux 也不重新加载 FPGA 位流。
// 切页命令来自私有 FIFO，与控制台 root shell 的输入保持分离。
// 改变两个页面的隐藏标志，保留同一个 Linux GUI 进程和显示缓冲。
static void set_page(unsigned page) {
    current_page=page?1:0;
    if(current_page){lv_obj_add_flag(home_page,LV_OBJ_FLAG_HIDDEN);lv_obj_clear_flag(status_page,LV_OBJ_FLAG_HIDDEN);}
    else {lv_obj_add_flag(status_page,LV_OBJ_FLAG_HIDDEN);lv_obj_clear_flag(home_page,LV_OBJ_FLAG_HIDDEN);}
}
// 首页和状态页共享一组持久 LVGL 对象，后续刷新修改对象文字而非播放预录画面。
// 企鹅由应用基本图形构造，用于视觉辨识；Linux 运行证据来自实时数据和串口命令。
// 下方页脚占用固定区域，缩小 ROI 后所有对象坐标均落在 320 乘 180 内。
// 构造首页和状态页的 LVGL 对象，系统数据占位在刷新回调中被真实值替换。
static void make_ui(void) {
    lv_obj_t *screen=lv_scr_act();lv_obj_clear_flag(screen,LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_style_bg_color(screen,lv_color_hex(0x101925),0);lv_obj_set_style_bg_opa(screen,LV_OPA_COVER,0);
    lv_obj_t *title=label(screen,"Linux on RV32 RV32",10,5);colored_text(title,0xf2f7fa,&lv_font_montserrat_18);
    shape(screen,10,29,300,1,0x314355,0);
    lv_obj_t *footer=lv_img_create(screen);lv_img_set_src(footer,&soc_footer);lv_obj_set_pos(footer,10,161);
    home_page=lv_obj_create(screen);lv_obj_remove_style_all(home_page);lv_obj_clear_flag(home_page,LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_size(home_page,320,128);lv_obj_set_pos(home_page,0,33);
    status_page=lv_obj_create(screen);lv_obj_remove_style_all(status_page);lv_obj_clear_flag(status_page,LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_size(status_page,320,128);lv_obj_set_pos(status_page,0,33);
    /* Original vector penguin: a recognisable emblem built from LVGL shapes. */
    shape(home_page,17,29,60,78,0x080c12,LV_RADIUS_CIRCLE);
    shape(home_page,25,17,44,42,0x080c12,LV_RADIUS_CIRCLE);
    shape(home_page,26,47,42,53,0xe5eceb,LV_RADIUS_CIRCLE);
    shape(home_page,31,30,11,14,0xffffff,LV_RADIUS_CIRCLE);
    shape(home_page,51,30,11,14,0xffffff,LV_RADIUS_CIRCLE);
    shape(home_page,36,34,4,6,0x172334,LV_RADIUS_CIRCLE);
    shape(home_page,52,34,4,6,0x172334,LV_RADIUS_CIRCLE);
    shape(home_page,41,46,12,6,0xf2b735,3);
    shape(home_page,12,98,28,10,0xf2b735,LV_RADIUS_CIRCLE);
    shape(home_page,53,98,28,10,0xf2b735,LV_RADIUS_CIRCLE);
    lv_obj_t *subtitle=lv_img_create(home_page);lv_img_set_src(subtitle,&soc_subtitle);lv_obj_set_pos(subtitle,90,6);
    home_info=label(home_page,"Reading system information...",90,30);colored_text(home_info,0xdde9ed,&lv_font_montserrat_14);
    lv_obj_set_width(home_info,220);lv_label_set_long_mode(home_info,LV_LABEL_LONG_WRAP);
    lv_obj_set_style_text_line_space(home_info,6,0);
    lv_obj_t *heading=label(status_page,"System status",10,0);colored_text(heading,0xf2f7fa,&lv_font_montserrat_18);
    lv_obj_t *a=label(status_page,"UPTIME",10,30);colored_text(a,0x9bb1be,&lv_font_montserrat_14);
    uptime_label=label(status_page,"--",10,49);colored_text(uptime_label,0xe7f3f5,&lv_font_montserrat_14);
    a=label(status_page,"MEM USED / TOTAL",10,78);colored_text(a,0x9bb1be,&lv_font_montserrat_14);
    memory_label=label(status_page,"--",10,98);colored_text(memory_label,0xe7f3f5,&lv_font_montserrat_14);
    shape(status_page,170,29,1,91,0x314355,0);
    a=label(status_page,"DEMO COUNTER",184,30);colored_text(a,0x9bb1be,&lv_font_montserrat_14);
    counter_label=label(status_page,"0",184,51);colored_text(counter_label,0xf2f7fa,&lv_font_montserrat_18);
    counter_state=label(status_page,"STOPPED",184,79);colored_text(counter_state,0x9bb1be,&lv_font_montserrat_14);
    // 配置 GUI 的周期回调，刷新周期受 Linux 调度影响，不是独立硬件计时精度证明。
    set_page(0);status_update(NULL);lv_timer_create(status_update,1000,NULL);
}
// 解析 FIFO 中完整的一行页面命令，不把命令内容交给主机执行。
// home status next 只改变 GUI 页面，quit 则请求应用自己的循环退出。
static void command(const char *s) {
    if (!strcmp(s, "home")) set_page(0);
    else if (!strcmp(s, "status")) set_page(1);
    else if (!strcmp(s, "next")) set_page(current_page^1);
    else if (!strcmp(s, "quit")) running = 0;
}
// 非阻塞逐字符读取 FIFO，在换行时才把一条命令交给解析器。
// 静态缓冲跨本轮循环保存未结束行，超过容量则清除当前片段。
// 没有输入时立即回到 GUI 事件处理，不等待 UART 或抢占 shell 标准输入。
static void read_commands(void) {
    static char line[64]; static size_t used;
    char ch;
    while (command_fd >= 0 && read(command_fd, &ch, 1) == 1) {
        if (ch == '\n') { line[used] = 0; command(line); used = 0; }
        else if (used + 1 < sizeof line) line[used++] = ch;
        else used = 0;
    }
}
// 真实 fbdev 模式先查询硬件几何 颜色位域和映射长度，错误布局立即返回失败。
// 双页地址来自驱动当前 yoffset，据此选择另一个页作为首个后缓冲。
// FIFO 需要属于当前用户且是真正的 FIFO，打开时不跟随符号链接。
// 进程处理 SIGINT 和 SIGTERM 后释放自己映射的页和文件描述符。
// headless 模式仅供电脑图形烟测，不是实板显示的执行方式。
// 选择 headless 或真实 fbdev 后初始化 LVGL，并在循环中处理节拍 命令和退出。
int main(int argc, char **argv) {
    const char *fb = "/dev/fb0", *headless = NULL; unsigned frames = 0;
    for (int i=1;i<argc;i++) {
        if (!strcmp(argv[i], "--headless") && i+1<argc) headless=argv[++i];
        else if (!strcmp(argv[i], "--fb") && i+1<argc) fb=argv[++i];
        else if (!strcmp(argv[i], "--frames") && i+1<argc) frames=(unsigned)strtoul(argv[++i],NULL,10);
        else if (!strcmp(argv[i], "--fifo") && i+1<argc) fifo_path=argv[++i];
        else { fprintf(stderr,"Usage: %s [--fb PATH|--headless FILE] [--frames N] [--fifo PATH]\n",argv[0]); return 2; }
    }
    int fd=-1;
    if (headless) { stride=WIDTH*2; map_size=stride*HEIGHT; pixels=calloc(1,map_size); }
    else {
        struct fb_fix_screeninfo fix; struct fb_var_screeninfo var;
        fd=open(fb,O_RDWR); if(fd<0){perror(fb);return 1;}
        if(ioctl(fd,FBIOGET_FSCREENINFO,&fix)||ioctl(fd,FBIOGET_VSCREENINFO,&var)){perror("fb ioctl");return 1;}
        if(var.xres!=FB_PAGE_WIDTH||var.yres!=FB_PAGE_HEIGHT||var.yres_virtual<FB_PAGE_HEIGHT*2||var.bits_per_pixel!=16||var.red.offset!=11||var.red.length!=5||var.green.offset!=5||var.green.length!=6||var.blue.offset!=0||var.blue.length!=5||var.xoffset||(var.yoffset!=0&&var.yoffset!=FB_PAGE_HEIGHT)||fix.line_length<FB_PAGE_WIDTH*2){fprintf(stderr,"Unsupported framebuffer layout\n");return 1;}
        stride=fix.line_length;map_size=fix.smem_len;
        if(map_size<stride*FB_PAGE_HEIGHT*2){fprintf(stderr,"Framebuffer too small\n");return 1;}
        // 映射实际 framebuffer 后仍需遵守前后页所有权，映射本身不提供 DMA 一致性。
        fb_map=mmap(NULL,map_size,PROT_READ|PROT_WRITE,MAP_SHARED,fd,0);
        if(fb_map==MAP_FAILED){perror("mmap");return 1;}
        fb_fd=fd;fb_var=var;fb_back=(var.yoffset/FB_PAGE_HEIGHT)^1;pixels=calloc(1,stride*HEIGHT);
    }
    if(!pixels){perror("pixels");return 1;}
    struct stat st;
    if(!lstat(fifo_path,&st)) {
        if(!S_ISFIFO(st.st_mode)||st.st_uid!=geteuid()){fprintf(stderr,"Unsafe command FIFO\n");return 1;}
    } else if(errno==ENOENT) { if(mkfifo(fifo_path,0600)==0) own_fifo=true; }
    command_fd=open(fifo_path,O_RDWR|O_NONBLOCK|O_NOFOLLOW);
    if(command_fd<0) fprintf(stderr,"Command FIFO unavailable: %s\n",strerror(errno));
    signal(SIGINT,stop);signal(SIGTERM,stop);
    lv_init(); static lv_color_t drawbuf[WIDTH*24]; static lv_disp_draw_buf_t db;
    lv_disp_draw_buf_init(&db,drawbuf,NULL,WIDTH*24);
    lv_disp_drv_t d;lv_disp_drv_init(&d);d.hor_res=WIDTH;d.ver_res=HEIGHT;d.flush_cb=flush;d.draw_buf=&db;
    lv_disp_drv_register(&d);make_ui();
    uint64_t last=monotonic_ms();unsigned frame=0;
    while(running && (!frames||frame<frames)) {
        uint64_t now=monotonic_ms();lv_tick_inc((uint32_t)(now-last));last=now;
        read_commands();lv_timer_handler(); ++frame;
        struct timespec delay={0,5000000};nanosleep(&delay,NULL);
    }
    if(headless) { FILE*f=fopen(headless,"wb");if(!f||fwrite(pixels,1,map_size,f)!=map_size){perror("image write");return 1;}fclose(f);free(pixels); }
    else { munmap(fb_map,map_size);free(pixels);close(fd); }
    if(command_fd>=0)close(command_fd);
    if(own_fifo)unlink(fifo_path);
    printf("GUI render complete: regions=%u loops=%u\n",flush_count,frame);return 0;
}
