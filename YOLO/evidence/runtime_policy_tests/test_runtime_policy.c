#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#define HZ 70000000u
#define CAMERA 0x1000u
#define DISPLAY_MMIO 0x2000u
#define IMAGE_MMIO 0x3000u
#define VIDEO_MMIO 0x4000u
#define SOC_CMOS2_DISPLAY_BYTES 462400u
#define BOARD_IMAGE_SOFTWARE_ONLY 0
#define IMAGE_CAPABILITY 1u
#define IMAGE_ID 0x1234u
enum { OK, DISPLAY_BAD_STATE, DISPLAY_WRITE_TIMEOUT, DISPLAY_WRITE_ERROR,
       IMAGE_HARDWARE_ERROR, CAMERA_NOT_READY, CAMERA_TIMEOUT, CAMERA_BAD_FRAME,
       BAD_RANGE, IMAGE_IN_PROGRESS };
static uint32_t mmio[0x5000u / 4u];
#define R32(a) mmio[(a)/4u]
static uint64_t now;
static uint32_t image_async_owned, image_timeout_latched, live_preview_owner;
static struct {uint32_t hardware;} image_last;
static uint32_t ticks(void) {return (uint32_t)now;}
static uint64_t ticks64(void) {return now;}
static void fence_all(void) {}
static void cache_invalidate(void) {}
static uint32_t image_start_hardware(uint32_t a,uint32_t b,uint32_t c,const int8_t *d) {
    (void)a;(void)b;(void)c;(void)d;image_last.hardware=1;return OK;
}
static uint32_t image_poll_hardware(void) {return IMAGE_IN_PROGRESS;}
#include "runtime_policy/workspace/project/firmware_displayready_src/live_frame_pool.h"

static void reset(void) {
    memset(mmio,0,sizeof mmio);memset(&live_preview,0,sizeof live_preview);
    memset(&live_pool,0,sizeof live_pool);
    live_inference_lease=(camera_pool_lease){0};live_resize_lease=(camera_pool_lease){0};
    live_inference_phase=0;image_async_owned=0;image_timeout_latched=0;
    assert(frame_pool_reset(&live_pool));
    now=(uint64_t)HZ*600u;live_preview.enabled=1;live_preview.infer_waiting=1;
}

int main(void) {
    assert(camera_loss_abort(829440,921600)); /* exactly 10% */
    assert(!camera_loss_abort(829441,921600)); /* one pixel below 10% */
    assert(camera_loss_abort(921600,829440));
    assert(!camera_loss_abort(921600,921600));
    assert(camera_loss_abort(0,0));
    assert(camera_lost_pixels(900000,900000)==21600); /* no double-count */
    reset();assert(frame_pool_capture_begin(&live_pool,1)==0);
    live_preview.capture_started=1;R32(CAMERA+8)=2;
    live_preview_service();assert(!live_preview.fault&&live_pool.capture_slot==0);
    uint32_t snap[4],raw=0,generation=0;uint64_t begin=0,end=0;
    assert(live_preview_inference_input_step(0,0,snap,&raw,&generation,&begin,&end)==IMAGE_IN_PROGRESS);
    now+=(uint64_t)HZ*600u;
    assert(live_preview_inference_input_step(0,0,snap,&raw,&generation,&begin,&end)==IMAGE_IN_PROGRESS);
    assert(!live_preview.fault&&live_pool.capture_slot==0); /* UART caller can regain control */
    reset();assert(frame_pool_capture_begin(&live_pool,1)==0);
    R32(CAMERA+8)=4;R32(CAMERA+12)=829441;R32(CAMERA+16)=921600;
    live_preview_service();
    assert(!live_preview.fault&&live_preview.dropped==1&&live_pool.rejected==1);
    assert(live_pool.slot[0].state==FRAME_POOL_FREE); /* bad frame never enters inference */
    reset();assert(frame_pool_capture_begin(&live_pool,1)==0);
    R32(CAMERA+8)=4;R32(CAMERA+12)=829440;R32(CAMERA+16)=921600;
    live_preview_service();assert(live_preview.fault==CAMERA_BAD_FRAME);
    reset();assert(frame_pool_capture_begin(&live_pool,1)==0);
    R32(CAMERA+8)=12;R32(CAMERA+12)=921600;R32(CAMERA+16)=921600;
    live_preview_service();assert(!live_preview.fault&&live_preview.valid==1);
    assert(live_pool.slot[0].state==FRAME_POOL_READY);
    puts("PASS: exact 10% boundary, writer/sensor loss, no double counting, 600-second capture/input wait, discard/recover and full-frame acceptance");
    return 0;
}
