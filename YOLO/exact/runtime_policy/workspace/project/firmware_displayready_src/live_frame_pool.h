/* Continuous raw-frame pool. Normal inference completion never drains it.
 * IMG is shared by preprocessing and preview; waiting inference has priority.
 * Display submission and vblank acknowledgement are independent of inference.
 */
#ifndef SOC_LIVE_FRAME_POOL_H
#define SOC_LIVE_FRAME_POOL_H
#include "camera_frame_pool.h"
#include "camera_loss_policy.h"
#define LIVE_FB0 0x82200000u
#define LIVE_FB1 0x82300000u
#define LIVE_FLAG 1u
typedef struct {
    uint32_t enabled,stopping,inflight,inflight_base,last_good,new_ready;
    uint32_t fault,sequence,attempted,valid,dropped,published,acknowledged;
    uint32_t waiting_ack,overlay_xy1,overlay_xy2,overlay_score,overlay_class,overlay_count;
    uint32_t overlay_frame,overlay_run,last_poll,last_display_fb;
    uint64_t capture_started,first_started,last_ack;
    uint32_t resize_phase,resize_source,resize_fb,resize_seq,resize_started,resize_completed;
    uint64_t resize_begin,drain_ticks,resize_ticks;
    uint32_t metadata_pending,metadata_published,metadata_acknowledged,publication_kind;
    uint32_t publication_overlay_frame,overlay_acknowledged_frame;
    uint32_t infer_waiting,infer_image,infer_last_generation,preview_last_generation;
    uint32_t inference_frames,service_calls,service_reentry,capture_no_free;
    uint64_t inference_wait_ticks;
} live_preview_state;
static live_preview_state live_preview;
static camera_frame_pool live_pool;
static camera_pool_lease live_inference_lease,live_resize_lease;
static void live_preview_service(void);

static uint32_t live_preview_switch_observer(uint32_t image_only) {
    (void)image_only;return (R32(DISPLAY_MMIO+4u)&0x80000000u)?OK:DISPLAY_BAD_STATE;
}
static void live_preview_ack(void) {
    if(live_preview.waiting_ack&&!(R32(DISPLAY_MMIO+0x84u)&6u)) {
        live_preview.waiting_ack=0u;
        if(live_preview.publication_kind==1u) {
            live_preview.acknowledged++;live_preview.last_ack=ticks64();
        } else live_preview.metadata_acknowledged++;
        live_preview.overlay_acknowledged_frame=live_preview.publication_overlay_frame;
    }
}
static uint32_t live_preview_free_fb(void) {
    uint32_t status=R32(DISPLAY_MMIO+0x84u);if(status&6u)return 0u;
    uint32_t active=R32(DISPLAY_MMIO+0x30u);
    uint32_t shown=(status&1u)?R32(DISPLAY_MMIO+0x88u):0u;
    if(LIVE_FB0!=active&&LIVE_FB0!=shown)return LIVE_FB0;
    if(LIVE_FB1!=active&&LIVE_FB1!=shown)return LIVE_FB1;
    return 0u;
}
static void live_preview_overlay_registers(void) {
    R32(DISPLAY_MMIO+16u)=live_preview.overlay_xy1;
    R32(DISPLAY_MMIO+20u)=live_preview.overlay_xy2;
    R32(DISPLAY_MMIO+24u)=live_preview.overlay_score;
    R32(DISPLAY_MMIO+28u)=live_preview.overlay_class;
    R32(DISPLAY_MMIO+32u)=live_preview.overlay_count;
}
static uint32_t live_preview_next_sequence(void) {
    uint32_t seq=++live_preview.sequence;
    if(seq>=0x80000000u){live_preview.fault=BAD_RANGE;return 0u;}
    return seq|0x80000000u;
}
static void live_preview_publish(void) {
    uint32_t fb=live_preview_free_fb();
    if(!fb||!frame_pool_take(&live_pool,FRAME_POOL_PREVIEW,
            live_preview.preview_last_generation,&live_resize_lease))return;
    uint32_t seq=live_preview_next_sequence();if(!seq)return;
    R32(DISPLAY_MMIO+8u)=fb;R32(DISPLAY_MMIO+12u)=seq;
    R32(DISPLAY_MMIO+0x54u)=live_preview.overlay_run;fence_all();
    R32(DISPLAY_MMIO)=1u;fence_all();uint32_t state=R32(DISPLAY_MMIO+4u);
    if(!(state&2u)) {
        frame_pool_release(&live_pool,&live_resize_lease);
        if(((state>>16)&255u)!=10u)live_preview.fault=DISPLAY_BAD_STATE;
        return;
    }
    uint32_t source=live_pool.slot[live_resize_lease.index].base;
    cache_invalidate();uint32_t result=image_start_hardware(source,fb,1u,0);
    if(result!=OK||!image_last.hardware) {
        live_preview.fault=result==OK?IMAGE_HARDWARE_ERROR:result;
        if(!image_async_owned)frame_pool_release(&live_pool,&live_resize_lease);
        return;
    }
    live_preview.preview_last_generation=live_resize_lease.generation;
    live_preview.resize_source=source;live_preview.resize_fb=fb;live_preview.resize_seq=seq;
    live_preview.resize_begin=ticks64();live_preview.resize_phase=1u;live_preview.resize_started++;
}
static void live_preview_resize_step(void) {
    if(!live_preview.resize_phase)return;
    if(live_preview.resize_phase==1u) {
        uint32_t result=image_poll_hardware();
        if(result==IMAGE_IN_PROGRESS)return;
        if(result!=OK){live_preview.fault=result;return;}
        live_preview.resize_phase=2u;
    }
    uint32_t state=R32(DISPLAY_MMIO+4u);
    if(state&0x00ff0000u){live_preview.fault=DISPLAY_WRITE_ERROR;return;}
    if(R32(DISPLAY_MMIO+0x28u)!=SOC_CMOS2_DISPLAY_BYTES||R32(DISPLAY_MMIO+0x2cu)) {
        if(ticks64()-live_preview.resize_begin>(uint64_t)HZ*5u)live_preview.fault=DISPLAY_WRITE_TIMEOUT;
        return;
    }
    live_preview_overlay_registers();R32(DISPLAY_MMIO+0x54u)=live_preview.overlay_run;
    R32(DISPLAY_MMIO)=2u;fence_all();uint32_t before=R32(DISPLAY_MMIO+0x4cu);
    R32(DISPLAY_MMIO)=4u;fence_all();state=R32(DISPLAY_MMIO+4u);
    if(!(state&4u)||(state&0x00ff0000u)||R32(DISPLAY_MMIO+0x30u)!=live_preview.resize_fb||
       R32(DISPLAY_MMIO+0x34u)!=live_preview.resize_seq||R32(DISPLAY_MMIO+0x4cu)!=before+1u) {
        live_preview.fault=DISPLAY_BAD_STATE;return;
    }
    if(!frame_pool_release(&live_pool,&live_resize_lease)){live_preview.fault=DISPLAY_BAD_STATE;return;}
    live_preview.last_good=live_preview.resize_source;live_preview.last_display_fb=live_preview.resize_fb;
    live_preview.published++;live_preview.resize_completed++;
    live_preview.resize_ticks+=ticks64()-live_preview.resize_begin;live_preview.resize_phase=0u;
    live_preview.waiting_ack=1u;live_preview.publication_kind=1u;
    live_preview.publication_overlay_frame=live_preview.overlay_frame;live_preview.metadata_pending=0u;
    R32(VIDEO_MMIO+0x10u)=2u;fence_all();
}
static void live_preview_metadata_step(void) {
    if(!live_preview.metadata_pending||live_preview.resize_phase||live_preview.waiting_ack||
       live_preview.infer_image||image_async_owned)return;
    uint32_t state=R32(DISPLAY_MMIO+0x84u),active=R32(DISPLAY_MMIO+0x30u);
    if((state&6u)||!(state&1u)||R32(DISPLAY_MMIO+0x88u)!=active||
       (active!=LIVE_FB0&&active!=LIVE_FB1))return;
    uint32_t seq=live_preview_next_sequence();if(!seq)return;
    uint32_t before=R32(DISPLAY_MMIO+0x4cu);
    R32(DISPLAY_MMIO+8u)=active;R32(DISPLAY_MMIO+12u)=seq;
    R32(DISPLAY_MMIO+0x54u)=live_preview.overlay_run;live_preview_overlay_registers();fence_all();
    R32(DISPLAY_MMIO)=16u;fence_all();
    if((R32(DISPLAY_MMIO+4u)&0x00ff0000u)||R32(DISPLAY_MMIO+0x4cu)!=before+1u) {
        live_preview.fault=DISPLAY_BAD_STATE;return;
    }
    live_preview.metadata_pending=0u;live_preview.metadata_published++;
    live_preview.waiting_ack=1u;live_preview.publication_kind=2u;
    live_preview.publication_overlay_frame=live_preview.overlay_frame;
}
static void live_preview_service(void) {
    if(!live_preview.enabled||live_preview.fault||live_preview.service_reentry)return;
    uint32_t now=ticks();if((uint32_t)(now-live_preview.last_poll)<HZ/1000u)return;
    live_preview.last_poll=now;live_preview.service_reentry=1u;live_preview.service_calls++;
    live_preview_ack();live_preview_resize_step();if(live_preview.fault)goto done;
    uint32_t state=R32(CAMERA+8u);
    if(live_pool.capture_slot<FRAME_POOL_SLOTS) {
        if((state&4u)&&!(state&2u)) {
            fence_all();uint32_t r=frame_pool_capture_complete(&live_pool,state,R32(CAMERA+12u),
                    R32(CAMERA+16u),R32(CAMERA+20u),ticks64());
            if(!r){live_preview.fault=CAMERA_NOT_READY;goto done;}
            live_preview.inflight=0u;
            if(r==1u)live_preview.valid++;else live_preview.dropped++;
            /* Evaluate loss only after DONE and final DMA retirement. A
             * partial in-flight transfer is not evidence of pixel loss. */
            if(camera_loss_abort(R32(CAMERA+12u),R32(CAMERA+16u))) {
                live_preview.fault=CAMERA_BAD_FRAME;goto done;
            }
        }
        /* User policy: keep servicing UART and preview while waiting for
         * camera completion; elapsed time alone never aborts capture. */
    }
    live_preview_metadata_step();if(live_preview.fault)goto done;
    if(!live_preview.stopping&&!live_preview.infer_waiting&&!live_preview.infer_image&&
       !live_preview.resize_phase&&!image_async_owned&&!live_preview.waiting_ack)live_preview_publish();
    if(live_preview.fault||live_preview.stopping||live_pool.capture_slot<FRAME_POOL_SLOTS)goto done;
    state=R32(CAMERA+8u);if((state&0x51u)!=0x51u)goto done;
    uint32_t slot=frame_pool_capture_begin(&live_pool,ticks64());
    if(slot==FRAME_POOL_NONE) {
        if(live_pool.next_generation==UINT32_MAX)live_preview.fault=BAD_RANGE;
        else live_preview.capture_no_free++;
        goto done;
    }
    uint32_t base=live_pool.slot[slot].base;R32(CAMERA+4u)=base;fence_all();
    if(R32(CAMERA+4u)!=base){live_preview.fault=CAMERA_NOT_READY;goto done;}
    R32(CAMERA)=1u;fence_all();live_preview.inflight=1u;live_preview.inflight_base=base;
    live_preview.capture_started=live_pool.slot[slot].capture_begin;
    if(!live_preview.first_started)live_preview.first_started=live_preview.capture_started;
    live_preview.attempted++;
done:
    live_preview.service_reentry=0u;
}
static uint32_t live_preview_begin(void) {
    if(live_preview.enabled)return live_preview.fault;
    if(image_async_owned||live_inference_lease.valid||live_resize_lease.valid||
       !frame_pool_reset(&live_pool))return IMAGE_HARDWARE_ERROR;
    if(BOARD_IMAGE_SOFTWARE_ONLY||!(R32(CAMERA+0x60u)&IMAGE_CAPABILITY)||
       R32(IMAGE_MMIO+0x20u)!=IMAGE_ID)return IMAGE_HARDWARE_ERROR;
    uint32_t result=live_preview_switch_observer(1u);if(result!=OK)return result;
    live_preview.stopping=0u;live_preview.fault=0u;live_preview.enabled=1u;live_preview_owner=1u;
    live_preview.last_poll=ticks()-HZ/1000u;live_preview_service();return live_preview.fault;
}
/* One bounded step. The raw read lease survives across calls until IMG's
 * real final response; other monitor requests may run between these steps. */
static uint32_t live_inference_phase;
static uint64_t live_inference_started;
static uint32_t live_preview_inference_input_step(uint32_t destination,const int8_t *lut,
        uint32_t snapshot[4],uint32_t *raw,uint32_t *generation,uint64_t *begin,uint64_t *end) {
    if(!live_inference_phase) {
        live_inference_started=ticks64();live_preview.infer_waiting=1u;live_inference_phase=1u;
    }
    live_preview_service();if(live_preview.fault)return live_preview.fault;
    if(live_inference_phase==1u) {
        if(!live_preview.resize_phase&&!image_async_owned&&!live_inference_lease.valid)
            frame_pool_take(&live_pool,FRAME_POOL_INFERENCE,live_preview.infer_last_generation,&live_inference_lease);
        if(!live_inference_lease.valid||live_preview.resize_phase||image_async_owned) {
            /* No recognition/input-idle deadline: yield cooperatively. */
            return IMAGE_IN_PROGRESS;
        }
        camera_pool_slot *slot=&live_pool.slot[live_inference_lease.index];
        *raw=slot->base;*generation=slot->generation;*begin=slot->capture_begin;*end=slot->capture_end;
        snapshot[0]=slot->camera_status;snapshot[1]=slot->written;snapshot[2]=slot->sensor;snapshot[3]=slot->errors;
        live_preview.inference_wait_ticks+=ticks64()-live_inference_started;live_preview.infer_image=1u;
        cache_invalidate();uint32_t result=image_start_hardware(slot->base,destination,0u,lut);
        if(result!=OK){live_preview.fault=result;return result;}
        live_inference_phase=2u;return IMAGE_IN_PROGRESS;
    }
    uint32_t result=image_poll_hardware();
    if(result==IMAGE_IN_PROGRESS)return result;
    if(result!=OK){live_preview.fault=result;return result;}
    if(!frame_pool_release(&live_pool,&live_inference_lease)){live_preview.fault=BAD_RANGE;return BAD_RANGE;}
    live_preview.infer_last_generation=*generation;live_preview.inference_frames++;
    live_preview.infer_image=0u;live_preview.infer_waiting=0u;live_inference_phase=0u;return OK;
}
/* Retained only for legacy host unit harnesses, never used by the live FSM. */
static __attribute__((unused)) uint32_t live_preview_inference_input(uint32_t destination,const int8_t *lut,
        uint32_t snapshot[4],uint32_t *raw,uint32_t *generation,uint64_t *begin,uint64_t *end) {
    uint32_t r;
    do {r=live_preview_inference_input_step(destination,lut,snapshot,raw,generation,begin,end);}while(r==IMAGE_IN_PROGRESS);
    return r;
}
static uint32_t live_preview_metadata(uint32_t frame,uint32_t run,uint32_t *fb) {
    live_preview.overlay_frame=frame;live_preview.overlay_run=run;
    live_preview.metadata_pending=1u;*fb=live_preview.last_display_fb;return live_preview.fault;
}
/* Explicit STOP/error only. READY raw frames without readers need no drain. */
static uint32_t live_preview_end(void) {
    if(!live_preview.enabled)return live_preview.fault;
    live_preview.stopping=1u;uint64_t began=ticks64();
    while((live_pool.capture_slot<FRAME_POOL_SLOTS||live_preview.resize_phase||
           live_preview.waiting_ack||live_preview.metadata_pending||image_async_owned||
           live_inference_lease.valid)&&!live_preview.fault) {
        live_preview_service();
        if(ticks64()-began>(uint64_t)HZ*5u){live_preview.fault=CAMERA_TIMEOUT;break;}
    }
    live_preview.drain_ticks+=ticks64()-began;live_preview.enabled=0u;live_preview_owner=0u;
    return live_preview.fault;
}
/* Ending the service loop is not evidence that a timed-out DMA retired.
 * Keep monitor writes out of the model/raw/display memory until common reset
 * when an owner or a quarantined error survives STOP. Read-only probes remain
 * available to diagnose the fault. */
static uint32_t live_preview_memory_owned(void) {
    return live_preview_owner||live_preview.fault||image_async_owned||
           image_timeout_latched||live_inference_lease.valid||live_resize_lease.valid;
}
#endif
