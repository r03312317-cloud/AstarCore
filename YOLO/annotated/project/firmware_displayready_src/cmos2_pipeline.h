// 架构导读：cmos2_pipeline。
// 裸机控制固件组件，提供本文件定义的状态检查、数据结构和服务函数。
#ifndef SOC_CMOS2_PIPELINE_H
#define SOC_CMOS2_PIPELINE_H
/* One Graph204 at a time, one IMG job at a time, one prefetch raw slot.
 * All reads/writes are owned by frame/run. An unfinished DMA is never
 * canceled by software, and no buffer is released before its last B.
 */
enum { PIPE_EMPTY=0, PIPE_CAMERA=1, PIPE_CAPTURED=2,
       PIPE_PREPROCESS=3, PIPE_READY=4 };
typedef struct {
    uint32_t state,raw,frame,run,arm_next;
    uint32_t camera_state,camera_written,camera_sensor,camera_errors;
    uint32_t display_started,display_done,first_conv,background_error;
    uint64_t capture_start,capture_end,pp_end;
    uint64_t display_start,display_end;
} soc_pipe;
static soc_pipe cmos2_pipe;

// 服务函数 cmos2_pipeline_poll。
// 接口参数：uint32_t completed；返回值及副作用由下列函数体定义。
// 参数入口：completed；类型、指针限定及返回约定沿用下列声明。
static void cmos2_pipeline_poll(uint32_t completed) {
    soc_pipe *p=&cmos2_pipe;
    // 控制边界：completed；仅在该条件成立时进入本分支。
    if(completed) p->first_conv=1u;
    if(p->state==PIPE_CAMERA) {
        // 硬件/可见性边界：uint32_t status=R32(CAMERA+8u);。
        // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
        uint32_t status=R32(CAMERA+8u);
        if(status&4u) {
            p->camera_state=status;
            // 硬件/可见性边界：p->camera_written=R32(CAMERA+12u);。
            // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
            p->camera_written=R32(CAMERA+12u);
            // 硬件/可见性边界：p->camera_sensor=R32(CAMERA+16u);。
            // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
            p->camera_sensor=R32(CAMERA+16u);
            // 硬件/可见性边界：p->camera_errors=R32(CAMERA+20u);。
            // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
            p->camera_errors=R32(CAMERA+20u);
            p->capture_end=ticks64();
            if(!(status&8u)||p->camera_errors ||
               p->camera_written!=1280u*720u||p->camera_sensor!=1280u*720u)
                p->background_error=CAMERA_BAD_FRAME;
            else p->state=PIPE_CAPTURED;
        } else if(ticks64()-p->capture_start>(uint64_t)HZ*5u)
            p->background_error=CAMERA_TIMEOUT;
    }
    if(p->display_started&&!p->display_done) {
        uint32_t r=image_poll_hardware();
        if(r==OK) {
            p->display_done=1u;p->display_end=ticks64();
            profile_counters[P_DISPLAY_RESIZE_TICKS]+=p->display_end-p->display_start;
        } else if(r!=IMAGE_IN_PROGRESS) p->background_error=r;
    }
    if(p->background_error)return;
    if(p->state==PIPE_CAPTURED && p->display_done && p->first_conv) {
        // 硬件/可见性边界：cache_invalidate(); /* only after capture DDR writes have retired */。
        // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
        cache_invalidate(); /* only after capture DDR writes have retired */
        uint32_t r=image_start_hardware(p->raw,0x80100000u,0u,soc_model_input_lut);
        if(r!=OK)p->background_error=r;
        else p->state=PIPE_PREPROCESS;
    }
    if(p->state==PIPE_PREPROCESS) {
        uint32_t r=image_poll_hardware();
        if(r==OK) {p->state=PIPE_READY;p->pp_end=ticks64();}
        else if(r!=IMAGE_IN_PROGRESS) p->background_error=r;
    }
}
// 服务函数 cmos2_graph_begin。
// 接口参数：void；返回值及副作用由下列函数体定义。
// 参数入口：无位置参数；类型、指针限定及返回约定沿用下列声明。
static void cmos2_graph_begin(void) {
    soc_pipe *p=&cmos2_pipe;
    if(!p->arm_next||p->background_error)return;
    if(camera_writing()||(R32(CAMERA+8u)&0x51u)!=0x51u) {
        p->background_error=CAMERA_NOT_READY;return;
    }
    // 硬件/可见性边界：R32(CAMERA+4u)=p->raw;fence_all();。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    R32(CAMERA+4u)=p->raw;fence_all();
    if(R32(CAMERA+4u)!=p->raw) {
        p->background_error=CAMERA_NOT_READY;return;
    }
    p->capture_start=ticks64();p->state=PIPE_CAMERA;
    // 硬件/可见性边界：R32(CAMERA)=1u;fence_all();。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    R32(CAMERA)=1u;fence_all();
}
// 服务函数 cmos2_graph_progress。
// 接口参数：uint32_t completed；返回值及副作用由下列函数体定义。
// 参数入口：completed；类型、指针限定及返回约定沿用下列声明。
static void cmos2_graph_progress(uint32_t completed) {
    cmos2_pipeline_poll(completed);
}
// 服务函数 cmos2_pipeline_join。
// 接口参数：uint32_t next_required；返回值及副作用由下列函数体定义。
// 参数入口：next_required；类型、指针限定及返回约定沿用下列声明。
static uint32_t cmos2_pipeline_join(uint32_t next_required) {
    uint64_t begin=ticks64();
    do {
        cmos2_pipeline_poll(cmos2_pipe.first_conv);
        if(cmos2_pipe.background_error)return cmos2_pipe.background_error;
        if(cmos2_pipe.display_done && (!next_required || cmos2_pipe.state==PIPE_READY))return OK;
    } while(ticks64()-begin<(uint64_t)HZ*6u);
    image_timeout_latched=1u; /* unfinished DMA: quarantine until reset */
    return IMAGE_HARDWARE_TIMEOUT;
}
#endif
