/* CMOS2 720p V1 HWC -> Graph204/S3 -> real palm NMS -> single HDMI.
 * Independent ABI; the 5MP V2 workflow source remains available for regression.
 * This is functional integration, not a claim of realtime inference. */
#include "display_cmos2.h"
#include "gesture_selection.h"
#include "cmos2_recovery.h"
#include "frame_pipeline_contract.h"
#include "cmos2_pipeline.h"
/* Candidate 20: capture belongs to the shared frame pool. */
#define CMOS2_WORKFLOW_ID 0x31563243u /* C2V1 */
static uint32_t cmos2_continuous,cmos2_completed,cmos2_last_status;
static uint32_t cmos2_attempted,cmos2_rejected,cmos2_recovered,cmos2_fatal;
static uint32_t cmos2_last_error,cmos2_last_bad_frame,cmos2_last_bad_run,cmos2_last_capture_errors;
static uint64_t cmos2_retry_after;
static uint32_t cmos2_session[WORKFLOW_WORDS];
static uint8_t cmos2_last_reply[288];
static uint32_t cmos2_async_stage,cmos2_stop_requested;
static void cmos2_idle_step(void);
/* Bounded display-only color-bar diagnostic. It uses the same uncached source,
 * IMG resize and atomic display-commit path as a normal frame; it does not
 * start camera capture, graph/NMS, or the autonomous loop. */
static uint32_t cmos2_display_colorbars(uint32_t argument) {
    static const uint16_t colors[8]={0xffffu,0xffe0u,0x07ffu,0x07e0u,0xf81fu,0xf800u,0x001fu,0x0000u};
    const uint32_t source=0x81000000u,fb=0x82000000u,frame=1u,run=1u;
    uint32_t result=OK,state=0u,armed=0u;
    data_len=48u;
    for(uint32_t i=0;i<data_len;i++)data[i]=0u;
    set32(data,0x31524142u);set32(data+4,1u);set32(data+8,680u);set32(data+12,340u);
    set32(data+16,fb);set32(data+20,frame);set32(data+24,run);
    if(argument || cmos2_continuous || camera_writing() || R32(DISPLAY_MMIO)!=DISPLAY_ID || R32(VIDEO_MMIO)!=VIDEO_ID) { result=BAD_COMMAND;goto done; }
    state=R32(DISPLAY_MMIO+4u);
    if((state&2u) || ((state&16u)&&R32(DISPLAY_MMIO+0x30u)==fb)){result=DISPLAY_BAD_STATE;goto done;}
    for(uint32_t y=0;y<720u;y++)for(uint32_t pair=0;pair<640u;pair++) {
        uint32_t c=colors[pair/80u];R32(source+(y*640u+pair)*4u)=c|(c<<16);
    }
    fence_all();cache_invalidate();
    R32(VIDEO_MMIO)=0u;R32(VIDEO_MMIO+8u)=run;R32(VIDEO_MMIO+12u)=frame;R32(VIDEO_MMIO)=1u;
    R32(DISPLAY_MMIO+8u)=fb;R32(DISPLAY_MMIO+12u)=frame;R32(DISPLAY_MMIO+0x54u)=run;fence_all();
    R32(DISPLAY_MMIO)=1u;fence_all();armed=1u;state=R32(DISPLAY_MMIO+4u);
    if(!(state&2u)||(state&0x00ff0000u)){result=DISPLAY_BAD_STATE;goto done;}
    result=image_display_cmos2(source,fb);if(result!=OK)goto done;
    fence_all();R32(DISPLAY_MMIO+16u)=0u;R32(DISPLAY_MMIO+20u)=0u;R32(DISPLAY_MMIO+24u)=0u;
    R32(DISPLAY_MMIO+28u)=0u;R32(DISPLAY_MMIO+32u)=0u;R32(DISPLAY_MMIO)=2u;fence_all();
    uint64_t began=ticks64();
    for(;;) {
        state=R32(DISPLAY_MMIO+4u);
        if(state&0x00ff0000u){result=DISPLAY_WRITE_ERROR;goto done;}
        if(R32(DISPLAY_MMIO+0x28u)==SOC_CMOS2_DISPLAY_BYTES&&R32(DISPLAY_MMIO+0x2cu)==0u)break;
        if(ticks64()-began>(uint64_t)HZ*5u){result=DISPLAY_WRITE_TIMEOUT;goto done;}
    }
    R32(DISPLAY_MMIO)=4u;fence_all();state=R32(DISPLAY_MMIO+4u);armed=0u;
    if(!(state&4u)||(state&0x00ff0000u)||R32(DISPLAY_MMIO+0x30u)!=fb||R32(DISPLAY_MMIO+0x34u)!=frame||R32(DISPLAY_MMIO+0x58u)!=run)result=DISPLAY_BAD_STATE;
done:
    if(armed && R32(DISPLAY_MMIO+0x2cu)==0u){R32(DISPLAY_MMIO)=8u;fence_all();}
    set32(data+28,result);set32(data+32,R32(DISPLAY_MMIO+4u));set32(data+36,R32(DISPLAY_MMIO+0x24u));set32(data+40,R32(DISPLAY_MMIO+0x28u));set32(data+44,R32(DISPLAY_MMIO+0x2cu));
    return result;
}
static uint32_t cmos2_execute(const uint32_t c[WORKFLOW_WORDS]) {
    static struct {
        uint32_t phase,result,detected,chosen,xy[2],score,klass,display_state,video_state;
        uint32_t ready_ok,hdmi_ok,inference_raw,inference_generation,camera_snap[4],display_fb;
        uint64_t t[11],capture_end;
    } frame;
    uint32_t pipemode=(c[1]==2u),from_prefetch=0u,pooled=c[39];
    if(cmos2_async_stage==1u)goto pooled_input_resume;
    if(cmos2_async_stage==2u)goto graph_resume;
    memset(&frame,0,sizeof(frame));frame.inference_raw=c[2];frame.display_fb=c[4];
    static const uint32_t model_words[8]={0x18fd72fbu,0x092deebdu,0x240531a5u,0x23e272adu,
        0xfb273633u,0x55c7c15au,0x4a0702d2u,0xf5b07c90u};
    if(c[0]!=CMOS2_WORKFLOW_ID||(c[1]!=1u&&c[1]!=2u)||
       (c[2]!=0x81000000u&&!(pipemode&&c[2]==0x81200000u))||c[3]!=0x80100000u||
       (c[4]!=0x82000000u&&c[4]!=0x82100000u)||
       !range(c[2],SOC_PP320_SOURCE_BYTES)||!range(c[3],SOC_PP320_TARGET_BYTES)||
       !range(c[4],SOC_CMOS2_DISPLAY_BYTES)||(c[6]&3u)||(c[7]&3u)||
       !range(c[6],GRAPH_MAX_OPS*GRAPH_WORDS_PER_OP*4u)||
       !range(c[7],GRAPH_MAX_OPS*GRAPH_TRACE_WORDS*4u)||
       c[13]!=SOC_GESTURE_CLASS_COUNT||!soc_gesture_filter_valid(c[18])||!c[16]||c[16]>1024u||!c[17]||c[17]>64u||c[17]>c[16]||
       c[6]>=0x81000000u-GRAPH_MAX_OPS*GRAPH_WORDS_PER_OP*4u||
       c[7]>=0x81000000u-GRAPH_MAX_OPS*GRAPH_TRACE_WORDS*4u||
       !range(c[8],c[9])||c[8]+c[9]>0x81000000u||
       !range(c[10],96u)||c[10]>0x81000000u-96u||
       !range(c[11],c[17]*sizeof(soc_detection))||c[11]>0x81000000u-c[17]*sizeof(soc_detection)||
       !range(c[12],c[16]*sizeof(soc_detection))||c[12]>0x81000000u-c[16]*sizeof(soc_detection)||
       (c[19]&~(GRAPH_WINDOW_FLAG|GRAPH_CONCAT_FLAG))!=(GRAPH_FAST_FLAG|GRAPH_S3_FLAG|GRAPH_S3_FUSE_LUT_FLAG|GRAPH_PROFILE_FLAG)||
       !c[20]||c[21]>1u||c[30]!=build_word(0u)||c[31]!=build_word(8u)||
       c[32]!=2560u||c[33]!=0x35363552u||c[34]!=1280u||c[35]!=720u||
       c[36]!=1280u||c[37]!=680u||c[38]!=340u||(c[39]&~LIVE_FLAG)||
       (c[39]&&(pipemode||!c[21]||(c[5]&0x80000000u)))||
       R32(c[6])!=10u||R32(c[6]+4u)!=c[3])return BAD_RANGE;
    for(uint32_t i=0;i<8u;i++)if(c[22u+i]!=model_words[i])return BAD_RANGE;
    if(pipemode || c[39]) {
        /* Capability and no-alias proof precede either camera owner. */
        if(!(R32(DISPLAY_MMIO+4u)&0x80000000u) ||
           !(R32(CAMERA+0x60u)&IMAGE_CAPABILITY) ||
           R32(IMAGE_MMIO+0x20u)!=IMAGE_ID)return DISPLAY_BAD_STATE;
        /* Pooled ARM proves this before sealing GRAPH_EXECUTOR. The copied session,
         * descriptors and model stay immutable until STOP; only frame/run
         * IDs and the legacy display selector advance between frames. */
        if(!pooled&&!cmos2_graph_input_lifetime(c))return GRAPH_BAD_DESCRIPTOR;
        if(pipemode && cmos2_pipe.state!=PIPE_EMPTY &&
           (cmos2_pipe.state!=PIPE_READY || cmos2_pipe.raw!=c[2] ||
            cmos2_pipe.frame!=c[5] || cmos2_pipe.run!=c[20]))return NPU_BUSY;
    }
    if(pooled&&!cmos2_continuous)return BAD_COMMAND;
    if((camera_writing()||image_async_owned)&&!(pooled&&live_preview.enabled))return CAMERA_NOT_READY;
    if(R32(DISPLAY_MMIO)!=DISPLAY_ID||R32(VIDEO_MMIO)!=VIDEO_ID)return BAD_COMMAND;
    if(R32(CAMERA+0x70u)!=1u || R32(CAMERA+0x18u)!=((720u<<16)|1280u))return CAMERA_NOT_READY;
    if(R32(0x60000008u)!=HZ)return DISPLAY_BAD_STATE;
    if(!pooled&&(R32(DISPLAY_MMIO+4u)&2u)) {
        if(R32(DISPLAY_MMIO+0x2cu)!=0u)return DISPLAY_BAD_STATE;
        R32(DISPLAY_MMIO)=8u;fence_all();
    }
    if(R32(DISPLAY_MMIO+0x30u)==c[4]&&(R32(DISPLAY_MMIO+4u)&16u))return DISPLAY_BAD_STATE;
    if(conv_service_frame_begin(c[5],c[20])!=OK)return NPU_ERROR;
    conv_service_workflow_context=1u;
    // Arm one-shot hardware event snapshots before accepting this START.
    rv32_perf_begin(c[5],c[20]);
    if(!pooled) {
        R32(VIDEO_MMIO)=0u;R32(VIDEO_MMIO+8u)=c[20];R32(VIDEO_MMIO+12u)=c[5];R32(VIDEO_MMIO)=1u;
    }
    fence_all();profile_session=1u;frame.t[0]=ticks64();frame.phase=1;frame.t[1]=ticks64();
    /* A READY prefetch was captured/PP-completed during the preceding graph.
     * The producer may not be reused until the hardware's final B response.
     */
    if(pooled) {
        frame.result=live_preview_begin();if(frame.result!=OK)goto finish;
        cmos2_async_stage=1u;
pooled_input_resume:
        frame.result=live_preview_inference_input_step(c[3],soc_model_input_lut,frame.camera_snap,
                &frame.inference_raw,&frame.inference_generation,&frame.t[0],&frame.capture_end);
        if(frame.result==IMAGE_IN_PROGRESS)return GRAPH_EXECUTOR_PENDING;
        if(frame.result!=OK)goto finish;
        cmos2_async_stage=0u;frame.t[1]=frame.capture_end;frame.t[2]=ticks64();
    } else if(pipemode && cmos2_pipe.state==PIPE_READY) {
        from_prefetch=1u;
        frame.t[0]=cmos2_pipe.capture_start;
        frame.capture_end=cmos2_pipe.capture_end;
        frame.t[1]=frame.capture_end;frame.t[2]=cmos2_pipe.pp_end;
        frame.camera_snap[0]=cmos2_pipe.camera_state;
        frame.camera_snap[1]=cmos2_pipe.camera_written;
        frame.camera_snap[2]=cmos2_pipe.camera_sensor;
        frame.camera_snap[3]=cmos2_pipe.camera_errors;
        cmos2_pipe.state=PIPE_EMPTY;
    } else {
        if(c[21]) {
            uint32_t state=R32(CAMERA+8u);
            if((state&0x51u)!=0x51u){frame.result=CAMERA_NOT_READY;goto finish;}
            R32(CAMERA+4u)=c[2];fence_all();
            if(R32(CAMERA+4u)!=c[2]){frame.result=CAMERA_NOT_READY;goto finish;}
            R32(CAMERA)=1u;fence_all();
            while(!(R32(CAMERA+8u)&4u)) {
                if(ticks64()-frame.t[0]>(uint64_t)HZ*5u){frame.result=CAMERA_TIMEOUT;goto finish;}
            }
            fence_all();state=R32(CAMERA+8u);
            frame.camera_snap[0]=state;frame.camera_snap[1]=R32(CAMERA+12u);
            frame.camera_snap[2]=R32(CAMERA+16u);frame.camera_snap[3]=R32(CAMERA+20u);
            if(!(state&8u)||frame.camera_snap[3]||frame.camera_snap[1]!=1280u*720u||
               frame.camera_snap[2]!=1280u*720u){frame.result=CAMERA_BAD_FRAME;goto finish;}
        }
        cache_invalidate();
        frame.capture_end=ticks64();frame.t[1]=frame.capture_end;
        frame.result=image_preprocess320(c[2],c[3],soc_model_input_lut);
        if(frame.result!=OK)goto finish;
        fence_all();frame.t[2]=ticks64();
    }
    profile_counters[P_V2_PREPROCESS_TICKS]+=frame.t[2]-frame.t[1];
    if(pipemode) {
        cmos2_pipe.display_started=0u;cmos2_pipe.display_done=0u;
        cmos2_pipe.first_conv=0u;cmos2_pipe.background_error=0u;
        cmos2_pipe.arm_next=(cmos2_continuous && c[21] &&
                             c[5]!=0xffffffffu && c[20]!=0xffffffffu);
        if(cmos2_pipe.arm_next) {
            cmos2_pipe.raw=c[2]^0x00200000u;
            cmos2_pipe.frame=c[5]+1u;
            cmos2_pipe.run=c[20]+1u;
        }
        /* ARM and start IMG display resize BEFORE Graph204: the first graph
         * convolution can now overlap the image writer. */
        R32(DISPLAY_MMIO+8u)=c[4];R32(DISPLAY_MMIO+12u)=c[5];
        R32(DISPLAY_MMIO+0x54u)=c[20];fence_all();
        R32(DISPLAY_MMIO)=1u;fence_all();
        frame.display_state=R32(DISPLAY_MMIO+4u);
        if(!(frame.display_state&2u)||(frame.display_state&0x00ff0000u)){
            frame.result=DISPLAY_BAD_STATE;goto finish;
        }
        cmos2_pipe.display_start=ticks64();
        frame.result=image_start_hardware(c[2],c[4],1u,0);
        if(frame.result!=OK)goto finish;
        cmos2_pipe.display_started=1u;
    }
    /* Continuous preview was started before acquiring the input frame. */
    frame.phase=2;data_len=16u;
    set32(data,c[19]|GRAPH_MAX_OPS);set32(data+4,c[7]);set32(data+8,c[8]);set32(data+12,c[9]);
    /* Lease only exists inside this checked Graph204 invocation. The graph
     * itself repeats its full descriptor validation before prefetch START. */
    cmos2_graph_active=pipemode;camera_model_lease=pipemode||pooled;
    frame.t[3]=ticks64();
    if(pooled) {
        frame.result=graph_hw_start();if(frame.result!=OK)goto finish;
        cmos2_async_stage=2u;return GRAPH_EXECUTOR_PENDING;
graph_resume:
        live_preview_service();
        frame.result=graph_hw_poll();if(frame.result==GRAPH_EXECUTOR_PENDING)return GRAPH_EXECUTOR_PENDING;
        if(frame.result==OK)frame.result=graph_hw_finish();
        cmos2_async_stage=0u;
    } else frame.result=graph_run(c[6]);
    frame.t[4]=ticks64();cmos2_graph_active=0u;
    /* The pool keeps capturing and previewing across graph completions. */
    if(frame.result!=OK)goto finish;
    if(pipemode && cmos2_pipe.background_error){frame.result=cmos2_pipe.background_error;goto finish;}
    frame.phase=3;data_len=40u;
    set32(data,3u);set32(data+4,c[13]);set32(data+8,320u);set32(data+12,320u);
    set32(data+16,c[14]);set32(data+20,c[15]);set32(data+24,c[16]);set32(data+28,c[17]);
    set32(data+32,c[11]);set32(data+36,c[12]);frame.result=detect_run(c[10]);
    if(frame.result!=OK)goto finish;
    frame.detected=get32(data+8);
    soc_gesture_selection selection=soc_select_cmos2_gesture(
        (const volatile soc_detection *)(uintptr_t)c[11],frame.detected,c[18]);
    frame.xy[0]=selection.xy[0];frame.xy[1]=selection.xy[1];
    frame.score=selection.score;frame.klass=selection.class_id;frame.chosen=selection.chosen;
    frame.t[5]=ticks64();frame.phase=4;
    if(pooled) {
        live_preview.overlay_xy1=frame.xy[0];live_preview.overlay_xy2=frame.xy[1];
        live_preview.overlay_score=frame.score;live_preview.overlay_class=frame.klass;live_preview.overlay_count=frame.chosen;
        frame.result=live_preview_metadata(c[5],c[20],&frame.display_fb);
        if(frame.result!=OK)goto finish;
        /* V3 READY is an inference frame.result queued for asynchronous display.
         * No fabricated vblank/HDMI-TE timestamp and no preview drain. */
        frame.t[7]=ticks64();frame.ready_ok=1u;frame.phase=9u;goto finish;
    }
    uint64_t wait_start=ticks64();
    if(pipemode) {
        /* Poll may also start next PP, but only once Conv0 and the display
         * resize have both retired. The scoped FB B proof is independent. */
        frame.result=cmos2_pipeline_join(0u);
        if(frame.result!=OK)goto finish;
    } else {
        R32(DISPLAY_MMIO+8u)=c[4];R32(DISPLAY_MMIO+12u)=c[5];R32(DISPLAY_MMIO+0x54u)=c[20];
        fence_all();R32(DISPLAY_MMIO)=1u;fence_all();frame.display_state=R32(DISPLAY_MMIO+4u);
        if(!(frame.display_state&2u)||(frame.display_state&0x00ff0000u)){frame.result=DISPLAY_BAD_STATE;goto finish;}
        cache_invalidate();
        frame.result=image_display_cmos2(c[2],c[4]);
        if(frame.result!=OK)goto finish;
        fence_all();profile_counters[P_DISPLAY_RESIZE_TICKS]+=ticks64()-frame.t[5];
    }
    R32(DISPLAY_MMIO+16u)=frame.xy[0];R32(DISPLAY_MMIO+20u)=frame.xy[1];
    R32(DISPLAY_MMIO+24u)=frame.score;R32(DISPLAY_MMIO+28u)=frame.klass;R32(DISPLAY_MMIO+32u)=frame.chosen;
    R32(DISPLAY_MMIO)=2u;fence_all();frame.phase=5;
    wait_start=ticks64();
    for(;;) {
        frame.display_state=R32(DISPLAY_MMIO+4u);
        if(frame.display_state&0x00ff0000u){frame.result=DISPLAY_WRITE_ERROR;goto finish;}
        if(R32(DISPLAY_MMIO+0x28u)==SOC_CMOS2_DISPLAY_BYTES&&R32(DISPLAY_MMIO+0x2cu)==0u)break;
        if(ticks64()-wait_start>(uint64_t)HZ*5u){frame.result=DISPLAY_WRITE_TIMEOUT;goto finish;}
    }
    frame.t[6]=fixed_snapshot(DISPLAY_MMIO+0x60u);R32(DISPLAY_MMIO)=4u;fence_all();
    frame.display_state=R32(DISPLAY_MMIO+4u);frame.t[7]=fixed_snapshot(DISPLAY_MMIO+0x68u);
    if(!(frame.display_state&4u)||(frame.display_state&0x00ff0000u)||R32(DISPLAY_MMIO+0x30u)!=frame.display_fb||
       R32(DISPLAY_MMIO+0x34u)!=c[5]||R32(DISPLAY_MMIO+0x58u)!=c[20]||
       R32(DISPLAY_MMIO+0x48u)!=frame.chosen){frame.result=DISPLAY_BAD_STATE;goto finish;}
    frame.ready_ok=1u;frame.phase=6;
    profile_counters[P_DDR_FRAME_TO_DISPLAY_READY_TICKS]+=frame.t[7]-frame.t[0];
    // Digital frame completion is a distinct endpoint from READY. First-ever
    // publication switches the standby bars to DDR at a safe frame boundary.
    R32(VIDEO_MMIO+0x10u)=2u;fence_all();wait_start=ticks64();frame.phase=7;
    for(;;) {
        frame.video_state=R32(VIDEO_MMIO+4u);
        if(frame.video_state&8u)break;
        if(ticks64()-wait_start>(uint64_t)HZ*2u){frame.result=HDMI_FRAME_TIMEOUT;goto finish;}
    }
    frame.t[8]=fixed_snapshot(VIDEO_MMIO+0x30u);frame.t[9]=fixed_snapshot(VIDEO_MMIO+0x38u);
    frame.t[10]=fixed_snapshot(VIDEO_MMIO+0x40u);
    if((frame.video_state&0x1eu)!=0x1eu||R32(VIDEO_MMIO+0x18u)!=0u||R32(VIDEO_MMIO+0x2cu)!=0u)
        {frame.result=HDMI_FRAME_ERROR;goto finish;}
    frame.hdmi_ok=1u;frame.phase=8;
    if(pipemode) {
        frame.result=cmos2_pipeline_join(cmos2_pipe.arm_next);
        if(frame.result!=OK)goto finish;
    }
finish:
    cmos2_async_stage=0u;
    if(pooled&&frame.result!=OK&&(R32(GRAPH_EXECUTOR_MMIO+4u)&9u))conv_service_timeout_latched=1u;
    if(live_preview.enabled&&frame.result!=OK)live_preview_end();
    if(pooled&&live_preview.fault&&frame.result==OK)frame.result=live_preview.fault;
    if(pooled) {frame.display_state=R32(DISPLAY_MMIO+4u);frame.video_state=R32(VIDEO_MMIO+4u);}
    cmos2_graph_active=0u;camera_model_lease=0u;
    if(pipemode && frame.result!=OK &&
       (cmos2_pipe.state==PIPE_CAMERA || cmos2_pipe.state==PIPE_PREPROCESS ||
        image_async_owned))image_timeout_latched=1u;
    conv_service_workflow_context=0u;
    rv32_perf_end(frame.result);
    for(uint32_t i=0;i<288u;i++)data[i]=0;
    set32(data,CMOS2_WORKFLOW_ID);set32(data+4,pooled?3u:c[1]);set32(data+8,frame.phase);set32(data+12,frame.result);
    set32(data+16,c[5]);set32(data+20,frame.display_fb);set32(data+24,frame.detected);set32(data+28,frame.chosen);
    set32(data+32,frame.xy[0]);set32(data+36,frame.xy[1]);set32(data+40,frame.score);set32(data+44,frame.klass);
    set32(data+48,frame.display_state);set32(data+52,R32(0x60000008u));set32(data+56,c[20]);set32(data+60,c[21]);
    set32(data+64,frame.video_state);set32(data+68,R32(VIDEO_MMIO+0x2cu));
    set32(data+72,R32(VIDEO_MMIO+0x48u));set32(data+76,R32(VIDEO_MMIO+0x14u));
    set32(data+80,R32(VIDEO_MMIO+0x18u));set32(data+84,R32(VIDEO_MMIO+0x1cu));
    set32(data+88,R32(VIDEO_MMIO+0x20u));set32(data+92,R32(VIDEO_MMIO+0x4cu));
    for(uint32_t i=0;i<11u;i++)set64(data+96u+i*8u,frame.t[i]);
    set32(data+184,R32(DISPLAY_MMIO+0x24u));set32(data+188,R32(DISPLAY_MMIO+0x28u));
    set32(data+192,R32(DISPLAY_MMIO+0x4cu));set32(data+196,R32(VIDEO_MMIO+0x24u));
    set32(data+200,R32(VIDEO_MMIO+0x28u));set32(data+204,R32(S2_MMIO+0x10u));
    set32(data+208,R32(S2_MMIO+0x1cu));set32(data+212,R32(S2_MMIO+0x0cu));
    set32(data+216,c[19]);set32(data+220,GRAPH_MAX_OPS);
    set32(data+224,frame.ready_ok|(frame.hdmi_ok<<1)|(c[21]?16u:0u)|(pooled?32u:0u));
    if(pipemode) {
        uint32_t f=1u|(from_prefetch<<1)|(cmos2_pipe.display_done<<2)|
                   (cmos2_pipe.first_conv<<3)|((frame.result!=OK)<<4);
        set32(data+228,f);set32(data+232,c[2]);
        set32(data+236,cmos2_pipe.arm_next?cmos2_pipe.raw:0u);
        set32(data+240,cmos2_pipe.state);
        set32(data+244,cmos2_pipe.background_error);
        set64(data+248,ticks64());
    } else if(c[39]) {
        set32(data+228,c[39]);set32(data+232,live_preview.last_good);
        set32(data+236,frame.inference_raw);set32(data+240,frame.inference_generation);
        set32(data+244,live_preview.overlay_frame);
        set64(data+248,ticks64());
    }
    set64(data+256,frame.capture_end);
    set32(data+264,frame.camera_snap[0]);set32(data+268,frame.camera_snap[1]);
    set32(data+272,frame.camera_snap[2]);set32(data+276,frame.camera_snap[3]);
    set32(data+280,R32(CAMERA+0x70u));set32(data+284,SOC_CMOS2_DISPLAY_BYTES);
    return frame.result;
}

static uint32_t cmos2_read_config(uint32_t address,uint32_t c[WORKFLOW_WORDS]) {
    if(data_len)return BAD_LENGTH;
    if((address&3u)||!range(address,WORKFLOW_WORDS*4u)||address>=0x81000000u-WORKFLOW_WORDS*4u)
        return BAD_RANGE;
    for(uint32_t i=0;i<WORKFLOW_WORDS;i++)c[i]=R32(address+i*4u);
    // Prevent a generated tensor, trace or result overwriting configuration.
    if(overlap(address,160u,c[3],SOC_PP320_TARGET_BYTES)||
       overlap(address,160u,c[6],GRAPH_MAX_OPS*GRAPH_WORDS_PER_OP*4u)||
       overlap(address,160u,c[7],GRAPH_MAX_OPS*GRAPH_TRACE_WORDS*4u)||
       overlap(address,160u,c[8],c[9])||overlap(address,160u,c[11],c[17]*sizeof(soc_detection))||
       overlap(address,160u,c[12],c[16]*sizeof(soc_detection)))return BAD_RANGE;
    return OK;
}
static uint32_t cmos2_run(uint32_t address) {
    uint32_t c[WORKFLOW_WORDS];
    if(cmos2_continuous)return NPU_BUSY;
    uint32_t status=cmos2_read_config(address,c);
    return status==OK?cmos2_execute(c):status;
}
static void cmos2_control(uint32_t address) {
    if(address==0u) {
        if(data_len){reply(BAD_LENGTH,0);return;}
        cmos2_stop_requested=1u;
        while(cmos2_async_stage && cmos2_continuous){live_preview_service();cmos2_idle_step();}
        cmos2_continuous=0u;cmos2_retry_after=0u;
        if(live_preview.enabled) {
            uint32_t pr=live_preview_end();if(pr!=OK){reply(pr,0);return;}
        }
        if(cmos2_pipe.state==PIPE_CAMERA || cmos2_pipe.state==PIPE_PREPROCESS || image_async_owned)
            {image_timeout_latched=1u;reply(NPU_BUSY,0);return;}
        cmos2_pipe.state=PIPE_EMPTY;cmos2_pipe.arm_next=0u;
        if(R32(GRAPH_EXECUTOR_MMIO+4u)&9u){reply(NPU_BUSY,0);return;}
        reply(OK,0);return;
    }
    if(address==0xfffffffbu) {
        if(data_len){reply(BAD_LENGTH,0);return;}
        set32(data,GRAPH_EXECUTOR_ID);set32(data+4,1u);set32(data+8,cmos2_async_stage);set32(data+12,HZ);
        const uint32_t offsets[16]={4u,0x0cu,0x18u,0x20u,0x24u,0x30u,0x34u,0x38u,0x3cu,0x40u,0x44u,0x48u,0x4cu,0x50u,0x68u,0x6cu};
        for(uint32_t i=0;i<16u;i++)set32(data+16u+4u*i,R32(GRAPH_EXECUTOR_MMIO+offsets[i]));
        set32(data+80u,graph_executor_starts);set32(data+84u,graph_executor_finishes);set32(data+88u,graph_executor_polls);set32(data+92u,graph_executor_ready);
        set64(data+96u,graph_executor_compile_ticks);set64(data+104u,graph_executor_cpu_poll_ticks);reply(OK,112u);return;
    }
    if(address==0xfffffffcu) {
        if(data_len){reply(BAD_LENGTH,0);return;}
        set32(data,0x30325046u);set32(data+4,1u);
        set32(data+8,live_preview.resize_started);set32(data+12,live_preview.resize_completed);
        set32(data+16,live_pool.next_generation);set32(data+20,live_preview.inference_frames);
        set32(data+24,live_pool.reclaimed);set32(data+28,live_pool.rejected);
        set64(data+32,live_preview.drain_ticks);set64(data+40,live_preview.inference_wait_ticks);
        set32(data+48,live_pool.capture_slot);set32(data+52,live_preview.resize_phase);
        set32(data+56,live_preview.fault);set32(data+60,HZ);
        set32(data+64,live_preview.metadata_published);set32(data+68,live_preview.metadata_acknowledged);
        set32(data+72,live_preview.overlay_acknowledged_frame);set32(data+76,live_preview.metadata_pending);
        set32(data+80,live_preview.service_calls);set32(data+84,live_pool.protocol_errors);
        set32(data+88,live_preview.infer_last_generation);set32(data+92,live_preview.preview_last_generation);
        for(uint32_t i=0;i<FRAME_POOL_SLOTS;i++) {
            set32(data+96u+i*16u,live_pool.slot[i].base);set32(data+100u+i*16u,live_pool.slot[i].state);
            set32(data+104u+i*16u,live_pool.slot[i].readers);set32(data+108u+i*16u,live_pool.slot[i].generation);
        }
        reply(OK,144u);return;
    }
    if(address==0xfffffffdu) {
        if(data_len){reply(BAD_LENGTH,0);return;}
        live_preview_ack();
        set32(data,0x3156504cu);set32(data+4,1u);
        set32(data+8,live_preview.enabled);set32(data+12,live_preview.attempted);
        set32(data+16,live_preview.valid);set32(data+20,live_preview.dropped);
        set32(data+24,live_preview.published);set32(data+28,live_preview.acknowledged);
        set32(data+32,live_preview.fault);set32(data+36,live_preview.overlay_frame);
        set32(data+40,live_preview.last_display_fb);set32(data+44,live_preview.sequence);
        set64(data+48,live_preview.first_started);set64(data+56,live_preview.last_ack);
        reply(OK,64u);return;
    }
    if(address==0xfffffffeu) {
        if(data_len){reply(BAD_LENGTH,0);return;}
        set32(data,0x32533243u);set32(data+4,1u);set32(data+8,cmos2_continuous);
        set32(data+12,cmos2_attempted);set32(data+16,cmos2_completed);
        set32(data+20,cmos2_rejected);set32(data+24,cmos2_recovered);set32(data+28,cmos2_fatal);
        set32(data+32,cmos2_last_error);set32(data+36,cmos2_last_bad_frame);
        set32(data+40,cmos2_last_bad_run);set32(data+44,cmos2_last_capture_errors);
        reply(OK,48u);return;
    }
    if(address==0xffffffffu) {
        if(data_len){reply(BAD_LENGTH,0);return;}
        set32(data,CMOS2_WORKFLOW_ID);set32(data+4,cmos2_continuous);
        set32(data+8,cmos2_completed);set32(data+12,cmos2_last_status);
        for(uint32_t i=0;i<288u;i++)data[16u+i]=cmos2_last_reply[i];
        reply(OK,304u);return;
    }
    if(conv_service_timeout_latched||(R32(GRAPH_EXECUTOR_MMIO+4u)&9u)||
       cmos2_continuous||live_preview.enabled||!frame_pool_quiescent(&live_pool)||
       live_inference_lease.valid||live_resize_lease.valid){reply(NPU_BUSY,0);return;}
    if((R32(0x50000004u)&15u)!=3u){reply(DDR_UNAVAILABLE,0);return;}
    if((R32(NPU+0x0cu)&3u)!=1u){reply(NPU_BUSY,0);return;}
    uint32_t status=cmos2_read_config(address,cmos2_session);
    if(status!=OK){reply(status,0);return;}
    // Deferred execution runs the same complete validator before ANY start.
    // The arm reply is not a capture or inference completion acknowledgement.
    if(cmos2_session[0]!=CMOS2_WORKFLOW_ID||
       (cmos2_session[1]!=1u&&cmos2_session[1]!=2u)||cmos2_session[21]!=1u)
        {reply(BAD_RANGE,0);return;}
    if((cmos2_session[1]==2u || cmos2_session[39]) &&
       (cmos2_pipe.state!=PIPE_EMPTY || !cmos2_graph_input_lifetime(cmos2_session)))
        {reply(GRAPH_BAD_DESCRIPTOR,0);return;}
    if(cmos2_session[39]) {
        data_len=16u;set32(data,cmos2_session[19]|GRAPH_MAX_OPS);
        set32(data+4u,cmos2_session[7]);set32(data+8u,cmos2_session[8]);set32(data+12u,cmos2_session[9]);
        graph_compile_only=1u;status=graph_run(cmos2_session[6]);graph_compile_only=0u;
        if(status!=OK){reply(status,0);return;}
    }
    cmos2_async_stage=0u;cmos2_stop_requested=0u;
    cmos2_continuous=1u;cmos2_completed=0u;cmos2_last_status=OK;
    cmos2_attempted=0;cmos2_rejected=0;cmos2_recovered=0;cmos2_fatal=0;
    cmos2_last_error=0;cmos2_last_bad_frame=0;cmos2_last_bad_run=0;cmos2_last_capture_errors=0;
    cmos2_retry_after=0;live_preview=(live_preview_state){0};live_preview_owner=0u;
    /* The pool generation is retained across ARM/STOP sessions. */
    for(uint32_t i=0;i<288u;i++)cmos2_last_reply[i]=0;
    reply(OK,0);
}
static void cmos2_idle_step(void) {
    if(!cmos2_continuous)return;
    if(cmos2_retry_after && ticks64()<cmos2_retry_after)return;
    if(!cmos2_async_stage) {
        if(cmos2_stop_requested)return;
        if(++cmos2_attempted==0u){cmos2_continuous=0u;cmos2_last_status=BAD_RANGE;return;}
        data_len=0u;for(uint32_t i=0;i<288u;i++)data[i]=0;
    }
    uint32_t result=cmos2_execute(cmos2_session);
    if(result==GRAPH_EXECUTOR_PENDING)return;
    cmos2_last_status=result;
    for(uint32_t i=0;i<288u;i++)cmos2_last_reply[i]=data[i];
    if(cmos2_last_status!=OK) {
        cmos2_last_error=cmos2_last_status;
        if(cmos2_last_status==CAMERA_BAD_FRAME) {
            cmos2_rejected++;cmos2_last_bad_frame=cmos2_session[5];
            cmos2_last_bad_run=cmos2_session[20];cmos2_last_capture_errors=get32(cmos2_last_reply+276u);
        }
        /* V2 prefetch failure can leave an IMG lease in flight: only the
         * single-frame mode has the existing safe completed-capture retry. */
        if(live_preview.fault || cmos2_session[1]!=1u || image_async_owned || image_timeout_latched ||
           !soc_cmos2_capture_can_resume(cmos2_last_status,get32(cmos2_last_reply+8u),
                  R32(CAMERA+8u),R32(0x50000004u),R32(NPU+0x0cu))) {
            cmos2_fatal++;cmos2_continuous=0u;return;
        }
        cmos2_recovered++;cmos2_retry_after=ticks64()+(uint64_t)HZ/30u;
    } else {
        cmos2_completed++;cmos2_retry_after=0;
        cmos2_session[4]^=0x00100000u;
        if(cmos2_session[1]==2u)cmos2_session[2]^=0x00200000u;
    }
    if(++cmos2_session[5]==0u||++cmos2_session[20]==0u)cmos2_continuous=0u;
}
