// 架构导读：preview_capture_prefetch。
// 裸机控制固件组件，提供本文件定义的状态检查、数据结构和服务函数。
#ifndef SOC_PREVIEW_CAPTURE_PREFETCH_H
#define SOC_PREVIEW_CAPTURE_PREFETCH_H
/* The live preview has released the camera before this starts. Reuse the
 * existing inference raw address only after preprocessing/graph/NMS finish.
 * Capture overlaps HDMI event confirmation and host telemetry, without
 * releasing or overwriting any preview/scanout buffer. */
typedef struct {
    uint32_t pending,raw,frame,run,started,used,discarded,bad;
    uint64_t begin;
} preview_capture_state;
static preview_capture_state preview_capture;

// 服务函数 preview_capture_matches。
// 接口参数：uint32_t raw,uint32_t frame,uint32_t run；返回值及副作用由下列函数体定义。
// 参数入口：raw, frame, run；类型、指针限定及返回约定沿用下列声明。
static uint32_t preview_capture_matches(uint32_t raw,uint32_t frame,uint32_t run) {
    return preview_capture.pending&&preview_capture.raw==raw&&
           preview_capture.frame==frame&&preview_capture.run==run;
}
// 服务函数 preview_capture_start。
// 接口参数：uint32_t raw,uint32_t frame,uint32_t run；返回值及副作用由下列函数体定义。
// 参数入口：raw, frame, run；类型、指针限定及返回约定沿用下列声明。
static uint32_t preview_capture_start(uint32_t raw,uint32_t frame,uint32_t run) {
    if(raw!=0x81000000u||!frame||(frame&0x80000000u)||!run)return BAD_RANGE;
    if(preview_capture.pending||image_async_owned||live_preview.enabled||
       live_preview.resize_phase||camera_writing())return NPU_BUSY;
    if((R32(CAMERA+8u)&0x51u)!=0x51u)return CAMERA_NOT_READY;
    // 硬件/可见性边界：R32(CAMERA+4u)=raw;fence_all();。
    R32(CAMERA+4u)=raw;fence_all();
    if(R32(CAMERA+4u)!=raw)return CAMERA_NOT_READY;
    preview_capture.raw=raw;preview_capture.frame=frame;preview_capture.run=run;
    preview_capture.begin=ticks64();preview_capture.pending=1u;
    preview_capture.started++;
    R32(CAMERA)=1u;fence_all();
    return OK;
}
// 服务函数 preview_capture_join。
// 接口参数：uint32_t snapshot[4],uint32_t discard；返回值及副作用由下列函数体定义。
// 参数入口：snapshot, discard；类型、指针限定及返回约定沿用下列声明。
static uint32_t preview_capture_join(uint32_t snapshot[4],uint32_t discard) {
    if(!preview_capture.pending)return BAD_COMMAND;
    while(!(R32(CAMERA+8u)&4u)) {
        if(ticks64()-preview_capture.begin>(uint64_t)HZ*5u)return CAMERA_TIMEOUT;
    }
    /* The camera's DONE contract includes its last AXI write response. */
    fence_all();snapshot[0]=R32(CAMERA+8u);snapshot[1]=R32(CAMERA+12u);
    snapshot[2]=R32(CAMERA+16u);snapshot[3]=R32(CAMERA+20u);
    if(snapshot[0]&2u)return CAMERA_NOT_READY;
    preview_capture.pending=0u;
    if(discard)preview_capture.discarded++;
    if(!(snapshot[0]&8u)||snapshot[3]||snapshot[1]!=1280u*720u||snapshot[2]!=1280u*720u) {
        preview_capture.bad++;return CAMERA_BAD_FRAME;
    }
    if(!discard)preview_capture.used++;
    return OK;
}
#endif
