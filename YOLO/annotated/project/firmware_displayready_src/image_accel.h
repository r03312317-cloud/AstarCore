/* IMG1 board image engine driver. Included by main.c after the common monitor
 * helpers. DDR addresses remain absolute CPU byte addresses: the RTL adapter
 * performs the DDR_BASE translation once, at its AXI boundary.
 */
// 架构导读：image_accel。
// 软件侧共享图像加速器接口，提交预处理/缩放并检查完成。
#ifndef SOC_IMAGE_ACCEL_H
#define SOC_IMAGE_ACCEL_H
#include "display_cmos2.h"

#ifndef BOARD_IMAGE_SOFTWARE_ONLY
#define BOARD_IMAGE_SOFTWARE_ONLY 0
#endif
#define IMAGE_MMIO 0x60001700u
#define IMAGE_ID 0x494d4731u
#define IMAGE_CAPABILITY (1u << 31)
#define IMAGE_UNAVAILABLE 0xffffffffu

typedef struct {
    uint32_t hardware,cycles,read_beats,write_beats,status;
} soc_image_result;
static soc_image_result image_last;
/* A timed-out engine may still own a DDR transaction. Never run software over
 * its output or submit another job until the common hardware reset.
 */
static uint32_t image_timeout_latched;

/* Asynchronous lease: IMG has exactly one outstanding command. The value
 * IMAGE_IN_PROGRESS is only a host/firmware polling result, not a MMIO bit.
 * On timeout or protocol error the lease is quarantined until common reset.
 */
#define IMAGE_IN_PROGRESS 0xfffffffeu
static uint32_t image_async_owned,image_async_mode,image_async_begin;

// 服务函数 image_start_hardware。
// 接口参数：uint32_t source,uint32_t destination,；返回值及副作用由下列函数体定义。
// 参数入口：source, destination, mode, table；类型、指针限定及返回约定沿用下列声明。
static uint32_t image_start_hardware(uint32_t source,uint32_t destination,
                                     uint32_t mode,const int8_t *table) {
    if(image_timeout_latched)return IMAGE_HARDWARE_TIMEOUT;
    if(image_async_owned)return NPU_BUSY;
    image_last=(soc_image_result){0,0,0,0,0};
    if(BOARD_IMAGE_SOFTWARE_ONLY)return IMAGE_UNAVAILABLE;
    if(!(R32(CAMERA+0x60u)&IMAGE_CAPABILITY))return IMAGE_UNAVAILABLE;
    if(R32(IMAGE_MMIO+0x20u)!=IMAGE_ID)return IMAGE_UNAVAILABLE;
    if((source|destination)&15u)return IMAGE_UNAVAILABLE;
    if(mode>1u || (mode==0u&&!table))return BAD_RANGE;
    image_last.hardware=1u;
    // 硬件/可见性边界：uint32_t state=R32(IMAGE_MMIO+0x10u);。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    uint32_t state=R32(IMAGE_MMIO+0x10u);
    image_last.status=state;
    if(state&1u)return NPU_BUSY;
    if(!(state&16u))return DDR_UNAVAILABLE;
    if(state&32u)return IMAGE_HARDWARE_ERROR;
    // 硬件/可见性边界：R32(IMAGE_MMIO+0x24u)=1u;。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    R32(IMAGE_MMIO+0x24u)=1u;
    // 硬件/可见性边界：R32(IMAGE_MMIO+4u)=source;。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    R32(IMAGE_MMIO+4u)=source;
    // 硬件/可见性边界：R32(IMAGE_MMIO+8u)=destination;。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    R32(IMAGE_MMIO+8u)=destination;
    // 硬件/可见性边界：R32(IMAGE_MMIO+12u)=mode;。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    R32(IMAGE_MMIO+12u)=mode;
    if(mode==0u) {
        // 硬件/可见性边界：R32(IMAGE_MMIO+0x28u)=0u;。
        // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
        R32(IMAGE_MMIO+0x28u)=0u;
        for(uint32_t i=0;i<256u;i++)R32(IMAGE_MMIO+0x2cu)=(uint8_t)table[i];
    }
    // 硬件/可见性边界：fence_all();。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    fence_all();
    image_async_mode=mode;image_async_begin=ticks();image_async_owned=1u;
    R32(IMAGE_MMIO)=1u;fence_all();
    return OK;
}
// 服务函数 image_poll_hardware。
// 接口参数：void；返回值及副作用由下列函数体定义。
// 参数入口：无位置参数；类型、指针限定及返回约定沿用下列声明。
static uint32_t image_poll_hardware(void) {
    if(image_timeout_latched)return IMAGE_HARDWARE_TIMEOUT;
    if(!image_async_owned)return BAD_COMMAND;
    uint32_t state=R32(IMAGE_MMIO+0x10u);
    image_last.status=state;
    if(state&44u) {
        image_timeout_latched=1u;
        return IMAGE_HARDWARE_ERROR;
    }
    if(!(state&2u)) {
        if((uint32_t)(ticks()-image_async_begin)<=HZ*5u)return IMAGE_IN_PROGRESS;
        image_timeout_latched=1u;
        return IMAGE_HARDWARE_TIMEOUT;
    }
    fence_all();cache_invalidate();
    image_last.cycles=R32(IMAGE_MMIO+0x14u);
    image_last.read_beats=R32(IMAGE_MMIO+0x18u);
    image_last.write_beats=R32(IMAGE_MMIO+0x1cu);
    if((state&1u)||image_last.read_beats!=(image_async_mode==0u?57600u:54400u)||
       image_last.write_beats!=(image_async_mode==0u?19200u:28900u)) {
        image_timeout_latched=1u;
        return IMAGE_HARDWARE_ERROR;
    }
    image_async_owned=0u;
    return OK;
}
// 服务函数 image_wait_hardware。
// 接口参数：void；返回值及副作用由下列函数体定义。
// 参数入口：无位置参数；类型、指针限定及返回约定沿用下列声明。
static uint32_t image_wait_hardware(void) {
    uint32_t result;
    do {result=image_poll_hardware();}while(result==IMAGE_IN_PROGRESS);
    return result;
}
// 服务函数 image_try_hardware。
// 接口参数：uint32_t source,uint32_t destination,；返回值及副作用由下列函数体定义。
// 参数入口：source, destination, mode, table；类型、指针限定及返回约定沿用下列声明。
static uint32_t image_try_hardware(uint32_t source,uint32_t destination,
                                  uint32_t mode,const int8_t *table) {
    uint32_t result=image_start_hardware(source,destination,mode,table);
    return result==OK?image_wait_hardware():result;
}

// 服务函数 image_preprocess320。
// 接口参数：uint32_t source,uint32_t destination,；返回值及副作用由下列函数体定义。
// 参数入口：source, destination, table；类型、指针限定及返回约定沿用下列声明。
static uint32_t image_preprocess320(uint32_t source,uint32_t destination,
                                   const int8_t table[256]) {
    if((source&1u)||!range(source,SOC_PP320_SOURCE_BYTES)||
       !range(destination,SOC_PP320_TARGET_BYTES)||
       overlap(source,SOC_PP320_SOURCE_BYTES,destination,SOC_PP320_TARGET_BYTES))
        return BAD_RANGE;
    uint32_t result=image_try_hardware(source,destination,0u,table);
    if(result!=IMAGE_UNAVAILABLE)return result;
    soc_preprocess_rgb565_320_i8((const volatile uint8_t *)(uintptr_t)source,
        (volatile int8_t *)(uintptr_t)destination,table);
    fence_all();return OK;
}

// 服务函数 image_display_cmos2。
// 接口参数：uint32_t source,uint32_t destination；返回值及副作用由下列函数体定义。
// 参数入口：source, destination；类型、指针限定及返回约定沿用下列声明。
static uint32_t image_display_cmos2(uint32_t source,uint32_t destination) {
    if(((source|destination)&1u)||!range(source,SOC_PP320_SOURCE_BYTES)||
       !range(destination,SOC_CMOS2_DISPLAY_BYTES)||
       overlap(source,SOC_PP320_SOURCE_BYTES,destination,SOC_CMOS2_DISPLAY_BYTES))
        return BAD_RANGE;
    uint32_t result=image_try_hardware(source,destination,1u,0);
    if(result!=IMAGE_UNAVAILABLE)return result;
    soc_display_resize_cmos2((const volatile uint8_t *)(uintptr_t)source,
        (volatile uint16_t *)(uintptr_t)destination);
    fence_all();return OK;
}
#endif
