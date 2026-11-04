/* One raw capture pool shared by inference preprocessing and preview resize.
 * A READY slot can have both readers. A producer can only reuse an unleased
 * slot. Capture DONE must include retirement of the hardware's final B.
 * Generations survive session resets to reject stale release tokens.
 */
#ifndef SOC_CAMERA_FRAME_POOL_H
#define SOC_CAMERA_FRAME_POOL_H
#include <stdint.h>
#define FRAME_POOL_SLOTS 3u
#define FRAME_POOL_NONE FRAME_POOL_SLOTS
#define FRAME_POOL_INFERENCE 1u
#define FRAME_POOL_PREVIEW 2u
#define FRAME_POOL_FREE 0u
#define FRAME_POOL_CAPTURING 1u
#define FRAME_POOL_READY 2u
typedef struct {
    uint32_t base,state,readers,generation,camera_status,written,sensor,errors;
    uint64_t capture_begin,capture_end;
} camera_pool_slot;
typedef struct {uint32_t index,generation,consumer,valid;} camera_pool_lease;
typedef struct {
    camera_pool_slot slot[FRAME_POOL_SLOTS];
    uint32_t capture_slot,next_generation,completed,rejected,reclaimed,protocol_errors;
} camera_frame_pool;
static inline uint32_t frame_pool_quiescent(const camera_frame_pool *p) {
    for(uint32_t i=0;i<FRAME_POOL_SLOTS;i++)
        if(p->slot[i].state==FRAME_POOL_CAPTURING||p->slot[i].readers)return 0u;
    return 1u;
}
static inline uint32_t frame_pool_reset(camera_frame_pool *p) {
    if(!frame_pool_quiescent(p))return 0u;
    uint32_t generation=p->next_generation;
    *p=(camera_frame_pool){0};p->next_generation=generation;p->capture_slot=FRAME_POOL_NONE;
    for(uint32_t i=0;i<FRAME_POOL_SLOTS;i++)p->slot[i].base=0x81000000u+i*0x00200000u;
    return 1u;
}
static inline uint32_t frame_pool_capture_begin(camera_frame_pool *p,uint64_t now) {
    if(p->capture_slot<FRAME_POOL_SLOTS||p->next_generation==UINT32_MAX)return FRAME_POOL_NONE;
    uint32_t chosen=FRAME_POOL_NONE;
    for(uint32_t i=0;i<FRAME_POOL_SLOTS;i++) {
        camera_pool_slot *s=&p->slot[i];
        if(s->readers||s->state==FRAME_POOL_CAPTURING)continue;
        if(chosen==FRAME_POOL_NONE||s->state==FRAME_POOL_FREE||
           (p->slot[chosen].state!=FRAME_POOL_FREE&&s->generation<p->slot[chosen].generation))chosen=i;
        if(s->state==FRAME_POOL_FREE)break;
    }
    if(chosen==FRAME_POOL_NONE)return chosen;
    camera_pool_slot *s=&p->slot[chosen];
    if(s->state==FRAME_POOL_READY)p->reclaimed++;
    s->state=FRAME_POOL_CAPTURING;s->generation=++p->next_generation;
    s->capture_begin=now;s->capture_end=0u;s->camera_status=0u;
    s->written=0u;s->sensor=0u;s->errors=0u;p->capture_slot=chosen;
    return chosen;
}
/* 0: not retired, 1: valid READY frame, 2: fully retired bad frame discarded. */
static inline uint32_t frame_pool_capture_complete(camera_frame_pool *p,uint32_t status,
        uint32_t written,uint32_t sensor,uint32_t errors,uint64_t now) {
    if(!(status&4u)||(status&2u))return 0u;
    if(p->capture_slot>=FRAME_POOL_SLOTS){p->protocol_errors++;return 0u;}
    camera_pool_slot *s=&p->slot[p->capture_slot];
    if(s->state!=FRAME_POOL_CAPTURING||s->readers){p->protocol_errors++;return 0u;}
    s->camera_status=status;s->written=written;s->sensor=sensor;s->errors=errors;s->capture_end=now;
    p->capture_slot=FRAME_POOL_NONE;
    if(!(status&8u)||errors||written!=921600u||sensor!=921600u) {
        s->state=FRAME_POOL_FREE;p->rejected++;return 2u;
    }
    s->state=FRAME_POOL_READY;p->completed++;return 1u;
}
static inline uint32_t frame_pool_take(camera_frame_pool *p,uint32_t consumer,
        uint32_t newer_than,camera_pool_lease *lease) {
    if(lease->valid||(consumer!=FRAME_POOL_INFERENCE&&consumer!=FRAME_POOL_PREVIEW))return 0u;
    uint32_t chosen=FRAME_POOL_NONE;
    for(uint32_t i=0;i<FRAME_POOL_SLOTS;i++) {
        camera_pool_slot *s=&p->slot[i];
        if(s->state!=FRAME_POOL_READY||s->generation<=newer_than||(s->readers&consumer))continue;
        if(chosen==FRAME_POOL_NONE||s->generation>p->slot[chosen].generation)chosen=i;
    }
    if(chosen==FRAME_POOL_NONE)return 0u;
    camera_pool_slot *s=&p->slot[chosen];s->readers|=consumer;
    *lease=(camera_pool_lease){chosen,s->generation,consumer,1u};return 1u;
}
static inline uint32_t frame_pool_release(camera_frame_pool *p,camera_pool_lease *lease) {
    if(!lease->valid||lease->index>=FRAME_POOL_SLOTS||
       (lease->consumer!=FRAME_POOL_INFERENCE&&lease->consumer!=FRAME_POOL_PREVIEW))return 0u;
    camera_pool_slot *s=&p->slot[lease->index];
    if(s->state!=FRAME_POOL_READY||s->generation!=lease->generation||!(s->readers&lease->consumer))return 0u;
    s->readers&=~lease->consumer;lease->valid=0u;return 1u;
}
#endif
