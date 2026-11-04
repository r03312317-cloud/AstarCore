/* Private integration candidate. Original NPU register window/UART upload
 * protocol stay intact. This path is required for all60 model Conv calls;
 * accepted hardware errors never fall back to CPU-computed tensors. */
// 架构导读：conv_service_hardware。
// 配置卷积服务参数与硬件事务，保留软件可检查的状态边界。
#ifndef SOC_CONV_SERVICE_HARDWARE_H
#define SOC_CONV_SERVICE_HARDWARE_H
#define CONV_SERVICE_MMIO 0x70000100u
#define CONV_SERVICE_ID 0x32584547u
#define CONV_SERVICE_LEGACY_ID 0x31584547u
#include "conv_service_batch_contract.h"
static uint32_t conv_service_timeout_latched;
/* Boot-loaded assets own epoch 1. Every accepted nonempty UART DDR upload
 * advances the content epoch before any write; a wrap requires common reset.
 * frame_epoch is a monotonic invocation identity, not an HDMI frame_id.
 * The workflow retains the actual frame/run IDs below and in its public
 * performance record. Standalone Graph/Conv use identity 0 = unavailable.
 * Hardware additionally changes task_generation for EVERY Conv, including
 * errors/reloads, and the Window row generation is part of the A key. Thus
 * reuse is confined to one immutable Conv lease; address equality is never
 * sufficient. Coordinated reset clears both software epochs and bank valid.
 */
static uint32_t conv_service_model_epoch=1u,conv_service_frame_epoch;
static uint32_t conv_service_frame_id,conv_service_run_id;
static uint32_t conv_service_workflow_context;
// 服务函数 conv_service_frame_begin。
// 接口参数：uint32_t frame,uint32_t run；返回值及副作用由下列函数体定义。
// 参数入口：frame, run；类型、指针限定及返回约定沿用下列声明。
static uint32_t conv_service_frame_begin(uint32_t frame,uint32_t run) {
    if(conv_service_frame_epoch==UINT32_MAX)return NPU_ERROR;
    conv_service_frame_epoch++;
    conv_service_frame_id=frame;conv_service_run_id=run;
    return OK;
}
// 服务函数 conv_service_page_limit。
// 接口参数：uint32_t k；返回值及副作用由下列函数体定义。
// 参数入口：k；类型、指针限定及返回约定沿用下列声明。
static uint32_t conv_service_page_limit(uint32_t k) {
    return k<=512u?256u:k<=576u?224u:k<=682u?192u:
           k<=818u?160u:k<=1024u?128u:112u;
}

// 服务函数 conv_service_run。
// 接口参数：uint32_t input,uint32_t weights,uint32_t output,；返回值及副作用由下列函数体定义。
// 参数入口：weights, scratch, scratch_stride, scratch_bytes, shape, layout；类型、指针限定及返回约定沿用下列声明。
static uint32_t conv_service_run(uint32_t input,uint32_t weights,uint32_t output,
    uint32_t scratch,uint32_t scratch_stride,uint32_t scratch_bytes,
    const soc_conv2d_shape *shape,const soc_conv2d_layout *layout) {
    if(conv_service_timeout_latched)return NPU_BUSY;
    if(!conv_service_frame_epoch && conv_service_frame_begin(0u,0u)!=OK)
        return NPU_ERROR;
    if(shape->tile_m!=64u||layout->rows>65535u||layout->k>1152u||
       shape->output_c>65535u||layout->output_w>65535u||
       shape->input_h>65535u||shape->input_w>65535u||shape->input_c>65535u||
       layout->output_h>65535u||shape->kernel_h>255u||shape->kernel_w>255u||
       shape->stride_h>255u||shape->stride_w>255u||
       shape->dilation_h>255u||shape->dilation_w>255u||
       shape->pad_top>255u||shape->pad_left>255u||
       shape->pad_bottom>255u||shape->pad_right>255u)return CONV_BAD_SHAPE;
    // 硬件/可见性边界：uint32_t service_id=R32(CONV_SERVICE_MMIO+8u);。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    uint32_t service_id=R32(CONV_SERVICE_MMIO+8u);
    if(service_id!=CONV_SERVICE_ID&&service_id!=CONV_SERVICE_LEGACY_ID)return NPU_ERROR;
    // 硬件/可见性边界：uint32_t batch_cap=service_id==CONV_SERVICE_ID?R32(CONV_SERVICE_MMIO+0xbcu):16u;。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    uint32_t batch_cap=service_id==CONV_SERVICE_ID?R32(CONV_SERVICE_MMIO+0xbcu):16u;
    uint32_t window_batch=conv_service_effective_window_rows(batch_cap,layout->k,scratch_stride,scratch_bytes!=0u);
    if(!window_batch)return NPU_ERROR;
    // 硬件/可见性边界：uint32_t state=R32(CONV_SERVICE_MMIO+4u);。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    uint32_t state=R32(CONV_SERVICE_MMIO+4u);
    if(state&0x8001u)return NPU_BUSY;
    if((R32(NPU+0x0cu)&0x47u)!=5u)return NPU_BUSY;
    /* Drain a prior standalone notification before acquiring private graph
     * ownership. The SoC masks perTile NPU IRQs only during this lease. */
    R32(NPU+0x14u)=3u;R32(NPU+0x78u)=0xfffu;fence_all();
    uint32_t words[31]={0};
    words[0]=conv_service_model_epoch;words[1]=conv_service_frame_epoch;
    words[2]=layout->rows;words[3]=(layout->k<<16)|shape->output_c;
    words[4]=layout->output_w;words[5]=scratch_bytes?1u:0u;
    words[6]=input;words[7]=weights;words[8]=output;
    words[9]=layout->k;words[10]=shape->output_c*4u;
    words[11]=layout->k*64u;words[12]=shape->output_c*256u;
    words[13]=layout->k*8u;words[14]=scratch;words[15]=scratch_stride;
    words[20]=input;words[21]=scratch;words[22]=0u;
    words[23]=(shape->input_w<<16)|shape->input_h;
    words[24]=(layout->output_h<<16)|shape->input_c;
    words[25]=layout->output_w;words[26]=64u<<16;
    words[27]=(shape->stride_w<<24)|(shape->stride_h<<16)|
        (shape->kernel_w<<8)|shape->kernel_h;
    words[28]=(shape->pad_left<<24)|(shape->pad_top<<16)|
        (shape->dilation_w<<8)|shape->dilation_h;
    words[29]=(shape->pad_right<<8)|shape->pad_bottom;words[30]=0u;
    uint32_t begin=ticks();
    for(uint32_t i=0;i<31u;i++)R32(CONV_SERVICE_MMIO+0x40u+4u*i)=words[i];
    // 硬件/可见性边界：fence_all();R32(CONV_SERVICE_MMIO)=1u;。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    fence_all();R32(CONV_SERVICE_MMIO)=1u;
    uint32_t poll_begin=ticks();
    while(!((state=R32(CONV_SERVICE_MMIO+4u))&2u)) {
        live_preview_service();
        if(state&0x8000u) {
            /* Retain the software lease. The UART dispatcher blocks all
             * buffer/model operations until coordinated common reset. */
            conv_service_timeout_latched=1u;return NPU_ERROR;
        }
        if((uint32_t)(ticks()-begin)>HZ*5u) {
            conv_service_timeout_latched=1u;return NPU_TIMEOUT;
        }
    }
    // 硬件/可见性边界：uint32_t polled=ticks()-poll_begin;fence_all();。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    uint32_t polled=ticks()-poll_begin;fence_all();
    uint32_t elapsed=ticks()-begin;
    uint32_t source=(state>>11)&7u,error=(state>>3)&255u;
    // 硬件/可见性边界：uint64_t macs=(uint64_t)R32(CONV_SERVICE_MMIO+0x0cu)|。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    uint64_t macs=(uint64_t)R32(CONV_SERVICE_MMIO+0x0cu)|
                  // 硬件/可见性边界：((uint64_t)R32(CONV_SERVICE_MMIO+0x10u)<<32);。
                  // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
                  ((uint64_t)R32(CONV_SERVICE_MMIO+0x10u)<<32);
    // 硬件/可见性边界：uint32_t commands=R32(CONV_SERVICE_MMIO+0x14u);。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    uint32_t commands=R32(CONV_SERVICE_MMIO+0x14u);
    // 硬件/可见性边界：uint32_t jobs=R32(CONV_SERVICE_MMIO+0x18u);。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    uint32_t jobs=R32(CONV_SERVICE_MMIO+0x18u);
    // 硬件/可见性边界：uint32_t cycles=R32(CONV_SERVICE_MMIO+0x1cu);。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    uint32_t cycles=R32(CONV_SERVICE_MMIO+0x1cu);
    // 硬件/可见性边界：uint32_t rd=R32(CONV_SERVICE_MMIO+0x20u),wr=R32(CONV_SERVICE_MMIO+0x24u);。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    uint32_t rd=R32(CONV_SERVICE_MMIO+0x20u),wr=R32(CONV_SERVICE_MMIO+0x24u);
    // 硬件/可见性边界：uint32_t active=R32(CONV_SERVICE_MMIO+0x28u),stalled=R32(CONV_SERVICE_MMIO+0x2cu);。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    uint32_t active=R32(CONV_SERVICE_MMIO+0x28u),stalled=R32(CONV_SERVICE_MMIO+0x2cu);
    uint32_t hits=R32(CONV_SERVICE_MMIO+0x30u),misses=R32(CONV_SERVICE_MMIO+0x34u);
    uint32_t window_ticks=R32(CONV_SERVICE_MMIO+0x38u);
    uint32_t npu_ticks=R32(CONV_SERVICE_MMIO+0x3cu);
    /* All returned command counters are snapshots after both owners drain.
     * CPU poll, Windowcommand and NPUcommand windows overlap by design. */
    if(graph_profile_active) {
        profile_counters[P_NPU_COMPLETION_CYCLES]+=cycles;
        profile_counters[P_NPU_COMMAND_TICKS]+=npu_ticks;
        profile_counters[P_NPU_POLL_TICKS]+=polled;
        profile_counters[P_CPU_POLL_TICKS]+=polled;
        profile_counters[P_WINDOW_GATHER_TICKS]+=window_ticks;
        profile_counters[P_WINDOW_READ_BYTES]+=rd;
        profile_counters[P_WINDOW_WRITE_BYTES]+=wr;
        profile_counters[P_WINDOW_ACTIVE_UI_CYCLES]+=active;
        profile_counters[P_WINDOW_STALL_UI_CYCLES]+=stalled;
    }
    window_wait_total+=window_ticks;window_read_total+=rd;window_write_total+=wr;
    window_hit_total+=hits;window_miss_total+=misses;window_active_total+=active;window_stall_total+=stalled;
    if(source||error) {
        uint32_t result=source==2u?WINDOW_GATHER_ERROR:source==4u?CONV_BAD_SHAPE:NPU_ERROR;
        if(source==2u){window_failures++;window_last_error=result;}
        set32(data,SOC_CONV2D_ID);set32(data+4,source);set32(data+8,result);set32(data+12,error);
        return result;
    }
    uint32_t tiles=(layout->rows+15u)/16u;
    uint32_t page_limit=conv_service_page_limit(layout->k);
    uint32_t pages=(shape->output_c+page_limit-1u)/page_limit;
    if(macs!=(uint64_t)layout->rows*shape->output_c*layout->k||
       commands!=tiles*pages||
       jobs!=(scratch_bytes?((layout->rows+window_batch-1u)/window_batch)*pages:0u)||
       wr!=(scratch_bytes?layout->rows*layout->k*pages:0u)||(state&0xc001u))
        return NPU_ERROR;
    window_jobs+=jobs;
    if(scratch_bytes)window_hw_layers++;else window_direct_layers++;
    uint32_t crc=graph_fast_mode?0u:crc_memory(output,layout->output_bytes);
    set32(data,SOC_CONV2D_ID);set32(data+4,input);set32(data+8,output);
    set32(data+12,layout->rows);set32(data+16,layout->k);set32(data+20,shape->output_c);
    set32(data+24,(layout->rows+63u)/64u);set32(data+28,0u);set32(data+32,npu_ticks);
    set32(data+36,cycles);set32(data+40,elapsed);set32(data+44,crc);
#ifdef BOARD_SIM_GRAPH_METRICS
    sim_npu_cycles+=cycles;sim_npu_commands+=commands;
#endif
    return OK;
}
#endif
