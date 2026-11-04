// 架构导读：v2_hardware。
// 裸机控制固件组件，提供本文件定义的状态检查、数据结构和服务函数。
#ifndef SOC_V2_HARDWARE_H
#define SOC_V2_HARDWARE_H
#define S2_MMIO 0x60001200u
#define S2_ID 0x32563253u
static uint64_t v2_hw_tp0,v2_hw_tp1;
/* This driver starts the exact A Buffered V2 data path. No AST1 traffic,
 * CPU pixel processing, or diagnostic readback occurs inside it. */
static uint32_t v2_hardware_run(uint32_t source,uint32_t destination) {
    if((source&255u)||(destination&15u)||source!=0x81000000u||destination!=0x80100000u||
       !range(source,SOC_V2_SOURCE_BYTES)||!range(destination,SOC_V2_OUTPUT_BYTES))return BAD_RANGE;
    if(R32(S2_MMIO+0x34u)!=S2_ID)return BAD_COMMAND;
    // 硬件/可见性边界：uint32_t state=R32(S2_MMIO+0x0cu);。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    uint32_t state=R32(S2_MMIO+0x0cu);
    if(!(state&16u)) {
        // 硬件/可见性边界：R32(S2_MMIO+0x2cu)=0;。
        // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
        R32(S2_MMIO+0x2cu)=0;
        for(uint32_t i=0;i<256u;i++)R32(S2_MMIO+0x30u)=(uint8_t)soc_model_input_lut[i];
        // 硬件/可见性边界：fence_all();state=R32(S2_MMIO+0x0cu);。
        // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
        fence_all();state=R32(S2_MMIO+0x0cu);
        if(!(state&16u))return V2_HARDWARE_ERROR;
    }
    if(!(state&1u))return NPU_BUSY;
    // 硬件/可见性边界：R32(S2_MMIO+4u)=source;R32(S2_MMIO+8u)=destination;fence_all();。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    R32(S2_MMIO+4u)=source;R32(S2_MMIO+8u)=destination;fence_all();
    uint64_t started=ticks64();v2_hw_tp0=started;v2_hw_tp1=0;R32(S2_MMIO)=1u;
    while(!(R32(S2_MMIO+0x0cu)&4u))
        if(ticks64()-started>(uint64_t)HZ*5u)return V2_HARDWARE_TIMEOUT;
    fence_all();v2_hw_tp1=ticks64();state=R32(S2_MMIO+0x0cu);
    if(!(state&8u)||R32(S2_MMIO+0x1cu)!=SOC_V2_OUTPUT_BYTES||
       R32(S2_MMIO+0x10u)!=2592u*1944u||
       (R32(S2_MMIO+0x20u)&255u)||(R32(S2_MMIO+0x24u)&255u)||(R32(S2_MMIO+0x28u)&255u))return V2_HARDWARE_ERROR;
    return OK;
}
#endif
