/* Stop-and-wait binary UART monitor. All transferred data remains volatile.
 * Packet: "AST1", sequence, opcode, argument, payload length, payload, CRC32.
 * Integers are little endian; CRC covers the 16-byte header after magic + data.
 * Replies use opcode|0x80000000 and argument=status. Never pipeline requests:
 * this candidate buffers 128 RX bytes for control packets during inference.
 * Model uploads remain stop-and-wait and are forbidden in continuous mode.
 */
// 架构导读：main。
// AST1 监控固件入口，处理带序号/CRC 的命令、DDR 访问与协作式识别服务。
#include <stdint.h>
#include <stddef.h>
void *memcpy(void *destination,const void *source,size_t bytes);
void *memset(void *destination,int value,size_t bytes);
#include "preprocess_rgb565.h"
#include "preprocess320_i8.h"
#include "model_input_lut.h"
#include "conv2d_int8.h"
#include "requant_i32_i8.h"
#include "tensor_ops_int8.h"
_Static_assert(sizeof(soc_conv2d_shape)==15u*sizeof(uint32_t),"Conv descriptor packing");
_Static_assert(sizeof(soc_tensor_shape)==14u*sizeof(uint32_t),"Tensor descriptor packing");
#include "yolov5_postprocess.h"
#include "s3_model_fuse_whitelist.h"
#include "preprocess5mp_v2.h"
#include "display_resize.h"
#define R32(a) (*(volatile uint32_t *)(uintptr_t)(a))
#include "cycle_timer64.h"
#define R8(a) (*(volatile uint8_t *)(uintptr_t)(a))
#define R16(a) (*(volatile uint16_t *)(uintptr_t)(a))
#ifndef BOARD_CPU_HZ
#define BOARD_CPU_HZ 27000000u
#endif
#ifndef BOARD_CPU_HZ_TEXT
#define BOARD_CPU_HZ_TEXT "27000000"
#endif
#ifndef BOARD_NPU_HZ
#define BOARD_NPU_HZ 100000000u
#endif
#define HZ BOARD_CPU_HZ
#define NPU 0x70000000u
#define MAX_DATA 1024u
#define DDR_BASE 0x80000000u
#define DDR_END 0x88000000u   /* cache-reloc-01: admit the 64 MiB cached window */
#define CAMERA 0x60001000u
#define S3_MMIO 0x60001100u
#define S3_ID 0x33515253u
#define WINDOW_MMIO 0x60001300u
#define WINDOW_ID 0x314e4957u
#define CAMERA_FRAME_BYTES SOC_FRAME_BYTES
#define SOC_PREPROCESS320_ID 0x4c423332u /* "LB32" */
static uint32_t live_preview_owner;
// 服务函数 live_preview_service。
// 以协作式小步推进采集、缩放和元数据确认；正常推理完成时继续保持独立预览服务。
// 参数入口：无位置参数；类型、指针限定及返回约定沿用下列声明。
static void live_preview_service(void);
// 服务函数 camera_writing。
// 接口参数：void；返回值及副作用由下列函数体定义。
// 参数入口：无位置参数；类型、指针限定及返回约定沿用下列声明。
static int camera_writing(void) {
#ifdef BOARD_SIM_NO_CAMERA
    return 0;
#else
    // 控制边界：!(R32(CAMERA+0x08u)&2u)；仅在该条件成立时进入本分支。
    if(!(R32(CAMERA+0x08u)&2u))return 0;
    // 控制边界：live_preview_owner；仅在该条件成立时进入本分支。
    if(live_preview_owner) {
        // 硬件/可见性边界：uint32_t base=R32(CAMERA+4u);。
        // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
        uint32_t base=R32(CAMERA+4u);
        // 控制边界：base==0x81200000u||base==0x81400000u；仅在该条件成立时进入本分支。
        if(base==0x81200000u||base==0x81400000u)return 0;
    }
    return 1;
#endif
}
#define GRAPH_ID 0x31505247u /* "GRP1" */
#define GRAPH_MAX_OPS 204u
#define GRAPH_WORDS_PER_OP 24u
#define GRAPH_TRACE_WORDS 6u
/* Mode bits share the existing graph count word; legacy counts stay diagnostic. */
#define GRAPH_FAST_FLAG 0x80000000u
#define GRAPH_FAST_FINAL_CRC_FLAG 0x40000000u
#define GRAPH_S3_FLAG 0x20000000u
#define GRAPH_S3_FUSE_LUT_FLAG 0x10000000u
#define GRAPH_PROFILE_FLAG 0x08000000u
#define GRAPH_WINDOW_FLAG 0x04000000u
#define GRAPH_CONCAT_FLAG 0x02000000u
#define GRAPH_COUNT_MASK 0xffu
#define PROFILE_ID 0x31465046u /* "FPF1", version 1 */
/* Counter order is part of AST1 opcode 18's versioned wire contract.
 * Cycles stay in their original clock domain; overlapping phases cannot be
 * added to infer elapsed time. Unsupported counters have zero validity bits. */
enum { P_GRAPH_TICKS, P_CONV_TICKS, P_IM2COL_TICKS,
       P_NPU_COMPLETION_CYCLES, P_NPU_COMMAND_TICKS, P_NPU_POLL_TICKS,
       P_HW_REQUANT_TICKS, P_SW_REQUANT_TICKS,
       P_CONCAT_TICKS, P_UPSAMPLE_TICKS, P_ADD_TICKS, P_POOL_TICKS,
       P_SW_LUT_TICKS, P_S3_POLL_TICKS, P_S3_ACTIVE_UI_CYCLES,
       P_S3_STALL_UI_CYCLES, P_S3_READ_BYTES, P_S3_WRITE_BYTES,
       P_GRAPH_VALIDATION_TICKS, P_CPU_POLL_TICKS, P_DECODE_TICKS,
       P_NPU_ACTIVE_CYCLES, P_NPU_DMA_WAIT_CYCLES,
       P_V2_PREPROCESS_TICKS, P_DISPLAY_RESIZE_TICKS,
       P_DDR_FRAME_TO_DISPLAY_READY_TICKS,
       P_WINDOW_GATHER_TICKS, P_WINDOW_READ_BYTES, P_WINDOW_WRITE_BYTES,
       P_WINDOW_ACTIVE_UI_CYCLES, P_WINDOW_STALL_UI_CYCLES,
       P_COUNTER_COUNT };
enum { OK, BAD_CRC, BAD_LENGTH, BAD_RANGE, RX_TIMEOUT, BAD_COMMAND,
       DDR_UNAVAILABLE, NPU_BUSY, NPU_TIMEOUT, NPU_ERROR, UART_ERROR,
       CAMERA_NOT_READY, CAMERA_TIMEOUT, CAMERA_BAD_FRAME, CONV_BAD_SHAPE,
       REQUANT_BAD_PARAMS, REQUANT_BIAS_OVERFLOW, TENSOR_BAD_SHAPE,
       GRAPH_BAD_DESCRIPTOR, DETECT_BAD_PARAMS, DETECT_CANDIDATE_OVERFLOW,
       V2_SOFTWARE_ERROR,DISPLAY_BAD_STATE,DISPLAY_WRITE_ERROR,DISPLAY_WRITE_TIMEOUT,
       V2_HARDWARE_ERROR,V2_HARDWARE_TIMEOUT,HDMI_FRAME_ERROR,HDMI_FRAME_TIMEOUT,
       WINDOW_GATHER_ERROR,WINDOW_GATHER_TIMEOUT,
       CONCAT_HARDWARE_ERROR,CONCAT_HARDWARE_TIMEOUT,TCM_STARTUP_FAULT,
       IMAGE_HARDWARE_ERROR,IMAGE_HARDWARE_TIMEOUT };
static uint8_t header[16], data[MAX_DATA];
static uint32_t graph_words[GRAPH_MAX_OPS][GRAPH_WORDS_PER_OP];
static uint32_t sequence, opcode, data_len;
static uint32_t crc_table[256];
static uint32_t graph_fast_mode,graph_window_mode,graph_concat_mode;
static uint32_t window_jobs,window_hw_layers,window_direct_layers,window_sw_layers;
static uint32_t window_failures,window_last_error,window_timeout_latched;
static uint64_t window_wait_total,window_read_total,window_write_total;
static uint64_t window_hit_total,window_miss_total,window_active_total,window_stall_total;
static uint32_t graph_requant_acc_bound;
static uint32_t graph_s3_mode,graph_s3_fuse_lut,graph_s3_lut_addr;
static uint32_t graph_s3_output_addr,graph_s3_used_lut;
static uint32_t s3_jobs,s3_fallbacks,s3_lut_jobs,s3_read_total,s3_write_total;
static uint64_t s3_wait_ticks_total,s3_active_cycles_total,s3_stall_cycles_total;
static uint64_t profile_counters[P_COUNTER_COUNT];
static uint32_t profile_batches,profile_ops,profile_errors;
static uint32_t graph_profile_active,profile_session;
/* Per logical operator: elapsed CPU timer ticks, status/flags, actual NPU
 * active and DMA-wait deltas. A fused LUT has bit30 and zero exclusive ticks;
 * its work is included in the preceding Requant record. Read after Graph. */
static uint32_t rv32_layer_profile[GRAPH_MAX_OPS][4];
static uint32_t rv32_layer_completed;
/* Only internal Graph204 v2 can enable the camera/model disjoint-region
 * lease. External monitor commands continue to enforce camera exclusivity. */
static uint32_t camera_model_lease,cmos2_graph_active;
// 服务函数 cmos2_graph_begin。
// 接口参数：void；返回值及副作用由下列函数体定义。
// 参数入口：无位置参数；类型、指针限定及返回约定沿用下列声明。
static void cmos2_graph_begin(void);
// 服务函数 cmos2_graph_progress。
// 接口参数：uint32_t completed；返回值及副作用由下列函数体定义。
// 参数入口：completed；类型、指针限定及返回约定沿用下列声明。
static void cmos2_graph_progress(uint32_t completed);
#ifdef BOARD_HOST_UNIT
// 服务函数 fence_all。
// 接口参数：void；返回值及副作用由下列函数体定义。
// 参数入口：无位置参数；类型、指针限定及返回约定沿用下列声明。
static void fence_all(void) { __sync_synchronize(); }
#else
// 服务函数 fence_all。
// 接口参数：void；返回值及副作用由下列函数体定义。
// 参数入口：无位置参数；类型、指针限定及返回约定沿用下列声明。
static void fence_all(void) { __asm__ volatile("fence iorw,iorw" ::: "memory"); }
#endif
/* cache-reloc-01: buffers placed at or above 0x8400_0000 live in the D$
 * window. Hardware engines (camera, NPU/Window Store, Requant, Tensor,
 * Concat) write DDR behind the CPU cache, so any CPU read of their output
 * must drop stale lines first. Write 1 to the cache-control word from ITCM
 * and wait for the done status (3). Uncached addresses are unaffected. */
#ifdef BOARD_HOST_UNIT
// 服务函数 cache_invalidate。
// 接口参数：void；返回值及副作用由下列函数体定义。
// 参数入口：无位置参数；类型、指针限定及返回约定沿用下列声明。
static void cache_invalidate(void) { __sync_synchronize(); }
#else
// 服务函数 cache_invalidate。
// 接口参数：void；返回值及副作用由下列函数体定义。
// 参数入口：无位置参数；类型、指针限定及返回约定沿用下列声明。
static void cache_invalidate(void) {
    // 硬件/可见性边界：R32(0x30000100u)=1u;。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    R32(0x30000100u)=1u;
    for(uint32_t guard=0;guard<1000000u&&R32(0x30000100u)!=3u;guard++){}
}
#endif
#ifdef BOARD_SIM_PROFILE_TICKS
static uint32_t sim_profile_ticks;
// 服务函数 ticks。
// 接口参数：void；返回值及副作用由下列函数体定义。
// 参数入口：无位置参数；类型、指针限定及返回约定沿用下列声明。
static uint32_t ticks(void) { return ++sim_profile_ticks; }
#else
// 服务函数 ticks。
// 接口参数：void；返回值及副作用由下列函数体定义。
// 参数入口：无位置参数；类型、指针限定及返回约定沿用下列声明。
static uint32_t ticks(void) { return R32(0x30000000u); }
#endif
// 服务函数 tx。
// 接口参数：uint8_t v；返回值及副作用由下列函数体定义。
// 参数入口：v；类型、指针限定及返回约定沿用下列声明。
static void tx(uint8_t v) { live_preview_service();R32(0x40000000u)=v; }
// 服务函数 text。
// 接口参数：const char *s；返回值及副作用由下列函数体定义。
// 参数入口：s；类型、指针限定及返回约定沿用下列声明。
static void text(const char *s) { while(*s) tx((uint8_t)*s++); }
// 服务函数 get32。
// 接口参数：const uint8_t *p；返回值及副作用由下列函数体定义。
// 参数入口：p；类型、指针限定及返回约定沿用下列声明。
static uint32_t get32(const uint8_t *p) {
    return (uint32_t)p[0]|((uint32_t)p[1]<<8)|((uint32_t)p[2]<<16)|((uint32_t)p[3]<<24);
}
// 服务函数 set32。
// 接口参数：uint8_t *p,uint32_t v；返回值及副作用由下列函数体定义。
// 参数入口：p, v；类型、指针限定及返回约定沿用下列声明。
static void set32(uint8_t *p,uint32_t v) {
    for(unsigned i=0;i<4;i++) p[i]=(uint8_t)(v>>(8*i));
}
// 服务函数 crc_init。
// 接口参数：void；返回值及副作用由下列函数体定义。
// 参数入口：无位置参数；类型、指针限定及返回约定沿用下列声明。
static void crc_init(void) {
    for(unsigned i=0;i<256;i++) {
        uint32_t c=i;
        for(unsigned j=0;j<8;j++) c=(c>>1)^((0u-(c&1u))&0xedb88320u);
        crc_table[i]=c;
    }
}
// 服务函数 crc_bytes。
// 接口参数：uint32_t crc,const uint8_t *p,uint32_t n；返回值及副作用由下列函数体定义。
// 参数入口：crc, p, n；类型、指针限定及返回约定沿用下列声明。
static uint32_t crc_bytes(uint32_t crc,const uint8_t *p,uint32_t n) {
    while(n--) crc=crc_table[(crc^*p++)&255]^(crc>>8);
    return crc;
}
static uint32_t monitor_background_allowed;
// 服务函数 cmos2_background_service。
// 接口参数：void；返回值及副作用由下列函数体定义。
// 参数入口：无位置参数；类型、指针限定及返回约定沿用下列声明。
static void cmos2_background_service(void);
// 服务函数 rx。
// 接口参数：uint8_t *v,uint32_t timeout；返回值及副作用由下列函数体定义。
// 参数入口：v, timeout；类型、指针限定及返回约定沿用下列声明。
static int rx(uint8_t *v,uint32_t timeout) {
    uint32_t begin=ticks();
    do {
        live_preview_service();
        // 控制边界：R32(0x60000024u)&1u；仅在该条件成立时进入本分支。
        if(R32(0x60000024u)&1u) { *v=(uint8_t)R32(0x60000028u); return 1; }
        // 控制边界：monitor_background_allowed；仅在该条件成立时进入本分支。
        if(monitor_background_allowed)cmos2_background_service();
    } while((uint32_t)(ticks()-begin)<timeout);
    return 0;
}
// 服务函数 receive。
// 接口参数：uint8_t *p,uint32_t n；返回值及副作用由下列函数体定义。
// 参数入口：p, n；类型、指针限定及返回约定沿用下列声明。
static int receive(uint8_t *p,uint32_t n) {
    while(n--) if(!rx(p++,HZ/4)) return 0;
    return 1;
}
// 服务函数 drain。
// 接口参数：void；返回值及副作用由下列函数体定义。
// 参数入口：无位置参数；类型、指针限定及返回约定沿用下列声明。
static void drain(void) {
    uint8_t ignored;
    while(rx(&ignored,HZ/10)) { }
    // 硬件/可见性边界：R32(0x6000002cu)=3;。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    R32(0x6000002cu)=3;
}
// 服务函数 reply。
// 接口参数：uint32_t status,uint32_t length；返回值及副作用由下列函数体定义。
// 参数入口：status, length；类型、指针限定及返回约定沿用下列声明。
static void reply(uint32_t status,uint32_t length) {
    uint8_t tail[4];
    set32(header,sequence);set32(header+4,opcode|0x80000000u);
    set32(header+8,status);set32(header+12,length);
    uint32_t crc=crc_bytes(crc_bytes(0xffffffffu,header,16),data,length)^0xffffffffu;
    set32(tail,crc);text("AST1");
    for(unsigned i=0;i<16;i++) tx(header[i]);
    for(unsigned i=0;i<length;i++) tx(data[i]);
    for(unsigned i=0;i<4;i++) tx(tail[i]);
}
// 服务函数 range。
// 接口参数：uint32_t base,uint32_t length；返回值及副作用由下列函数体定义。
// 参数入口：base, length；类型、指针限定及返回约定沿用下列声明。
static int range(uint32_t base,uint32_t length) {
    return base>=DDR_BASE && base<DDR_END && length && length<=DDR_END-base;
}
// 服务函数 overlap。
// 接口参数：uint32_t a,uint32_t a_length,uint32_t b,uint32_t b_length；返回值及副作用由下列函数体定义。
// 参数入口：a, a_length, b, b_length；类型、指针限定及返回约定沿用下列声明。
static int overlap(uint32_t a,uint32_t a_length,uint32_t b,uint32_t b_length) {
    return a<b+b_length && b<a+a_length;
}
#include "image_accel.h"
// 服务函数 crc_memory。
// 接口参数：uint32_t base,uint32_t length；返回值及副作用由下列函数体定义。
// 参数入口：base, length；类型、指针限定及返回约定沿用下列声明。
static uint32_t crc_memory(uint32_t base,uint32_t length) {
    // 硬件/可见性边界：cache_invalidate(); /* the buffer may have been written by a hardware engine */。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    cache_invalidate();   /* the buffer may have been written by a hardware engine */
    uint32_t crc=0xffffffffu;
    for(uint32_t i=0;i<length;i++) crc=crc_table[(crc^R8(base+i))&255u]^(crc>>8);
    return crc^0xffffffffu;
}
// 服务函数 test_pixel。
// 接口参数：uint32_t x,uint32_t y；返回值及副作用由下列函数体定义。
// 参数入口：x, y；类型、指针限定及返回约定沿用下列声明。
static uint16_t test_pixel(uint32_t x,uint32_t y) {
    return (uint16_t)((((x*3u+y*5u)&31u)<<11) |
                      (((x*7u+y*11u)&63u)<<5) |
                      ((x*13u+y*17u)&31u));
}
// 服务函数 matrix_range。
// 接口参数：uint32_t base,uint32_t rows,uint32_t stride,uint32_t width；返回值及副作用由下列函数体定义。
// 参数入口：base, rows, stride, width；类型、指针限定及返回约定沿用下列声明。
static int matrix_range(uint32_t base,uint32_t rows,uint32_t stride,uint32_t width) {
    /* Division bounds the multiplication and avoids any 32-bit wrap. */
    return range(base,width) && rows && stride>=width &&
           rows-1<=(DDR_END-base-width)/stride;
}
// 服务函数 npu_launch_words。
// 接口参数：const uint32_t w[12],uint32_t *begin；返回值及副作用由下列函数体定义。
// 参数入口：w；类型、指针限定及返回约定沿用下列声明。
static uint32_t npu_launch_words(const uint32_t w[12],uint32_t *begin) {
    // 控制边界：(R32(NPU+0x0cu)&0x47u)!=5u；仅在该条件成立时进入本分支。
    if((R32(NPU+0x0cu)&0x47u)!=5u) return NPU_BUSY;
    // 硬件/可见性边界：R32(NPU+0x14u)=3;R32(NPU+0x78u)=0xfff;R32(NPU+0x10u)=3;。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    R32(NPU+0x14u)=3;R32(NPU+0x78u)=0xfff;R32(NPU+0x10u)=3;
    for(unsigned i=0;i<12;i++) R32(NPU+0x20u+4*i)=w[i];
    // 硬件/可见性边界：fence_all();。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    fence_all();
    // 硬件/可见性边界：*begin=ticks();R32(NPU+0x50u)=1;。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    *begin=ticks();R32(NPU+0x50u)=1;
    return OK;
}
// 服务函数 npu_finish_words。
// 接口参数：uint32_t begin,uint32_t result[8]；返回值及副作用由下列函数体定义。
// 参数入口：result；类型、指针限定及返回约定沿用下列声明。
static uint32_t npu_finish_words(uint32_t begin,uint32_t result[8]) {
    uint32_t poll_begin=graph_profile_active?ticks():0u;
    while(!(R32(NPU+0x0cu)&0x40u)) {
        live_preview_service();
        // 控制边界：(uint32_t)(ticks()-begin)>HZ*5u；仅在该条件成立时进入本分支。
        if((uint32_t)(ticks()-begin)>HZ*5u) {
            // 控制边界：graph_profile_active；仅在该条件成立时进入本分支。
            if(graph_profile_active) {
                uint32_t waited=ticks()-poll_begin;
                profile_counters[P_NPU_POLL_TICKS]+=waited;
                profile_counters[P_CPU_POLL_TICKS]+=waited;
            }
            return NPU_TIMEOUT;
        }
    }
    // 控制边界：graph_profile_active；仅在该条件成立时进入本分支。
    if(graph_profile_active) {
        uint32_t waited=ticks()-poll_begin;
        profile_counters[P_NPU_POLL_TICKS]+=waited;
        profile_counters[P_CPU_POLL_TICKS]+=waited;
    }
    // 硬件/可见性边界：fence_all();。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    fence_all();
    uint32_t elapsed=ticks()-begin;
    for(unsigned i=0;i<5;i++) result[i]=R32(NPU+0x60u+4*i);
    // 硬件/可见性边界：result[5]=R32(NPU+0x78u);result[6]=R32(NPU+0x14u);。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    result[5]=R32(NPU+0x78u);result[6]=R32(NPU+0x14u);
    result[7]=elapsed;
    // 硬件/可见性边界：R32(NPU+0x74u)=1;R32(NPU+0x14u)=3;。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    R32(NPU+0x74u)=1;R32(NPU+0x14u)=3;
    // 控制边界：result[1] || result[5]；仅在该条件成立时进入本分支。
    if(result[1] || result[5]) return NPU_ERROR;
    return OK;
}
// 服务函数 npu_execute_words。
// 接口参数：const uint32_t w[12],uint32_t result[8]；返回值及副作用由下列函数体定义。
// 参数入口：w, result；类型、指针限定及返回约定沿用下列声明。
static uint32_t npu_execute_words(const uint32_t w[12],uint32_t result[8]) {
    uint32_t begin,status=npu_launch_words(w,&begin);
    return status==OK?npu_finish_words(begin,result):status;
}
// 服务函数 npu_run。
// 接口参数：void；返回值及副作用由下列函数体定义。
// 参数入口：无位置参数；类型、指针限定及返回约定沿用下列声明。
static uint32_t npu_run(void) {
    uint32_t w[12],result[8];
    // 控制边界：data_len!=48；仅在该条件成立时进入本分支。
    if(data_len!=48) return BAD_LENGTH;
    for(unsigned i=0;i<12;i++) w[i]=get32(data+4*i);
    uint32_t m=w[3]&65535u,n=w[3]>>16,k=w[4]&65535u;
    uint32_t input_bytes=1u+((w[4]>>16)&1u),fmt=w[8]&3u;
    // 控制边界：(w[4]>>17) || (w[8]>>11) || fmt>2 || ((w[8]>>2)&3u)>2 ||；仅在该条件成立时进入本分支。
    if((w[4]>>17) || (w[8]>>11) || fmt>2 || ((w[8]>>2)&3u)>2 ||
       ((w[8]>>5)&63u)>47 || !m || !n || !k) return BAD_RANGE;
    uint32_t output_bytes=1u<<fmt;
    // 控制边界：!matrix_range(w[0],m,w[5],k*input_bytes) ||；仅在该条件成立时进入本分支。
    if(!matrix_range(w[0],m,w[5],k*input_bytes) ||
       !matrix_range(w[1],k,w[6],n*input_bytes) ||
       !matrix_range(w[2],m,w[7],n*output_bytes)) return BAD_RANGE;
    uint32_t aend=w[0]+(m-1)*w[5]+k*input_bytes;
    uint32_t bend=w[1]+(k-1)*w[6]+n*input_bytes;
    uint32_t cend=w[2]+(m-1)*w[7]+n*output_bytes;
    // 控制边界：(w[2]<aend && w[0]<cend) || (w[2]<bend && w[1]<cend)；仅在该条件成立时进入本分支。
    if((w[2]<aend && w[0]<cend) || (w[2]<bend && w[1]<cend)) return BAD_RANGE;
    uint32_t status=npu_execute_words(w,result);
    // 控制边界：status==OK || status==NPU_ERROR；仅在该条件成立时进入本分支。
    if(status==OK || status==NPU_ERROR)
        for(unsigned i=0;i<8;i++) set32(data+4*i,result[i]);
    return status;
}
#ifdef BOARD_SIM_GRAPH_METRICS
static uint32_t sim_npu_cycles,sim_npu_commands,sim_im2col_ticks;
#endif
static uint32_t window_async_owned,window_async_begin,window_async_expected_bytes;
// 服务函数 window_launch_impl。
// 接口参数：uint32_t input,uint32_t scratch,；返回值及副作用由下列函数体定义。
// 参数入口：scratch, s, l, first, count, flush；类型、指针限定及返回约定沿用下列声明。
static uint32_t window_launch_impl(uint32_t input,uint32_t scratch,
        const soc_conv2d_shape *s,const soc_conv2d_layout *l,
        uint32_t first,uint32_t count,uint32_t flush) {
    // 控制边界：window_async_owned；仅在该条件成立时进入本分支。
    if(window_async_owned)return WINDOW_GATHER_ERROR;
    /* The same shape/range checks used by conv_run still apply. These port
     * width checks additionally prevent silent truncation of MMIO fields. */
    if(!count || count>64u || first>=l->rows || count>l->rows-first ||
       s->input_h>65535u || s->input_w>65535u || s->input_c>65535u ||
       l->output_h>65535u || l->output_w>65535u ||
       s->kernel_h>255u || s->kernel_w>255u ||
       s->stride_h>255u || s->stride_w>255u ||
       s->dilation_h>255u || s->dilation_w>255u ||
       s->pad_top>255u || s->pad_left>255u ||
       s->pad_bottom>255u || s->pad_right>255u ||
       !range(input,l->input_bytes) ||
       !range(scratch,count*l->k) || (scratch&63u))
        return CONV_BAD_SHAPE;
    // 控制边界：R32(WINDOW_MMIO+0x4cu)!=WINDOW_ID；仅在该条件成立时进入本分支。
    if(R32(WINDOW_MMIO+0x4cu)!=WINDOW_ID) return WINDOW_GATHER_ERROR;
    // 控制边界：window_timeout_latched；仅在该条件成立时进入本分支。
    if(window_timeout_latched) return WINDOW_GATHER_ERROR;
    uint32_t begin=ticks(),state;
    while(1) {
        live_preview_service();
        // 硬件/可见性边界：state=R32(WINDOW_MMIO+0x30u);。
        // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
        state=R32(WINDOW_MMIO+0x30u);
        // 控制边界：state&(1u<<16)；仅在该条件成立时进入本分支。
        if(state&(1u<<16)) return WINDOW_GATHER_ERROR;
        // 控制边界：!(state&(1u<<15))；仅在该条件成立时进入本分支。
        if(!(state&(1u<<15))) return DDR_UNAVAILABLE;
        // 控制边界：state&(1u<<17)；仅在该条件成立时进入本分支。
        if(state&(1u<<17)) break;
        // 控制边界：(uint32_t)(ticks()-begin)>HZ*2u；仅在该条件成立时进入本分支。
        if((uint32_t)(ticks()-begin)>HZ*2u)
            return WINDOW_GATHER_TIMEOUT;
    }
    uint32_t first_oy=first/l->output_w,first_ox=first%l->output_w;
    // 硬件/可见性边界：R32(WINDOW_MMIO+0x04u)=input;。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    R32(WINDOW_MMIO+0x04u)=input;
    // 硬件/可见性边界：R32(WINDOW_MMIO+0x08u)=scratch;。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    R32(WINDOW_MMIO+0x08u)=scratch;
    // 硬件/可见性边界：R32(WINDOW_MMIO+0x0cu)=first;。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    R32(WINDOW_MMIO+0x0cu)=first;
    // 硬件/可见性边界：R32(WINDOW_MMIO+0x10u)=(s->input_w<<16)|s->input_h;。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    R32(WINDOW_MMIO+0x10u)=(s->input_w<<16)|s->input_h;
    // 硬件/可见性边界：R32(WINDOW_MMIO+0x14u)=(l->output_h<<16)|s->input_c;。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    R32(WINDOW_MMIO+0x14u)=(l->output_h<<16)|s->input_c;
    // 硬件/可见性边界：R32(WINDOW_MMIO+0x18u)=(first_oy<<16)|l->output_w;。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    R32(WINDOW_MMIO+0x18u)=(first_oy<<16)|l->output_w;
    // 硬件/可见性边界：R32(WINDOW_MMIO+0x1cu)=(count<<16)|first_ox;。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    R32(WINDOW_MMIO+0x1cu)=(count<<16)|first_ox;
    // 硬件/可见性边界：R32(WINDOW_MMIO+0x20u)=(s->stride_w<<24)|(s->stride_h<<16)|。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    R32(WINDOW_MMIO+0x20u)=(s->stride_w<<24)|(s->stride_h<<16)|
                             (s->kernel_w<<8)|s->kernel_h;
    // 硬件/可见性边界：R32(WINDOW_MMIO+0x24u)=(s->pad_left<<24)|(s->pad_top<<16)|。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    R32(WINDOW_MMIO+0x24u)=(s->pad_left<<24)|(s->pad_top<<16)|
                             (s->dilation_w<<8)|s->dilation_h;
    // 硬件/可见性边界：R32(WINDOW_MMIO+0x28u)=(s->pad_right<<8)|s->pad_bottom;。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    R32(WINDOW_MMIO+0x28u)=(s->pad_right<<8)|s->pad_bottom;
    // 硬件/可见性边界：R32(WINDOW_MMIO+0x2cu)=flush?1u:0u;。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    R32(WINDOW_MMIO+0x2cu)=flush?1u:0u;
    // 硬件/可见性边界：fence_all();。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    fence_all();
    // 硬件/可见性边界：R32(WINDOW_MMIO)=1u;。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    R32(WINDOW_MMIO)=1u;
    window_async_owned=1u;window_async_begin=begin;
    window_async_expected_bytes=count*l->k;
    return OK;
}
// 服务函数 window_finish_impl。
// 接口参数：void；返回值及副作用由下列函数体定义。
// 参数入口：无位置参数；类型、指针限定及返回约定沿用下列声明。
static uint32_t window_finish_impl(void) {
    // 控制边界：!window_async_owned；仅在该条件成立时进入本分支。
    if(!window_async_owned)return WINDOW_GATHER_ERROR;
    uint32_t begin=window_async_begin,state;
    uint32_t poll_begin=ticks();
    while(!(R32(WINDOW_MMIO+0x30u)&2u)) {
        live_preview_service();
        // 控制边界：(uint32_t)(ticks()-begin)>HZ*2u；仅在该条件成立时进入本分支。
        if((uint32_t)(ticks()-begin)>HZ*2u)
            return WINDOW_GATHER_TIMEOUT;
    }
    uint32_t poll_ticks=ticks()-poll_begin;
    // 硬件/可见性边界：fence_all();。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    fence_all();
    // 硬件/可见性边界：state=R32(WINDOW_MMIO+0x30u);。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    state=R32(WINDOW_MMIO+0x30u);
    // 硬件/可见性边界：uint32_t written=R32(WINDOW_MMIO+0x38u);。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    uint32_t written=R32(WINDOW_MMIO+0x38u);
    // 硬件/可见性边界：uint32_t read_bytes=R32(WINDOW_MMIO+0x34u);。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    uint32_t read_bytes=R32(WINDOW_MMIO+0x34u);
    // 硬件/可见性边界：uint32_t active=R32(WINDOW_MMIO+0x44u);。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    uint32_t active=R32(WINDOW_MMIO+0x44u);
    // 硬件/可见性边界：uint32_t stalled=R32(WINDOW_MMIO+0x48u);。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    uint32_t stalled=R32(WINDOW_MMIO+0x48u);
    window_read_total+=read_bytes;window_write_total+=written;
    // 硬件/可见性边界：window_hit_total+=R32(WINDOW_MMIO+0x3cu);。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    window_hit_total+=R32(WINDOW_MMIO+0x3cu);
    // 硬件/可见性边界：window_miss_total+=R32(WINDOW_MMIO+0x40u);。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    window_miss_total+=R32(WINDOW_MMIO+0x40u);
    window_active_total+=active;window_stall_total+=stalled;
    // 控制边界：graph_profile_active；仅在该条件成立时进入本分支。
    if(graph_profile_active) {
        profile_counters[P_WINDOW_GATHER_TICKS]+=(uint32_t)(ticks()-begin);
        profile_counters[P_WINDOW_READ_BYTES]+=read_bytes;
        profile_counters[P_WINDOW_WRITE_BYTES]+=written;
        profile_counters[P_WINDOW_ACTIVE_UI_CYCLES]+=active;
        profile_counters[P_WINDOW_STALL_UI_CYCLES]+=stalled;
        profile_counters[P_CPU_POLL_TICKS]+=poll_ticks;
    }
    window_async_owned=0u;
    // 控制边界：(state&0x1fe0u) || (state&(1u<<14)) || (state&(1u<<16)) ||；仅在该条件成立时进入本分支。
    if((state&0x1fe0u) || (state&(1u<<14)) || (state&(1u<<16)) ||
       !(state&(1u<<13)) || written!=window_async_expected_bytes || (read_bytes&15u))
        return WINDOW_GATHER_ERROR;
    return OK;
}
// 服务函数 window_record_error。
// 接口参数：uint32_t status；返回值及副作用由下列函数体定义。
// 参数入口：status；类型、指针限定及返回约定沿用下列声明。
static uint32_t window_record_error(uint32_t status) {
    // 控制边界：status!=OK；仅在该条件成立时进入本分支。
    if(status!=OK) {
        window_failures++;window_last_error=status;
        // 控制边界：status==WINDOW_GATHER_TIMEOUT；仅在该条件成立时进入本分支。
        if(status==WINDOW_GATHER_TIMEOUT)window_timeout_latched=1u;
    }
    return status;
}
// 服务函数 window_gather_launch。
// 接口参数：uint32_t input,uint32_t scratch,；返回值及副作用由下列函数体定义。
// 参数入口：scratch, s, l, first, count, flush；类型、指针限定及返回约定沿用下列声明。
static uint32_t window_gather_launch(uint32_t input,uint32_t scratch,
        const soc_conv2d_shape *s,const soc_conv2d_layout *l,
        uint32_t first,uint32_t count,uint32_t flush) {
    return window_record_error(window_launch_impl(input,scratch,s,l,first,count,flush));
}
// 服务函数 window_gather_finish。
// 接口参数：void；返回值及副作用由下列函数体定义。
// 参数入口：无位置参数；类型、指针限定及返回约定沿用下列声明。
static uint32_t window_gather_finish(void) {
    uint32_t begin=window_async_begin;
    uint32_t status=window_finish_impl();
    /* Command wall time now includes overlap with other NPU N groups.
     * UI ACTIVE and remaining poll ticks are the measured activity/wait;
     * this duration must never be added to NPU as exclusive latency. */
    window_wait_total+=(uint32_t)(ticks()-begin);
    // 控制边界：status==OK；仅在该条件成立时进入本分支。
    if(status==OK)window_jobs++;
    return window_record_error(status);
}
// 服务函数 window_gather_tile。
// 接口参数：uint32_t input,uint32_t scratch,；返回值及副作用由下列函数体定义。
// 参数入口：scratch, s, l, first, count, flush；类型、指针限定及返回约定沿用下列声明。
static uint32_t window_gather_tile(uint32_t input,uint32_t scratch,
        const soc_conv2d_shape *s,const soc_conv2d_layout *l,
        uint32_t first,uint32_t count,uint32_t flush) {
    uint32_t status=window_gather_launch(input,scratch,s,l,first,count,flush);
    return status==OK?window_gather_finish():status;
}
// 服务函数 window_probe_run。
// 接口参数：uint32_t input；返回值及副作用由下列函数体定义。
// 参数入口：无位置参数；类型、指针限定及返回约定沿用下列声明。
static uint32_t window_probe_run(uint32_t input) {
    /* One bounded gather for CPU/DDR bring-up, without launching NPU.
     * Payload is the existing Conv geometry plus first/count/flush words. */
    if(data_len!=84u)return BAD_LENGTH;
    // 控制边界：camera_writing()&&!camera_model_lease；仅在该条件成立时进入本分支。
    if(camera_writing()&&!camera_model_lease)return CAMERA_NOT_READY;
    uint32_t v[21];
    for(unsigned i=0;i<21u;i++)v[i]=get32(data+4u*i);
    soc_conv2d_shape s;memcpy(&s,&v[3],sizeof(s));
    soc_conv2d_layout l;
    // 控制边界：!soc_conv2d_layout_int8_i32(&s,&l) || v[20]>1u；仅在该条件成立时进入本分支。
    if(!soc_conv2d_layout_int8_i32(&s,&l) || v[20]>1u)
        return CONV_BAD_SHAPE;
    // 控制边界：!range(input,l.input_bytes) || !v[19] || v[19]>64u ||；仅在该条件成立时进入本分支。
    if(!range(input,l.input_bytes) || !v[19] || v[19]>64u ||
       !range(v[2],v[19]*l.k) || (v[2]&63u) ||
       overlap(input,l.input_bytes,v[2],v[19]*l.k))return BAD_RANGE;
    uint64_t begin=soc_ticks64();
    uint32_t result=window_gather_tile(input,v[2],&s,&l,v[18],v[19],v[20]);
    uint64_t elapsed=soc_ticks64()-begin;
    set32(data,WINDOW_ID);set32(data+4,input);set32(data+8,v[2]);
    set32(data+12,v[18]);set32(data+16,v[19]);set32(data+20,l.k);
    // 硬件/可见性边界：set32(data+24,R32(WINDOW_MMIO+0x30u));。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    set32(data+24,R32(WINDOW_MMIO+0x30u));
    // 硬件/可见性边界：set32(data+28,R32(WINDOW_MMIO+0x38u));。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    set32(data+28,R32(WINDOW_MMIO+0x38u));
    set32(data+32,(uint32_t)elapsed);set32(data+36,(uint32_t)(elapsed>>32));
    return result;
}
#include "conv_service_hardware.h"
// 服务函数 conv_run。
// 接口参数：uint32_t input；返回值及副作用由下列函数体定义。
// 参数入口：无位置参数；类型、指针限定及返回约定沿用下列声明。
static uint32_t conv_run(uint32_t input) {
    // 控制边界：data_len!=72u；仅在该条件成立时进入本分支。
    if(data_len!=72u) return BAD_LENGTH;
    // 控制边界：camera_writing()&&!camera_model_lease；仅在该条件成立时进入本分支。
    if(camera_writing()&&!camera_model_lease) return CAMERA_NOT_READY;
    uint32_t v[18];
    for(unsigned i=0;i<18;i++) v[i]=get32(data+4*i);
    soc_conv2d_shape shape;memcpy(&shape,&v[3],sizeof(shape));
    soc_conv2d_layout layout;
    // 控制边界：!soc_conv2d_layout_int8_i32(&shape,&layout)；仅在该条件成立时进入本分支。
    if(!soc_conv2d_layout_int8_i32(&shape,&layout)) return CONV_BAD_SHAPE;
    uint32_t weights=v[0],output=v[1],scratch=v[2];
    uint32_t scratch_stride,scratch_bytes;
    // 控制边界：!soc_conv2d_workspace_bytes(&shape,&layout,&scratch_stride,；仅在该条件成立时进入本分支。
    if(!soc_conv2d_workspace_bytes(&shape,&layout,&scratch_stride,
                                     &scratch_bytes)) return CONV_BAD_SHAPE;
    // 控制边界：(output&3u) || !range(input,layout.input_bytes) ||；仅在该条件成立时进入本分支。
    if((output&3u) || !range(input,layout.input_bytes) ||
       !range(weights,layout.weight_bytes) ||
       !range(output,layout.output_bytes) ||
       (scratch_bytes && (!range(scratch,scratch_bytes) || (scratch&63u))))
        return BAD_RANGE;
    const uint32_t addresses[4]={input,weights,output,scratch};
    const uint32_t lengths[4]={layout.input_bytes,layout.weight_bytes,
                                layout.output_bytes,scratch_bytes};
    for(unsigned i=0;i<4;i++)
        for(unsigned j=i+1;j<4;j++)
            // 控制边界：lengths[i] && lengths[j] &&；仅在该条件成立时进入本分支。
            if(lengths[i] && lengths[j] &&
               overlap(addresses[i],lengths[i],addresses[j],lengths[j]))
                return BAD_RANGE;
    // 控制边界：graph_window_mode；仅在该条件成立时进入本分支。
    if(graph_window_mode)return conv_service_run(input,weights,output,scratch,scratch_stride,scratch_bytes,&shape,&layout);
    uint32_t begin=ticks(),im2col_ticks=0,npu_ticks=0,npu_cycles=0,tiles=0;
    // 控制边界：window_async_owned；仅在该条件成立时进入本分支。
    if(window_async_owned)return WINDOW_GATHER_ERROR;
    uint32_t slot=0,prepared=0;
    for(uint32_t first=0;first<layout.rows;) {
        uint32_t count=layout.rows-first;
        // 控制边界：count>shape.tile_m；仅在该条件成立时进入本分支。
        if(count>shape.tile_m) count=shape.tile_m;
        uint32_t a=soc_conv2d_direct_hwc(&shape)?
            input+first*layout.k:scratch+slot*scratch_stride;
        // 控制边界：scratch_bytes && !prepared；仅在该条件成立时进入本分支。
        if(scratch_bytes && !prepared) {
            uint32_t phase=ticks();
            // 控制边界：graph_window_mode；仅在该条件成立时进入本分支。
            if(graph_window_mode) {
                uint32_t window_status=window_gather_tile(input,a,&shape,
                                             &layout,first,count,first==0u);
                // 控制边界：window_status!=OK；仅在该条件成立时进入本分支。
                if(window_status!=OK) return window_status;
            } else {
                soc_im2col_int8_tile((const volatile int8_t *)(uintptr_t)input,
                    (volatile int8_t *)(uintptr_t)a,&shape,&layout,first,count);
                // 硬件/可见性边界：fence_all();im2col_ticks+=ticks()-phase;。
                // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
                fence_all();im2col_ticks+=ticks()-phase;
            }
        }
        uint32_t next_first=first+count,next_prepared=0;
        for(uint32_t col=0;col<shape.output_c;col+=8u) {
            uint32_t group=shape.output_c-col;
            // 控制边界：group>8u；仅在该条件成立时进入本分支。
            if(group>8u) group=8u;
            uint32_t w[12]={a,weights+col*layout.k,
                output+first*shape.output_c*4u+col*4u,(group<<16)|count,
                layout.k,layout.k,group,shape.output_c*4u,
                2u,0x80000000u,0x7fffffffu,0x434f0000u|tiles};
            uint32_t completion[8]={0},launched;
            uint32_t status=npu_launch_words(w,&launched);
            // 控制边界：status!=OK；仅在该条件成立时进入本分支。
            if(status!=OK) {
                // 控制边界：next_prepared && graph_window_mode && window_async_owned；仅在该条件成立时进入本分支。
                if(next_prepared && graph_window_mode && window_async_owned)
                    (void)window_gather_finish();
                set32(data,SOC_CONV2D_ID);set32(data+4,first);
                set32(data+8,status);set32(data+12,0u);
                return status;
            }
            // 控制边界：scratch_bytes && !next_prepared && next_first<layout.rows；仅在该条件成立时进入本分支。
            if(scratch_bytes && !next_prepared && next_first<layout.rows) {
                uint32_t next_count=layout.rows-next_first;
                // 控制边界：next_count>shape.tile_m；仅在该条件成立时进入本分支。
                if(next_count>shape.tile_m) next_count=shape.tile_m;
                uint32_t phase=ticks();
                // 控制边界：graph_window_mode；仅在该条件成立时进入本分支。
                if(graph_window_mode) {
                    uint32_t window_status=window_gather_launch(input,
                        scratch+(slot^1u)*scratch_stride,&shape,&layout,
                        next_first,next_count,0u);
                    // 控制边界：window_status!=OK；仅在该条件成立时进入本分支。
                    if(window_status!=OK) {
                        /* A prior NPU command may still be reading the other
                         * scratch slot. Drain it before propagating the
                         * gather failure; do not reuse either slot. */
                        uint32_t drain=npu_finish_words(launched,completion);
                        return drain==OK?window_status:drain;
                    }
                } else {
                    soc_im2col_int8_tile((const volatile int8_t *)(uintptr_t)input,
                        (volatile int8_t *)(uintptr_t)(scratch+(slot^1u)*scratch_stride),
                        &shape,&layout,next_first,next_count);
                    // 硬件/可见性边界：fence_all();im2col_ticks+=ticks()-phase;。
                    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
                    fence_all();im2col_ticks+=ticks()-phase;
                }
                next_prepared=1;
            }
            status=npu_finish_words(launched,completion);
            // 控制边界：status!=OK；仅在该条件成立时进入本分支。
            if(status!=OK) {
                // 控制边界：next_prepared && graph_window_mode && window_async_owned；仅在该条件成立时进入本分支。
                if(next_prepared && graph_window_mode && window_async_owned)
                    (void)window_gather_finish();
                set32(data,SOC_CONV2D_ID);set32(data+4,first);
                set32(data+8,status);
                set32(data+12,(status==NPU_ERROR)?completion[1]:0u);
                return status;
            }
            npu_ticks+=completion[7];npu_cycles+=completion[2];
#ifdef BOARD_SIM_GRAPH_METRICS
            sim_npu_cycles+=completion[2];sim_npu_commands++;
#endif
        }
        // 控制边界：next_prepared && graph_window_mode；仅在该条件成立时进入本分支。
        if(next_prepared && graph_window_mode) {
            uint32_t window_status=window_gather_finish();
            // 控制边界：window_status!=OK；仅在该条件成立时进入本分支。
            if(window_status!=OK)return window_status;
        }
        first=next_first;slot^=1u;prepared=next_prepared;tiles++;
    }
    // 控制边界：graph_window_mode；仅在该条件成立时进入本分支。
    if(graph_window_mode) {
        // 控制边界：scratch_bytes；仅在该条件成立时进入本分支。
        if(scratch_bytes)window_hw_layers++;else window_direct_layers++;
    // 控制边界：scratch_bytes；仅在该条件成立时进入本分支。
    } else if(scratch_bytes)window_sw_layers++;
    // 硬件/可见性边界：fence_all();。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    fence_all();
    uint32_t elapsed=ticks()-begin;
    // 控制边界：graph_profile_active；仅在该条件成立时进入本分支。
    if(graph_profile_active) {
        profile_counters[P_IM2COL_TICKS]+=im2col_ticks;
        profile_counters[P_NPU_COMPLETION_CYCLES]+=npu_cycles;
        profile_counters[P_NPU_COMMAND_TICKS]+=npu_ticks;
    }
    uint32_t crc=graph_fast_mode?0u:crc_memory(output,layout.output_bytes);
    set32(data,SOC_CONV2D_ID);set32(data+4,input);
    set32(data+8,output);set32(data+12,layout.rows);
    set32(data+16,layout.k);set32(data+20,shape.output_c);
    set32(data+24,tiles);set32(data+28,im2col_ticks);
    set32(data+32,npu_ticks);set32(data+36,npu_cycles);
    set32(data+40,elapsed);set32(data+44,crc);
#ifdef BOARD_SIM_GRAPH_METRICS
    sim_im2col_ticks+=im2col_ticks;
#endif
    return OK;
}
/* Returns 0 for software fallback, 1 for completed hardware, 2 for fault.
 * Only graph_run sets graph_requant_acc_bound after a successful immediately
 * preceding signed INT8 Conv and checks its shape/output address. UART opcode
 * 11 never authorizes this DMA; an arbitrary caller cannot assert a bound. */
static uint32_t s3_try_requant(uint32_t input,uint32_t output,
    uint32_t bias,uint32_t multiplier,uint32_t shift,
    uint32_t elements,uint32_t channels,const uint32_t *v) {
    // 控制边界：!graph_s3_mode；仅在该条件成立时进入本分支。
    if(!graph_s3_mode) return 0u;
    // 控制边界：!graph_requant_acc_bound || channels>256u ||；仅在该条件成立时进入本分支。
    if(!graph_requant_acc_bound || channels>256u ||
       ((input|output|bias|multiplier|shift)&15u) ||
       (graph_s3_lut_addr && (graph_s3_lut_addr&15u)) ||
       (int32_t)v[6]<-128 || (int32_t)v[6]>127 ||
       (int32_t)v[7]<-128 || (int32_t)v[7]>127 ||
       (int32_t)v[8]<-128 || (int32_t)v[8]>127 || v[9]>2u) {
        s3_fallbacks++;
        return 0u;
    }
    uint32_t target=graph_s3_lut_addr?graph_s3_output_addr:output;
    // 控制边界：(target&15u) || !range(target,(elements+15u)&~15u) ||；仅在该条件成立时进入本分支。
    if((target&15u) || !range(target,(elements+15u)&~15u) ||
       (graph_s3_lut_addr && !range(graph_s3_lut_addr,256u))) {
        s3_fallbacks++;
        return 0u;
    }
    // 硬件/可见性边界：R32(S3_MMIO+0x04u)=input;。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    R32(S3_MMIO+0x04u)=input;
    // 硬件/可见性边界：R32(S3_MMIO+0x08u)=target;。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    R32(S3_MMIO+0x08u)=target;
    // 硬件/可见性边界：R32(S3_MMIO+0x0cu)=bias;。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    R32(S3_MMIO+0x0cu)=bias;
    // 硬件/可见性边界：R32(S3_MMIO+0x10u)=multiplier;。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    R32(S3_MMIO+0x10u)=multiplier;
    // 硬件/可见性边界：R32(S3_MMIO+0x14u)=shift;。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    R32(S3_MMIO+0x14u)=shift;
    // 硬件/可见性边界：R32(S3_MMIO+0x18u)=graph_s3_lut_addr;。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    R32(S3_MMIO+0x18u)=graph_s3_lut_addr;
    // 硬件/可见性边界：R32(S3_MMIO+0x1cu)=elements/channels;。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    R32(S3_MMIO+0x1cu)=elements/channels;
    // 硬件/可见性边界：R32(S3_MMIO+0x20u)=channels;。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    R32(S3_MMIO+0x20u)=channels;
    // 硬件/可见性边界：R32(S3_MMIO+0x24u)=graph_requant_acc_bound;。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    R32(S3_MMIO+0x24u)=graph_requant_acc_bound;
    // 硬件/可见性边界：R32(S3_MMIO+0x28u)=((v[8]&255u)<<24)|((v[7]&255u)<<16)|。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    R32(S3_MMIO+0x28u)=((v[8]&255u)<<24)|((v[7]&255u)<<16)|
                       ((v[6]&255u)<<8)|((graph_s3_lut_addr?1u:0u)<<2)|v[9];
    // 硬件/可见性边界：fence_all();。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    fence_all();
    uint32_t start=ticks(),status;
    // 硬件/可见性边界：R32(S3_MMIO)=1u;。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    R32(S3_MMIO)=1u;
    do {
        live_preview_service();
        // 硬件/可见性边界：status=R32(S3_MMIO+0x2cu);。
        // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
        status=R32(S3_MMIO+0x2cu);
        // 控制边界：status&0x202u；仅在该条件成立时进入本分支。
        if(status&0x202u) break; /* rejected or done */
    } while(ticks()-start<HZ*10u);
    uint32_t s3_waited=ticks()-start;
    s3_wait_ticks_total+=s3_waited;
    // 控制边界：graph_profile_active；仅在该条件成立时进入本分支。
    if(graph_profile_active) {
        profile_counters[P_S3_POLL_TICKS]+=s3_waited;
        profile_counters[P_CPU_POLL_TICKS]+=s3_waited;
    }
    // 控制边界：!(status&2u) || (status&(0xf0u|0x100u|0x200u|0x800u))；仅在该条件成立时进入本分支。
    if(!(status&2u) || (status&(0xf0u|0x100u|0x200u|0x800u)))
        return 2u;
    s3_jobs++;
    // 硬件/可见性边界：uint32_t bytes_read=R32(S3_MMIO+0x30u);。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    uint32_t bytes_read=R32(S3_MMIO+0x30u);
    // 硬件/可见性边界：uint32_t bytes_written=R32(S3_MMIO+0x34u);。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    uint32_t bytes_written=R32(S3_MMIO+0x34u);
    // 硬件/可见性边界：uint32_t stalled=R32(S3_MMIO+0x38u);。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    uint32_t stalled=R32(S3_MMIO+0x38u);
    // 硬件/可见性边界：uint32_t active=R32(S3_MMIO+0x3cu);。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    uint32_t active=R32(S3_MMIO+0x3cu);
    s3_read_total+=bytes_read;
    s3_write_total+=bytes_written;
    s3_stall_cycles_total+=stalled;
    s3_active_cycles_total+=active;
    // 控制边界：graph_profile_active；仅在该条件成立时进入本分支。
    if(graph_profile_active) {
        profile_counters[P_S3_READ_BYTES]+=bytes_read;
        profile_counters[P_S3_WRITE_BYTES]+=bytes_written;
        profile_counters[P_S3_STALL_UI_CYCLES]+=stalled;
        profile_counters[P_S3_ACTIVE_UI_CYCLES]+=active;
    }
    graph_s3_used_lut=graph_s3_lut_addr!=0u;
    // 控制边界：graph_s3_used_lut；仅在该条件成立时进入本分支。
    if(graph_s3_used_lut) s3_lut_jobs++;
    return 1u;
}
// 服务函数 requant_run。
// 接口参数：uint32_t input；返回值及副作用由下列函数体定义。
// 参数入口：无位置参数；类型、指针限定及返回约定沿用下列声明。
static uint32_t requant_run(uint32_t input) {
    // 控制边界：data_len!=40u；仅在该条件成立时进入本分支。
    if(data_len!=40u) return BAD_LENGTH;
    // 控制边界：camera_writing()&&!camera_model_lease；仅在该条件成立时进入本分支。
    if(camera_writing()&&!camera_model_lease) return CAMERA_NOT_READY;
    uint32_t v[10];
    for(unsigned i=0;i<10;i++) v[i]=get32(data+4*i);
    uint32_t output=v[0],bias=v[1],multiplier=v[2],shift=v[3];
    uint32_t elements=v[4],channels=v[5];
    // 控制边界：!elements || !channels || elements%channels ||；仅在该条件成立时进入本分支。
    if(!elements || !channels || elements%channels ||
       elements>(DDR_END-DDR_BASE)/4u || channels>(DDR_END-DDR_BASE)/4u ||
       ((input|bias|multiplier|shift)&3u)) return BAD_RANGE;
    uint32_t parameter_bytes=channels*4u,source_bytes=elements*4u;
    const uint32_t addresses[5]={input,output,bias,multiplier,shift};
    const uint32_t lengths[5]={source_bytes,elements,parameter_bytes,
                                parameter_bytes,parameter_bytes};
    for(unsigned i=0;i<5;i++) {
        // 控制边界：!range(addresses[i],lengths[i])；仅在该条件成立时进入本分支。
        if(!range(addresses[i],lengths[i])) return BAD_RANGE;
        for(unsigned j=0;j<i;j++)
            // 控制边界：overlap(addresses[i],lengths[i],addresses[j],lengths[j])；仅在该条件成立时进入本分支。
            if(overlap(addresses[i],lengths[i],addresses[j],lengths[j]))
                return BAD_RANGE;
    }
    uint32_t failed_index;
    uint32_t begin=ticks();
    const volatile int32_t *source=(const volatile int32_t *)(uintptr_t)input;
    volatile int8_t *destination=(volatile int8_t *)(uintptr_t)output;
    const volatile int32_t *bias_words=(const volatile int32_t *)(uintptr_t)bias;
    const volatile int32_t *mult_words=(const volatile int32_t *)(uintptr_t)multiplier;
    const volatile uint32_t *shift_words=(const volatile uint32_t *)(uintptr_t)shift;
    uint32_t hw=s3_try_requant(input,output,bias,multiplier,shift,
                               elements,channels,v);
    // 控制边界：hw==2u；仅在该条件成立时进入本分支。
    if(hw==2u) {
        set32(data,SOC_REQUANT_ID);set32(data+4,input);
        set32(data+8,output);set32(data+12,UINT32_MAX);
        return NPU_ERROR;
    }
    uint32_t result=hw==1u?SOC_RQ_OK:graph_requant_acc_bound?
        soc_requant_i32_i8_from_conv(source,destination,bias_words,
            mult_words,shift_words,elements,channels,(int32_t)v[6],
            (int32_t)v[7],(int32_t)v[8],v[9],graph_requant_acc_bound,
            &failed_index):
        soc_requant_i32_i8(source,destination,bias_words,mult_words,
            shift_words,elements,channels,(int32_t)v[6],(int32_t)v[7],
            (int32_t)v[8],v[9],&failed_index);
    // 硬件/可见性边界：fence_all();。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    fence_all();
    uint32_t compute_ticks=ticks()-begin;
    // 控制边界：result!=SOC_RQ_OK；仅在该条件成立时进入本分支。
    if(result!=SOC_RQ_OK) {
        set32(data,SOC_REQUANT_ID);set32(data+4,input);
        set32(data+8,output);set32(data+12,failed_index);
        return result==SOC_RQ_BIAS_OVERFLOW?REQUANT_BIAS_OVERFLOW:
               REQUANT_BAD_PARAMS;
    }
    uint32_t crc=0u,crc_ticks=0u;
    // 控制边界：!graph_fast_mode；仅在该条件成立时进入本分支。
    if(!graph_fast_mode) {
        begin=ticks();
        crc=crc_memory(output,elements);
        crc_ticks=ticks()-begin;
    }
    set32(data,SOC_REQUANT_ID);set32(data+4,input);
    set32(data+8,output);set32(data+12,elements);
    set32(data+16,compute_ticks);set32(data+20,crc);
    set32(data+24,crc_ticks);
    return OK;
}
#include "concat_hardware.h"
#include "shared_tensor_hardware.h"
// 服务函数 tensor_run。
// 接口参数：uint32_t input；返回值及副作用由下列函数体定义。
// 参数入口：无位置参数；类型、指针限定及返回约定沿用下列声明。
static uint32_t tensor_run(uint32_t input) {
    // 控制边界：data_len!=64u；仅在该条件成立时进入本分支。
    if(data_len!=64u) return BAD_LENGTH;
    // 控制边界：camera_writing()&&!camera_model_lease；仅在该条件成立时进入本分支。
    if(camera_writing()&&!camera_model_lease) return CAMERA_NOT_READY;
    uint32_t v[16];
    for(unsigned i=0;i<16;i++) v[i]=get32(data+4*i);
    soc_tensor_shape shape;memcpy(&shape,&v[2],sizeof(shape));
    soc_tensor_layout layout;
    // 控制边界：!soc_tensor_layout_int8(&shape,&layout)；仅在该条件成立时进入本分支。
    if(!soc_tensor_layout_int8(&shape,&layout)) return TENSOR_BAD_SHAPE;
    uint32_t output=v[0],aux=v[1];
    // 控制边界：!range(input,layout.input_bytes) || !range(output,layout.output_bytes) ||；仅在该条件成立时进入本分支。
    if(!range(input,layout.input_bytes) || !range(output,layout.output_bytes) ||
       overlap(input,layout.input_bytes,output,layout.output_bytes)) return BAD_RANGE;
    // 控制边界：layout.aux_bytes；仅在该条件成立时进入本分支。
    if(layout.aux_bytes) {
        // 控制边界：!range(aux,layout.aux_bytes) ||；仅在该条件成立时进入本分支。
        if(!range(aux,layout.aux_bytes) ||
           overlap(input,layout.input_bytes,aux,layout.aux_bytes) ||
           overlap(output,layout.output_bytes,aux,layout.aux_bytes))
            return BAD_RANGE;
    // 控制边界：aux；仅在该条件成立时进入本分支。
    } else if(aux) return BAD_RANGE;
    uint32_t begin=ticks();
    // 控制边界：graph_concat_mode && (shape.kind==SOC_TOP_POOL ||；仅在该条件成立时进入本分支。
    if(graph_concat_mode && (shape.kind==SOC_TOP_POOL ||
       shape.kind==SOC_TOP_ADD || shape.kind==SOC_TOP_UPSAMPLE)) {
        /* A failed or unsupported accepted Graph Tensor never falls back
         * over uncertain DDR output. All twelve model jobs use real DMA. */
        uint32_t status=shared_tensor_hardware_run(input,aux,output,&shape,&layout);
        // 控制边界：status!=OK；仅在该条件成立时进入本分支。
        if(status!=OK)return status;
    // 控制边界：shape.kind==SOC_TOP_CONCAT && graph_concat_mode &&；仅在该条件成立时进入本分支。
    } else if(shape.kind==SOC_TOP_CONCAT && graph_concat_mode &&
       concat_fast_supported(input,aux,output,&shape)) {
        uint32_t status=concat_hardware_run(input,aux,output,&shape,&layout);
        // 控制边界：status!=OK；仅在该条件成立时进入本分支。
        if(status!=OK)return status;
    } else {
        // 控制边界：shape.kind==SOC_TOP_CONCAT；仅在该条件成立时进入本分支。
        if(shape.kind==SOC_TOP_CONCAT) {
            concat_sw_layers++;
            // 控制边界：graph_concat_mode；仅在该条件成立时进入本分支。
            if(graph_concat_mode) {concat_fallbacks++;concat_unaligned_fallbacks++;}
        }
        soc_tensor_run_int8((const volatile int8_t *)(uintptr_t)input,
                          (const volatile int8_t *)(uintptr_t)aux,
                          (volatile int8_t *)(uintptr_t)output,
                          &shape,&layout);
    }
    // 硬件/可见性边界：fence_all();。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    fence_all();
    uint32_t compute_ticks=ticks()-begin;
    uint32_t crc=graph_fast_mode?0u:crc_memory(output,layout.output_bytes);
    set32(data,SOC_TENSOR_OPS_ID);set32(data+4,shape.kind);
    set32(data+8,input);set32(data+12,aux);set32(data+16,output);
    set32(data+20,layout.output_h);set32(data+24,layout.output_w);
    set32(data+28,layout.output_c);set32(data+32,compute_ticks);
    set32(data+36,crc);
    return OK;
}
// 服务函数 graph_buffer_clear。
// 接口参数：uint32_t address,uint32_t length,；返回值及副作用由下列函数体定义。
// 参数入口：address, length, descriptor_base, descriptor_bytes, trace_base, trace_bytes；类型、指针限定及返回约定沿用下列声明。
static int graph_buffer_clear(uint32_t address,uint32_t length,
                              uint32_t descriptor_base,uint32_t descriptor_bytes,
                              uint32_t trace_base,uint32_t trace_bytes) {
    return range(address,length) &&
           (!live_preview_owner || (address<0x81000000u && length<=0x81000000u-address)) &&
           !overlap(address,length,descriptor_base,descriptor_bytes) &&
           !overlap(address,length,trace_base,trace_bytes);
}
// 服务函数 s3_fuse_batch_allowed。
// 接口参数：uint32_t base,uint32_t count,uint32_t crc；返回值及副作用由下列函数体定义。
// 参数入口：base, count, crc；类型、指针限定及返回约定沿用下列声明。
static int s3_fuse_batch_allowed(uint32_t base,uint32_t count,uint32_t crc) {
    /* The packed 204-descriptor model is contiguous in DDR. Authenticating
     * the whole byte sequence allows legal Conv/Requant and Requant/SiLU
     * pairs that happen to cross the former UART batch boundaries. */
    if(base==soc_s3_fuse_full_graph.base &&
       count==soc_s3_fuse_full_graph.count &&
       crc==soc_s3_fuse_full_graph.crc32) return 1;
    for(uint32_t i=0;i<13u;i++)
        // 控制边界：soc_s3_fuse_batches[i].base==base &&；仅在该条件成立时进入本分支。
        if(soc_s3_fuse_batches[i].base==base &&
           soc_s3_fuse_batches[i].count==count &&
           soc_s3_fuse_batches[i].crc32==crc) return 1;
    return 0;
}
static uint32_t graph_compile_only;
// 服务函数 graph_compile_loaded。
// 接口参数：uint32_t count,uint32_t flags；返回值及副作用由下列函数体定义。
// 参数入口：count, flags；类型、指针限定及返回约定沿用下列声明。
static uint32_t graph_compile_loaded(uint32_t count,uint32_t flags);
// 服务函数 graph_run。
// 接口参数：uint32_t descriptor_base；返回值及副作用由下列函数体定义。
// 参数入口：descriptor_base；类型、指针限定及返回约定沿用下列声明。
static uint32_t graph_run(uint32_t descriptor_base) {
    // 控制边界：data_len!=16u；仅在该条件成立时进入本分支。
    if(data_len!=16u) return BAD_LENGTH;
    // 控制边界：camera_writing()&&!camera_model_lease；仅在该条件成立时进入本分支。
    if(camera_writing()&&!camera_model_lease) return CAMERA_NOT_READY;
    uint32_t raw_count=get32(data),count=raw_count&GRAPH_COUNT_MASK;
    uint32_t fast=(raw_count&GRAPH_FAST_FLAG)!=0u;
    uint32_t profile_requested=(raw_count&GRAPH_PROFILE_FLAG)!=0u;
    uint32_t profile_begin=profile_requested?ticks():0u;
    uint32_t window=(raw_count&GRAPH_WINDOW_FLAG)!=0u;
    uint32_t concat=(raw_count&GRAPH_CONCAT_FLAG)!=0u;
    uint32_t s3=(raw_count&GRAPH_S3_FLAG)!=0u;
    uint32_t fuse_lut=(raw_count&GRAPH_S3_FUSE_LUT_FLAG)!=0u;
    uint32_t final_crc_requested=!fast || (raw_count&GRAPH_FAST_FINAL_CRC_FLAG)!=0u;
    uint32_t trace_base=get32(data+4);
    uint32_t final_output=get32(data+8),final_bytes=get32(data+12);
    // 控制边界：(raw_count&~(GRAPH_FAST_FLAG|GRAPH_FAST_FINAL_CRC_FLAG|；仅在该条件成立时进入本分支。
    if((raw_count&~(GRAPH_FAST_FLAG|GRAPH_FAST_FINAL_CRC_FLAG|
                    GRAPH_S3_FLAG|GRAPH_S3_FUSE_LUT_FLAG|
                    GRAPH_PROFILE_FLAG|GRAPH_WINDOW_FLAG|GRAPH_CONCAT_FLAG|GRAPH_COUNT_MASK)) ||
       (!fast && (raw_count&GRAPH_FAST_FINAL_CRC_FLAG)) ||
       (profile_requested && !fast) ||
       (fuse_lut && (!fast || !s3)) ||
       !count || count>GRAPH_MAX_OPS ||
       (descriptor_base&3u) || (trace_base&3u)) return BAD_RANGE;
    uint32_t descriptor_bytes=count*GRAPH_WORDS_PER_OP*4u;
    uint32_t trace_bytes=count*GRAPH_TRACE_WORDS*4u;
    // 控制边界：!range(descriptor_base,descriptor_bytes) ||；仅在该条件成立时进入本分支。
    if(!range(descriptor_base,descriptor_bytes) ||
       !range(trace_base,trace_bytes) ||
       !range(final_output,final_bytes) ||
       overlap(descriptor_base,descriptor_bytes,trace_base,trace_bytes))
        return BAD_RANGE;
    for(uint32_t i=0;i<count;i++)
        for(uint32_t j=0;j<GRAPH_WORDS_PER_OP;j++)
            // 硬件/可见性边界：graph_words[i][j]=R32(descriptor_base+(i*GRAPH_WORDS_PER_OP+j)*4u);。
            // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
            graph_words[i][j]=R32(descriptor_base+(i*GRAPH_WORDS_PER_OP+j)*4u);
    // 控制边界：s3 && R32(S3_MMIO+0x40u)!=S3_ID；仅在该条件成立时进入本分支。
    if(s3 && R32(S3_MMIO+0x40u)!=S3_ID) return NPU_ERROR;
    // 控制边界：fuse_lut && !s3_fuse_batch_allowed(descriptor_base,count,；仅在该条件成立时进入本分支。
    if(fuse_lut && !s3_fuse_batch_allowed(descriptor_base,count,
                    crc_memory(descriptor_base,descriptor_bytes)))
        return GRAPH_BAD_DESCRIPTOR;
    uint32_t last_output=0,last_bytes=0;
    for(uint32_t i=0;i<count;i++) {
        const uint32_t *d=graph_words[i];
        uint32_t words=d[0]==10u?18u:d[0]==11u?10u:d[0]==12u?16u:0u;
        // 控制边界：!words || d[2]!=words*4u || d[3]；仅在该条件成立时进入本分支。
        if(!words || d[2]!=words*4u || d[3]) return GRAPH_BAD_DESCRIPTOR;
        for(uint32_t j=4u+words;j<GRAPH_WORDS_PER_OP;j++)
            // 控制边界：d[j]；仅在该条件成立时进入本分支。
            if(d[j]) return GRAPH_BAD_DESCRIPTOR;
        // 控制边界：d[0]==10u；仅在该条件成立时进入本分支。
        if(d[0]==10u) {
            soc_conv2d_shape s;memcpy(&s,&d[7],sizeof(s));
            soc_conv2d_layout l;
            uint32_t scratch_stride,scratch_bytes;
            // 控制边界：!soc_conv2d_layout_int8_i32(&s,&l) ||；仅在该条件成立时进入本分支。
            if(!soc_conv2d_layout_int8_i32(&s,&l) ||
               !soc_conv2d_workspace_bytes(&s,&l,&scratch_stride,
                                             &scratch_bytes) ||
               !graph_buffer_clear(d[1],l.input_bytes,descriptor_base,descriptor_bytes,trace_base,trace_bytes) ||
               !graph_buffer_clear(d[4],l.weight_bytes,descriptor_base,descriptor_bytes,trace_base,trace_bytes) ||
               !graph_buffer_clear(d[5],l.output_bytes,descriptor_base,descriptor_bytes,trace_base,trace_bytes) ||
               (scratch_bytes && !graph_buffer_clear(d[6],scratch_bytes,
                    descriptor_base,descriptor_bytes,trace_base,trace_bytes)))
                return GRAPH_BAD_DESCRIPTOR;
            last_output=d[5];last_bytes=l.output_bytes;
        // 控制边界：d[0]==11u；仅在该条件成立时进入本分支。
        } else if(d[0]==11u) {
            uint32_t elements=d[8],channels=d[9];
            // 控制边界：!elements || !channels || elements%channels ||；仅在该条件成立时进入本分支。
            if(!elements || !channels || elements%channels ||
               elements>(DDR_END-DDR_BASE)/4u ||
               channels>(DDR_END-DDR_BASE)/4u) return GRAPH_BAD_DESCRIPTOR;
            uint32_t param_bytes=channels*4u;
            // 控制边界：!graph_buffer_clear(d[1],elements*4u,descriptor_base,descriptor_bytes,trace_base,trace_bytes) ||；仅在该条件成立时进入本分支。
            if(!graph_buffer_clear(d[1],elements*4u,descriptor_base,descriptor_bytes,trace_base,trace_bytes) ||
               !graph_buffer_clear(d[4],elements,descriptor_base,descriptor_bytes,trace_base,trace_bytes) ||
               !graph_buffer_clear(d[5],param_bytes,descriptor_base,descriptor_bytes,trace_base,trace_bytes) ||
               !graph_buffer_clear(d[6],param_bytes,descriptor_base,descriptor_bytes,trace_base,trace_bytes) ||
               !graph_buffer_clear(d[7],param_bytes,descriptor_base,descriptor_bytes,trace_base,trace_bytes))
                return GRAPH_BAD_DESCRIPTOR;
            last_output=d[4];last_bytes=elements;
        } else {
            soc_tensor_shape s;memcpy(&s,&d[6],sizeof(s));
            soc_tensor_layout l;
            // 控制边界：!soc_tensor_layout_int8(&s,&l) ||；仅在该条件成立时进入本分支。
            if(!soc_tensor_layout_int8(&s,&l) ||
               !graph_buffer_clear(d[1],l.input_bytes,descriptor_base,descriptor_bytes,trace_base,trace_bytes) ||
               !graph_buffer_clear(d[4],l.output_bytes,descriptor_base,descriptor_bytes,trace_base,trace_bytes) ||
               (l.aux_bytes && !graph_buffer_clear(d[5],l.aux_bytes,descriptor_base,descriptor_bytes,trace_base,trace_bytes)))
                return GRAPH_BAD_DESCRIPTOR;
            last_output=d[4];last_bytes=l.output_bytes;
        }
    }
    // 控制边界：last_output!=final_output || last_bytes!=final_bytes；仅在该条件成立时进入本分支。
    if(last_output!=final_output || last_bytes!=final_bytes)
        return GRAPH_BAD_DESCRIPTOR;
    // 控制边界：graph_compile_only；仅在该条件成立时进入本分支。
    if(graph_compile_only)return graph_compile_loaded(count,raw_count);
    // 控制边界：cmos2_graph_active；仅在该条件成立时进入本分支。
    if(cmos2_graph_active)cmos2_graph_begin();
    // 控制边界：!conv_service_workflow_context &&；仅在该条件成立时进入本分支。
    if(!conv_service_workflow_context &&
       conv_service_frame_begin(0u,0u)!=OK)return NPU_ERROR;
    // 控制边界：!fast；仅在该条件成立时进入本分支。
    if(!fast)
        for(uint32_t j=0;j<trace_bytes;j+=4u) R32(trace_base+j)=0;
    rv32_layer_completed=0u;
    for(uint32_t i=0;i<count;i++)for(uint32_t j=0;j<4u;j++)rv32_layer_profile[i][j]=0u;
    uint32_t begin=ticks(),completed=0,failed_index=UINT32_MAX;
    uint32_t result=OK;
    // 控制边界：profile_requested；仅在该条件成立时进入本分支。
    if(profile_requested)
        profile_counters[P_GRAPH_VALIDATION_TICKS]+=(uint32_t)(begin-profile_begin);
    graph_fast_mode=fast;
    graph_window_mode=window;
    graph_concat_mode=concat;
    graph_s3_mode=s3;
    graph_s3_fuse_lut=fuse_lut;
    graph_profile_active=profile_requested;
    // 控制边界：profile_requested；仅在该条件成立时进入本分支。
    if(profile_requested) profile_session=1u;
    graph_requant_acc_bound=0u;
    for(uint32_t i=0;i<count;i++) {
        const uint32_t *d=graph_words[i];
        data_len=d[2];
        for(uint32_t j=0;j<data_len/4u;j++) set32(data+4u*j,d[4u+j]);
        uint32_t op_begin=(!fast || profile_requested)?ticks():0u;
        uint64_t active_before=profile_counters[P_NPU_ACTIVE_CYCLES];
        uint64_t dma_before=profile_counters[P_NPU_DMA_WAIT_CYCLES];
        uint32_t jobs_before=s3_jobs;
        // 控制边界：d[0]==10u；仅在该条件成立时进入本分支。
        if(d[0]==10u) result=conv_run(d[1]);
        // 控制边界：d[0]==11u；仅在该条件成立时进入本分支。
        else if(d[0]==11u) {
            graph_s3_lut_addr=0u;
            graph_s3_output_addr=0u;
            graph_s3_used_lut=0u;
            /* A successful immediately preceding Conv is the only trusted
             * source for a one-pass signed-INT32 Requant. For other sources,
             * the generic transactional preflight is retained. */
            if(i && graph_words[i-1][0]==10u) {
                const uint32_t *prior=graph_words[i-1];
                // 控制边界：prior[5]==d[1] && prior[10]==d[9]；仅在该条件成立时进入本分支。
                if(prior[5]==d[1] && prior[10]==d[9]) {
                    soc_conv2d_shape s;memcpy(&s,&prior[7],sizeof(s));
                    soc_conv2d_layout l;
                    // 控制边界：soc_conv2d_layout_int8_i32(&s,&l) &&；仅在该条件成立时进入本分支。
                    if(soc_conv2d_layout_int8_i32(&s,&l) &&
                       l.output_bytes==d[8]*4u && l.k<=INT32_MAX/16384u)
                        graph_requant_acc_bound=l.k*16384u;
                }
            }
            // 控制边界：graph_s3_fuse_lut && i+1u<count &&；仅在该条件成立时进入本分支。
            if(graph_s3_fuse_lut && i+1u<count &&
               graph_words[i+1u][0]==12u &&
               graph_words[i+1u][6]==SOC_TOP_LUT &&
               graph_words[i+1u][1]==d[4] &&
               (uint64_t)graph_words[i+1u][7]*graph_words[i+1u][8]*
                   graph_words[i+1u][9]==d[8]) {
                graph_s3_output_addr=graph_words[i+1u][4];
                graph_s3_lut_addr=graph_words[i+1u][5];
            }
            result=requant_run(d[1]);
            graph_requant_acc_bound=0u;
        }
        else result=tensor_run(d[1]);
        // 控制边界：profile_requested && result==OK；仅在该条件成立时进入本分支。
        if(profile_requested && result==OK) {
            uint32_t op_ticks=ticks()-op_begin;
            // 控制边界：d[0]==10u；仅在该条件成立时进入本分支。
            if(d[0]==10u) profile_counters[P_CONV_TICKS]+=op_ticks;
            // 控制边界：d[0]==11u；仅在该条件成立时进入本分支。
            else if(d[0]==11u)
                profile_counters[s3_jobs!=jobs_before?
                    P_HW_REQUANT_TICKS:P_SW_REQUANT_TICKS]+=op_ticks;
            // 控制边界：d[6]==SOC_TOP_CONCAT；仅在该条件成立时进入本分支。
            else if(d[6]==SOC_TOP_CONCAT)
                profile_counters[P_CONCAT_TICKS]+=op_ticks;
            // 控制边界：d[6]==SOC_TOP_UPSAMPLE；仅在该条件成立时进入本分支。
            else if(d[6]==SOC_TOP_UPSAMPLE)
                profile_counters[P_UPSAMPLE_TICKS]+=op_ticks;
            // 控制边界：d[6]==SOC_TOP_ADD；仅在该条件成立时进入本分支。
            else if(d[6]==SOC_TOP_ADD)
                profile_counters[P_ADD_TICKS]+=op_ticks;
            // 控制边界：d[6]==SOC_TOP_POOL；仅在该条件成立时进入本分支。
            else if(d[6]==SOC_TOP_POOL)
                profile_counters[P_POOL_TICKS]+=op_ticks;
            // 控制边界：d[6]==SOC_TOP_LUT；仅在该条件成立时进入本分支。
            else if(d[6]==SOC_TOP_LUT)
                profile_counters[P_SW_LUT_TICKS]+=op_ticks;
            rv32_layer_profile[i][0]=op_ticks;
            rv32_layer_profile[i][1]=0x80000000u|result;
            rv32_layer_profile[i][2]=(uint32_t)(profile_counters[P_NPU_ACTIVE_CYCLES]-active_before);
            rv32_layer_profile[i][3]=(uint32_t)(profile_counters[P_NPU_DMA_WAIT_CYCLES]-dma_before);
            rv32_layer_completed=i+1u;
        }
        // 控制边界：!fast；仅在该条件成立时进入本分支。
        if(!fast) {
            uint32_t elapsed=ticks()-op_begin;
            uint32_t crc=result==OK?get32(data+(d[0]==10u?44u:d[0]==11u?20u:36u)):0u;
            uint32_t op_output=d[0]==10u?d[5]:d[4];
            uint32_t offset=trace_base+i*GRAPH_TRACE_WORDS*4u;
            // 硬件/可见性边界：R32(offset)=i;R32(offset+4u)=d[0];R32(offset+8u)=result;。
            // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
            R32(offset)=i;R32(offset+4u)=d[0];R32(offset+8u)=result;
            // 硬件/可见性边界：R32(offset+12u)=elapsed;R32(offset+16u)=crc;。
            // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
            R32(offset+12u)=elapsed;R32(offset+16u)=crc;
            // 硬件/可见性边界：R32(offset+20u)=op_output;。
            // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
            R32(offset+20u)=op_output;
        }
        // 控制边界：result!=OK；仅在该条件成立时进入本分支。
        if(result!=OK) { failed_index=i;break; }
        // 控制边界：graph_s3_used_lut；仅在该条件成立时进入本分支。
        if(graph_s3_used_lut) {
            i++;completed++;graph_s3_used_lut=0u;
            // 控制边界：profile_requested；仅在该条件成立时进入本分支。
            if(profile_requested){rv32_layer_profile[i][1]=0xc0000000u;rv32_layer_completed=i+1u;}
        }
        completed++;
        // 控制边界：cmos2_graph_active；仅在该条件成立时进入本分支。
        if(cmos2_graph_active)cmos2_graph_progress(completed);
    }
    graph_fast_mode=0u;
    graph_window_mode=0u;
    graph_concat_mode=0u;
    graph_s3_mode=0u;
    graph_s3_fuse_lut=0u;
    graph_requant_acc_bound=0u;
    graph_profile_active=0u;
    // 硬件/可见性边界：fence_all();。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    fence_all();
    uint32_t elapsed=ticks()-begin;
    uint32_t trace_crc=fast?0u:crc_memory(trace_base,trace_bytes);
    uint32_t final_crc=(result==OK && final_crc_requested)?
        crc_memory(final_output,final_bytes):0u;
    // 控制边界：profile_requested；仅在该条件成立时进入本分支。
    if(profile_requested) {
        profile_counters[P_GRAPH_TICKS]+=(uint32_t)(ticks()-profile_begin);
        profile_batches++;
        profile_ops+=completed;
        // 控制边界：result!=OK；仅在该条件成立时进入本分支。
        if(result!=OK) profile_errors++;
    }
    set32(data,GRAPH_ID);set32(data+4,count);set32(data+8,completed);
    set32(data+12,failed_index);set32(data+16,elapsed);
    set32(data+20,trace_base);set32(data+24,trace_crc);
    set32(data+28,final_crc);
    return result;
}
// 服务函数 detect_run。
// 接口参数：uint32_t descriptor_base；返回值及副作用由下列函数体定义。
// 参数入口：descriptor_base；类型、指针限定及返回约定沿用下列声明。
static uint32_t detect_run(uint32_t descriptor_base) {
    // 控制边界：data_len!=40u；仅在该条件成立时进入本分支。
    if(data_len!=40u) return BAD_LENGTH;
    // 控制边界：camera_writing()&&!camera_model_lease；仅在该条件成立时进入本分支。
    if(camera_writing()&&!camera_model_lease) return CAMERA_NOT_READY;
    uint32_t head_count=get32(data),output=get32(data+32),scratch=get32(data+36);
    soc_yolov5_options options={get32(data+4),get32(data+8),get32(data+12),
        get32(data+16),get32(data+20),get32(data+24),get32(data+28)};
    // 控制边界：!head_count || head_count>3u || (descriptor_base&3u) ||；仅在该条件成立时进入本分支。
    if(!head_count || head_count>3u || (descriptor_base&3u) ||
       (output&3u) || (scratch&3u) ||
       !options.max_candidates || options.max_candidates>1024u ||
       !options.max_results || options.max_results>64u ||
       options.max_results>options.max_candidates) return DETECT_BAD_PARAMS;
    uint32_t descriptor_bytes=head_count*32u;
    uint32_t output_bytes=options.max_results*sizeof(soc_detection);
    uint32_t scratch_bytes=options.max_candidates*sizeof(soc_detection);
    // 控制边界：!range(descriptor_base,descriptor_bytes) || !range(output,output_bytes) ||；仅在该条件成立时进入本分支。
    if(!range(descriptor_base,descriptor_bytes) || !range(output,output_bytes) ||
       !range(scratch,scratch_bytes) ||
       overlap(descriptor_base,descriptor_bytes,output,output_bytes) ||
       overlap(descriptor_base,descriptor_bytes,scratch,scratch_bytes) ||
       overlap(output,output_bytes,scratch,scratch_bytes)) return BAD_RANGE;
    soc_yolov5_head heads[3];
    for(uint32_t i=0;i<head_count;i++) {
        uint32_t d[8];
        for(uint32_t j=0;j<8;j++) d[j]=R32(descriptor_base+i*32u+j*4u);
        // 控制边界：d[6] || d[7] || (d[4]&1u) || (d[5]&1u) ||；仅在该条件成立时进入本分支。
        if(d[6] || d[7] || (d[4]&1u) || (d[5]&1u) ||
           !d[1] || d[1]>2048u || !d[2] || d[2]>2048u ||
           !options.class_count || options.class_count>80u) return DETECT_BAD_PARAMS;
        uint64_t bytes=(uint64_t)d[1]*d[2]*3u*(options.class_count+5u);
        // 控制边界：bytes>DDR_END-DDR_BASE || !range(d[0],(uint32_t)bytes) ||；仅在该条件成立时进入本分支。
        if(bytes>DDR_END-DDR_BASE || !range(d[0],(uint32_t)bytes) ||
           !range(d[4],12u) || !range(d[5],512u)) return BAD_RANGE;
        const uint32_t addresses[3]={d[0],d[4],d[5]};
        const uint32_t lengths[3]={(uint32_t)bytes,12u,512u};
        for(uint32_t j=0;j<3;j++)
            // 控制边界：overlap(addresses[j],lengths[j],descriptor_base,descriptor_bytes) ||；仅在该条件成立时进入本分支。
            if(overlap(addresses[j],lengths[j],descriptor_base,descriptor_bytes) ||
               overlap(addresses[j],lengths[j],output,output_bytes) ||
               overlap(addresses[j],lengths[j],scratch,scratch_bytes))
                return BAD_RANGE;
        heads[i].tensor=(const volatile int8_t *)(uintptr_t)d[0];
        heads[i].anchors_wh=(const volatile uint16_t *)(uintptr_t)d[4];
        heads[i].sigmoid_q15=(const volatile uint16_t *)(uintptr_t)d[5];
        heads[i].grid_w=d[1];heads[i].grid_h=d[2];heads[i].stride=d[3];
    }
    // 硬件/可见性边界：cache_invalidate(); /* head tensors come from NPU/Requant DMA */。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    cache_invalidate();   /* head tensors come from NPU/Requant DMA */
    uint32_t candidates=0,results=0,begin=ticks();
    uint32_t outcome=soc_yolov5_decode_nms(heads,head_count,&options,
        (volatile soc_detection *)(uintptr_t)scratch,
        (volatile soc_detection *)(uintptr_t)output,&candidates,&results);
    // 硬件/可见性边界：fence_all();。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    fence_all();
    uint32_t elapsed=ticks()-begin;
    // 控制边界：profile_session；仅在该条件成立时进入本分支。
    if(profile_session) profile_counters[P_DECODE_TICKS]+=elapsed;
    set32(data,0x31544544u); /* "DET1" */
    set32(data+4,candidates);set32(data+8,results);set32(data+12,elapsed);
    // 控制边界：outcome==SOC_DETECT_BAD_PARAMS；仅在该条件成立时进入本分支。
    if(outcome==SOC_DETECT_BAD_PARAMS) return DETECT_BAD_PARAMS;
    // 控制边界：outcome==SOC_DETECT_CANDIDATE_OVERFLOW；仅在该条件成立时进入本分支。
    if(outcome==SOC_DETECT_CANDIDATE_OVERFLOW) return DETECT_CANDIDATE_OVERFLOW;
    set32(data+16,output);set32(data+20,results*sizeof(soc_detection));
    set32(data+24,results?crc_memory(output,results*sizeof(soc_detection)):0u);
    return OK;
}
#include "ddr_hdmi_workflow.h"
#include "graph_executor.h"
#include "rv32_performance.h"
#include "live_preview.h"
#include "cmos2_workflow.h"
// 服务函数 cmos2_background_service。
// 接口参数：void；返回值及副作用由下列函数体定义。
// 参数入口：无位置参数；类型、指针限定及返回约定沿用下列声明。
static void cmos2_background_service(void) {
    static uint32_t last;uint32_t now=ticks();
    // 控制边界：cmos2_continuous&&(uint32_t)(now-last)>=HZ/4000u；仅在该条件成立时进入本分支。
    if(cmos2_continuous&&(uint32_t)(now-last)>=HZ/4000u){last=now;cmos2_idle_step();}
}
// 服务函数 camera_status。
// 接口参数：uint32_t elapsed；返回值及副作用由下列函数体定义。
// 参数入口：elapsed；类型、指针限定及返回约定沿用下列声明。
static void camera_status(uint32_t elapsed) {
    // 硬件/可见性边界：set32(data,R32(CAMERA+0x1cu));set32(data+4,R32(CAMERA+0x08u));。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    set32(data,R32(CAMERA+0x1cu));set32(data+4,R32(CAMERA+0x08u));
    // 硬件/可见性边界：set32(data+8,R32(CAMERA+0x04u));set32(data+12,R32(CAMERA+0x18u));。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    set32(data+8,R32(CAMERA+0x04u));set32(data+12,R32(CAMERA+0x18u));
    // 硬件/可见性边界：set32(data+16,R32(CAMERA+0x0cu));set32(data+20,R32(CAMERA+0x10u));。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    set32(data+16,R32(CAMERA+0x0cu));set32(data+20,R32(CAMERA+0x10u));
    // 硬件/可见性边界：set32(data+24,R32(CAMERA+0x14u));set32(data+28,elapsed);。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    set32(data+24,R32(CAMERA+0x14u));set32(data+28,elapsed);
}
#include "camera_sccb_readback.h"
// 服务函数 camera_configuration_readback。
// 接口参数：uint32_t channel；返回值及副作用由下列函数体定义。
// 参数入口：channel；类型、指针限定及返回约定沿用下列声明。
static void camera_configuration_readback(uint32_t channel) {
    /* No general MMIO or arbitrary sensor writes are exposed. Sensor identity,
     * output geometry/format, PLL/dividers and sync polarity are read only. */
    static const uint16_t registers[]={
        0x300a,0x300b,0x3008,0x3017,0x3018,0x3034,0x3035,0x3036,0x3037,
        0x3039,0x3108,0x3800,0x3801,0x3802,0x3803,0x3804,0x3805,0x3806,
        0x3807,0x3808,0x3809,0x380a,0x380b,0x380c,0x380d,0x380e,0x380f,
        0x3810,0x3811,0x3812,0x3813,0x3814,0x3815,0x3820,0x3821,0x3824,
        0x4300,0x501f,0x460b,0x460c,0x4740,0x503d};
    // 控制边界：data_len || channel>1u；仅在该条件成立时进入本分支。
    if(data_len || channel>1u){reply(BAD_LENGTH,0);return;}
    // 控制边界：SCB_READ(0x6cu)!=0x31424353u；仅在该条件成立时进入本分支。
    if(SCB_READ(0x6cu)!=0x31424353u){reply(BAD_COMMAND,0);return;}
    // 控制边界：SCB_READ(0x64u)!=3u || !(R32(CAMERA+8u)&1u) || (SCB_READ(0x60u)&0x3fu)；仅在该条件成立时进入本分支。
    if(SCB_READ(0x64u)!=3u || !(R32(CAMERA+8u)&1u) || (SCB_READ(0x60u)&0x3fu))
        {reply(CAMERA_NOT_READY,0);return;}
    scb_context bus={channel,0,0,0};
    scb_lines(&bus,0,0);
    uint32_t before=SCB_READ(0x68u),ok=0;
    uint64_t started=ticks64();
    unsigned count=sizeof(registers)/sizeof(registers[0]);
    for(unsigned i=0;i<count;i++) {
        uint8_t value;
        uint32_t error=scb_read_register(&bus,registers[i],&value);
        set32(data+40u+8u*i,(uint32_t)registers[i]|((uint32_t)value<<16)|(error<<24));
        set32(data+44u+8u*i,bus.acks);
        // 控制边界：!error；仅在该条件成立时进入本分支。
        if(!error)ok++;
        /* An idle/clock fault applies to the whole bus; do not repeatedly clock
         * a stuck or disconnected interface. Remaining records are not run. */
        if(error==SCB_BUS_NOT_IDLE || error==SCB_CLOCK_TIMEOUT || error==SCB_STOP_ERROR) {
            for(unsigned j=i+1;j<count;j++) {
                set32(data+40u+8u*j,(uint32_t)registers[j]|0xff000000u);
                set32(data+44u+8u*j,0);
            }
            break;
        }
    }
    uint64_t elapsed=ticks64()-started;
    scb_lines(&bus,0,0);uint32_t after=SCB_READ(0x68u);
    SCB_WRITE(0x60u,0u);
    set32(data,0x31424353u);set32(data+4,1u);set32(data+8,channel);
    set32(data+12,count);set32(data+16,before);set32(data+20,after);
    set32(data+24,ok);set32(data+28,count-ok);set64(data+32,elapsed);
    reply(OK,40u+8u*count);
}
#include "startup_tcm_diag.h"
// 服务函数 execute。
// 接口参数：uint32_t argument；返回值及副作用由下列函数体定义。
// 参数入口：argument；类型、指针限定及返回约定沿用下列声明。
static void execute(uint32_t argument) {
    /* A failed local-memory selftest must never start DDR/model/camera tasks.
     * PING and read-only video status remain usable for controlled diagnosis. */
    if(boot_tcm_fault && opcode!=1u && !(opcode==22u && argument==0u))
        {reply(TCM_STARTUP_FAULT,0);return;}
    /* Stop/status must remain accessible after a DDR or NPU error. */
    if(opcode==26u){cmos2_control(argument);return;}
    // 控制边界：cmos2_continuous && opcode!=1u && opcode!=26u &&；仅在该条件成立时进入本分支。
    if(cmos2_continuous && opcode!=1u && opcode!=26u &&
       !(opcode==22u && argument==0u)) {reply(NPU_BUSY,0);return;}
    uint32_t count,status;
    /* Read-only service status remains accessible in quarantine. Existing
     * upload/control opcodes and their payload layouts are unchanged. */
    if(opcode==33u) {
        // 控制边界：argument||data_len；仅在该条件成立时进入本分支。
        if(argument||data_len){reply(BAD_LENGTH,0);return;}
        for(uint32_t i=0;i<16u;i++)set32(data+4u*i,R32(CONV_SERVICE_MMIO+4u*i));
        reply(OK,64u);return;
    }
    // 控制边界：conv_service_timeout_latched || (R32(GRAPH_EXECUTOR_MMIO+4u)&9u) ||；仅在该条件成立时进入本分支。
    if(conv_service_timeout_latched || (R32(GRAPH_EXECUTOR_MMIO+4u)&9u) ||
       // 硬件/可见性边界：(R32(CONV_SERVICE_MMIO+4u)&0x8001u)) {reply(NPU_BUSY,0);return;}。
       // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
       (R32(CONV_SERVICE_MMIO+4u)&0x8001u)) {reply(NPU_BUSY,0);return;}
    // 控制边界：opcode==1；仅在该条件成立时进入本分支。
    if(opcode==1) {
        // 控制边界：data_len>64；仅在该条件成立时进入本分支。
        if(data_len>64) { reply(BAD_LENGTH,0);return; }
        /* Echo a host nonce after fixed metadata, proving a live bidirectional link. */
        for(int i=(int)data_len-1;i>=0;i--) data[64+i]=data[i];
        set32(data,1);set32(data+4,HZ);set32(data+8,MAX_DATA);
        // 硬件/可见性边界：set32(data+12,R32(0x50000004u));set32(data+16,R32(NPU));。
        // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
        set32(data+12,R32(0x50000004u));set32(data+16,R32(NPU));
        // 硬件/可见性边界：set32(data+20,R32(NPU+4));set32(data+24,R32(NPU+8));。
        // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
        set32(data+20,R32(NPU+4));set32(data+24,R32(NPU+8));
        set32(data+28,DDR_BASE);set32(data+32,DDR_END);
        // 硬件/可见性边界：set32(data+36,R32(0x6000002cu));set32(data+40,R32(NPU+0x0c));。
        // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
        set32(data+36,R32(0x6000002cu));set32(data+40,R32(NPU+0x0c));
        // 硬件/可见性边界：set32(data+44,R32(NPU+0x78));。
        // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
        set32(data+44,R32(NPU+0x78));
        for(unsigned i=0;i<16;i++) data[48+i]=BOARD_BUILD_ID[i];
        reply(OK,64+data_len);return;
    }
    /* Video diagnostics remain available when DDR is not ready. Only the
     * bounded pattern selector is writable; no arbitrary MMIO access. Event
     * timestamps are immutable first-event snapshots until the next START. */
    if(opcode==22u) {
        // 控制边界：argument>1u || (argument==0u && data_len) ||；仅在该条件成立时进入本分支。
        if(argument>1u || (argument==0u && data_len) ||
           (argument==1u && data_len!=4u)) { reply(BAD_LENGTH,0);return; }
        // 控制边界：R32(VIDEO_MMIO)!=VIDEO_ID || R32(DISPLAY_MMIO)!=DISPLAY_ID；仅在该条件成立时进入本分支。
        if(R32(VIDEO_MMIO)!=VIDEO_ID || R32(DISPLAY_MMIO)!=DISPLAY_ID)
            {reply(BAD_COMMAND,0);return;}
        // 控制边界：argument==1u；仅在该条件成立时进入本分支。
        if(argument==1u) {
            uint32_t mode=get32(data);
            // 控制边界：mode>2u || (mode==2u && !(R32(DISPLAY_MMIO+4u)&16u))；仅在该条件成立时进入本分支。
            if(mode>2u || (mode==2u && !(R32(DISPLAY_MMIO+4u)&16u)))
                {reply(BAD_RANGE,0);return;}
            // 硬件/可见性边界：R32(VIDEO_MMIO+0x10u)=mode;fence_all();。
            // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
            R32(VIDEO_MMIO+0x10u)=mode;fence_all();
        }
        set32(data,0x32445648u);set32(data+4,2u);
        // 硬件/可见性边界：set32(data+8,HZ);set32(data+12,R32(0x50000004u));。
        // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
        set32(data+8,HZ);set32(data+12,R32(0x50000004u));
        for(uint32_t i=0;i<20u;i++)set32(data+16u+i*4u,R32(VIDEO_MMIO+i*4u));
        const uint32_t offsets[8]={4u,0x30u,0x34u,0x58u,0x48u,0x28u,0x2cu,0x50u};
        for(uint32_t i=0;i<8u;i++)set32(data+96u+i*4u,R32(DISPLAY_MMIO+offsets[i]));
        set64(data+128u,ticks64());reply(OK,136u);return;
    }
    // 控制边界：(R32(0x50000004u)&15u)!=3u；仅在该条件成立时进入本分支。
    if((R32(0x50000004u)&15u)!=3u) { reply(DDR_UNAVAILABLE,0);return; }
    /* Timeout leaves the in-flight command alone; do not let host overwrite its buffers. */
    if((R32(NPU+0x0cu)&3u)!=1u) { reply(NPU_BUSY,0);return; }
    // 根据 opcode 分派协议/运算类型，逐个分支保留原有返回约定。
    switch(opcode) {
    case 33:
        // 控制边界：data_len；仅在该条件成立时进入本分支。
        if(data_len){reply(BAD_LENGTH,0);return;}
        status=cmos2_display_colorbars(argument);reply(status,data_len);return;
    case 32: {
        // 控制边界：data_len || argument>=GRAPH_MAX_OPS；仅在该条件成立时进入本分支。
        if(data_len || argument>=GRAPH_MAX_OPS) {reply(BAD_LENGTH,0);return;}
        uint32_t n=GRAPH_MAX_OPS-argument;if(n>32u)n=32u;
        set32(data,0x314c3252u);set32(data+4u,argument);
        set32(data+8u,n);set32(data+12u,rv32_layer_completed);
        for(uint32_t i=0;i<n;i++)for(uint32_t j=0;j<4u;j++)
            set32(data+16u+i*16u+j*4u,rv32_layer_profile[argument+i][j]);
        reply(OK,16u+n*16u);return;
    }
    case 31:
        // 控制边界：data_len || argument；仅在该条件成立时进入本分支。
        if(data_len || argument) {reply(BAD_LENGTH,0);return;}
        rv32_perf_reply();return;
    case 29: {
        // 控制边界：data_len || argument；仅在该条件成立时进入本分支。
        if(data_len || argument) {reply(BAD_LENGTH,0);return;}
        const uint32_t words[8]={CONCAT_ID,1u,concat_jobs,concat_sw_layers,
            concat_fallbacks,concat_failures,concat_last_error,concat_unaligned_fallbacks};
        const uint64_t values[5]={concat_wait_total,concat_read_total,concat_write_total,
            concat_active_total,concat_stall_total};
        for(unsigned i=0;i<8u;i++)set32(data+4u*i,words[i]);
        for(unsigned i=0;i<5u;i++)set64(data+32u+8u*i,values[i]);
        set32(data+72u,concat_timeout_latched);reply(OK,76u);return;
    }
    case 30:
        /* Explicit hardware probe. Normal opcode12 remains software. */
        graph_concat_mode=1u;status=tensor_run(argument);graph_concat_mode=0u;
        reply(status,status==OK?40u:0u);return;
    case 27: {
        /* Read-only cumulative counters; no MMIO/DDR readback in timed graph. */
        if(data_len || argument) {reply(BAD_LENGTH,0);return;}
        const uint32_t words[8]={WINDOW_ID,1u,window_jobs,window_hw_layers,
            window_direct_layers,window_sw_layers,window_failures,window_last_error};
        const uint64_t values[7]={window_wait_total,window_read_total,window_write_total,
            window_hit_total,window_miss_total,window_active_total,window_stall_total};
        for(unsigned i=0;i<8u;i++)set32(data+4u*i,words[i]);
        for(unsigned i=0;i<7u;i++) {
            set32(data+32u+8u*i,(uint32_t)values[i]);
            set32(data+36u+8u*i,(uint32_t)(values[i]>>32));
        }
        set32(data+88u,window_timeout_latched);
        reply(OK,92u);return;
    }
    case 28:
        status=window_probe_run(argument);reply(status,data_len==84u?40u:0u);return;
    case 25:
        set32(data,0u);status=cmos2_run(argument);
        reply(status,get32(data)==CMOS2_WORKFLOW_ID?288u:0u);return;
    case 24:camera_configuration_readback(argument);return;
    case 21:
        set32(data,0u);status=displayready_run(argument);
        reply(status,get32(data)==WORKFLOW_ID?256u:0u);return;
    case 20: {
        // 控制边界：data_len!=4u；仅在该条件成立时进入本分支。
        if(data_len!=4u){reply(BAD_LENGTH,0);return;}
        uint32_t destination=get32(data);
        uint64_t started=ticks64();status=v2_hardware_run(argument,destination);
        uint64_t elapsed=ticks64()-started;
        set32(data,S2_ID);set32(data+4,argument);set32(data+8,destination);
        set32(data+12,SOC_V2_OUTPUT_BYTES);set64(data+16,elapsed);
        // 硬件/可见性边界：set32(data+24,R32(S2_MMIO+0x10u));set32(data+28,R32(S2_MMIO+0x0cu));。
        // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
        set32(data+24,R32(S2_MMIO+0x10u));set32(data+28,R32(S2_MMIO+0x0cu));
        reply(status,32u);return;
    }
    case 2:
        // 控制边界：data_len!=4；仅在该条件成立时进入本分支。
        if(data_len!=4) { reply(BAD_LENGTH,0);return; }
        count=get32(data);
        // 控制边界：!count || count>MAX_DATA；仅在该条件成立时进入本分支。
        if(!count || count>MAX_DATA) { reply(BAD_LENGTH,0);return; }
        // 控制边界：!range(argument,count)；仅在该条件成立时进入本分支。
        if(!range(argument,count)) { reply(BAD_RANGE,0);return; }
        // 硬件/可见性边界：fence_all();。
        // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
        fence_all();
        for(unsigned i=0;i<count;i++) data[i]=R8(argument+i);
        reply(OK,count);return;
    case 3:
        // 控制边界：!range(argument,data_len)；仅在该条件成立时进入本分支。
        if(!range(argument,data_len)) { reply(BAD_RANGE,0);return; }
        // 控制边界：data_len；仅在该条件成立时进入本分支。
        if(data_len) {
            // 控制边界：conv_service_model_epoch==UINT32_MAX；仅在该条件成立时进入本分支。
            if(conv_service_model_epoch==UINT32_MAX){reply(NPU_ERROR,0);return;}
            conv_service_model_epoch++;
        }
        for(unsigned i=0;i<data_len;i++) R8(argument+i)=data[i];
        // 硬件/可见性边界：fence_all();reply(OK,0);return;。
        // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
        fence_all();reply(OK,0);return;
    case 4:
        status=npu_run();reply(status,(status==OK || status==NPU_ERROR)?32:0);return;
    case 5:
        // 控制边界：data_len；仅在该条件成立时进入本分支。
        if(data_len) { reply(BAD_LENGTH,0);return; }
        camera_status(0);reply(OK,32);return;
    case 23:
        /* Read-only DVP diagnostics with an explicit immutable snapshot.
         * No arbitrary MMIO access and no changes to sensor configuration. */
        if(data_len || argument>3u) { reply(BAD_LENGTH,0);return; }
        count=(argument&2u)?0x80u:0x20u;
        // 控制边界：argument&1u；仅在该条件成立时进入本分支。
        if(argument&1u) { R32(CAMERA+count)=1u;fence_all(); }
        for(unsigned i=0;i<16;i++)set32(data+4u*i,R32(CAMERA+count+4u*i));
        reply(OK,64);return;
    case 6:
        // 控制边界：data_len；仅在该条件成立时进入本分支。
        if(data_len) { reply(BAD_LENGTH,0);return; }
        // 控制边界：(argument&255u) || !range(argument,CAMERA_FRAME_BYTES)；仅在该条件成立时进入本分支。
        if((argument&255u) || !range(argument,CAMERA_FRAME_BYTES)) {
            reply(BAD_RANGE,0);return;
        }
        // 控制边界：!(R32(CAMERA+0x08u)&1u)；仅在该条件成立时进入本分支。
        if(!(R32(CAMERA+0x08u)&1u)) { reply(CAMERA_NOT_READY,0);return; }
        // 硬件/可见性边界：R32(CAMERA+0x04u)=argument;fence_all();。
        // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
        R32(CAMERA+0x04u)=argument;fence_all();
        // 硬件/可见性边界：set32(data,R32(CAMERA+0x04u));。
        // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
        set32(data,R32(CAMERA+0x04u));
        reply(OK,4);return;
    case 7:
        // 控制边界：data_len；仅在该条件成立时进入本分支。
        if(data_len) { reply(BAD_LENGTH,0);return; }
        // 硬件/可见性边界：status=R32(CAMERA+0x08u);。
        // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
        status=R32(CAMERA+0x08u);
        // 控制边界：(status&0x51u)!=0x51u；仅在该条件成立时进入本分支。
        if((status&0x51u)!=0x51u) { camera_status(0);reply(CAMERA_NOT_READY,32);return; }
        // 硬件/可见性边界：count=ticks();R32(CAMERA)=1u;fence_all();。
        // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
        count=ticks();R32(CAMERA)=1u;fence_all();
        while(!(R32(CAMERA+0x08u)&4u)) {
            // 控制边界：(uint32_t)(ticks()-count)>HZ*5u；仅在该条件成立时进入本分支。
            if((uint32_t)(ticks()-count)>HZ*5u) {
                camera_status(ticks()-count);reply(CAMERA_TIMEOUT,32);return;
            }
        }
        // 硬件/可见性边界：fence_all();cache_invalidate();camera_status(ticks()-count);。
        // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
        fence_all();cache_invalidate();camera_status(ticks()-count);
        reply(((get32(data+4)&8u) && get32(data+24)==0u &&
               get32(data+16)==1280u*720u) ? OK : CAMERA_BAD_FRAME,32);
        return;
    case 8: {
        /* Model-independent spatial transform. Input and output must be
         * disjoint within the NPU-visible uncached 64 MiB DDR aperture. */
        if(data_len!=4) { reply(BAD_LENGTH,0);return; }
        uint32_t destination=get32(data);
        // 控制边界：(argument&1u) || !range(argument,SOC_FRAME_BYTES) ||；仅在该条件成立时进入本分支。
        if((argument&1u) || !range(argument,SOC_FRAME_BYTES) ||
           !range(destination,SOC_TENSOR_BYTES) ||
           overlap(argument,SOC_FRAME_BYTES,destination,SOC_TENSOR_BYTES)) {
            reply(BAD_RANGE,0);return;
        }
        // 控制边界：camera_writing()||live_preview_memory_owned()；仅在该条件成立时进入本分支。
        if(camera_writing()||live_preview_memory_owned()) { reply(CAMERA_NOT_READY,0);return; }
        count=ticks();
        // 硬件/可见性边界：cache_invalidate(); /* the frame was written by the camera DMA */。
        // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
        cache_invalidate();   /* the frame was written by the camera DMA */
        soc_preprocess_rgb565((const volatile uint8_t *)(uintptr_t)argument,
                                (volatile uint8_t *)(uintptr_t)destination);
        // 硬件/可见性边界：fence_all();。
        // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
        fence_all();
        uint32_t compute_ticks=ticks()-count;
        count=ticks();
        uint32_t crc=crc_memory(destination,SOC_TENSOR_BYTES);
        uint32_t crc_ticks=ticks()-count;
        set32(data,SOC_PREPROCESS_ID);set32(data+4,argument);
        set32(data+8,destination);set32(data+12,SOC_TENSOR_BYTES);
        set32(data+16,compute_ticks);set32(data+20,crc);
        set32(data+24,crc_ticks);reply(OK,28);return;
    }
    case 9: {
        /* Deterministic full-frame diagnostic input for testing the same
         * DDR preprocessing path before the physical sensor is connected. */
        if(data_len) { reply(BAD_LENGTH,0);return; }
        // 控制边界：(argument&1u) || !range(argument,SOC_FRAME_BYTES)；仅在该条件成立时进入本分支。
        if((argument&1u) || !range(argument,SOC_FRAME_BYTES)) {
            reply(BAD_RANGE,0);return;
        }
        // 控制边界：camera_writing()||live_preview_memory_owned()；仅在该条件成立时进入本分支。
        if(camera_writing()||live_preview_memory_owned()) { reply(CAMERA_NOT_READY,0);return; }
        count=ticks();
        for(uint32_t y=0;y<SOC_FRAME_HEIGHT;y++)
            for(uint32_t x=0;x<SOC_FRAME_WIDTH;x++)
                R16(argument+(y*SOC_FRAME_WIDTH+x)*2u)=test_pixel(x,y);
        // 硬件/可见性边界：fence_all();。
        // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
        fence_all();
        uint32_t fill_ticks=ticks()-count;
        uint32_t crc=crc_memory(argument,SOC_FRAME_BYTES);
        set32(data,SOC_PREPROCESS_ID);set32(data+4,argument);
        set32(data+8,SOC_FRAME_BYTES);set32(data+12,fill_ticks);
        set32(data+16,crc);reply(OK,20);return;
    }
    case 10:
        status=conv_run(argument);
        reply(status,status==OK?48u:
              (status==NPU_ERROR || status==NPU_TIMEOUT || status==NPU_BUSY)?16u:0u);
        return;
    case 11:
        status=requant_run(argument);
        reply(status,status==OK?28u:
              (status==REQUANT_BAD_PARAMS || status==REQUANT_BIAS_OVERFLOW)?16u:0u);
        return;
    case 12:
        status=tensor_run(argument);reply(status,status==OK?40u:0u);return;
    case 13: {
        // 控制边界：data_len；仅在该条件成立时进入本分支。
        if(data_len) { reply(BAD_LENGTH,0);return; }
        // 控制边界：argument!=0xffffffffu && argument>15u；仅在该条件成立时进入本分支。
        if(argument!=0xffffffffu && argument>15u) {
            reply(BAD_RANGE,0);return;
        }
        // 硬件/可见性边界：uint32_t previous=R32(0x50000000u);。
        // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
        uint32_t previous=R32(0x50000000u);
        // 控制边界：argument!=0xffffffffu；仅在该条件成立时进入本分支。
        if(argument!=0xffffffffu) R32(0x50000000u)=argument;
        // 硬件/可见性边界：fence_all();。
        // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
        fence_all();
        // 硬件/可见性边界：set32(data,previous);set32(data+4,R32(0x50000000u));。
        // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
        set32(data,previous);set32(data+4,R32(0x50000000u));
        // 硬件/可见性边界：set32(data+8,R32(0x50000004u));set32(data+12,ticks());。
        // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
        set32(data+8,R32(0x50000004u));set32(data+12,ticks());
        reply(OK,16);return;
    }
    case 14:
        status=graph_run(argument);
        reply(status,status==OK?32u:
              (status==NPU_ERROR || status==NPU_TIMEOUT || status==NPU_BUSY ||
               status==REQUANT_BAD_PARAMS || status==REQUANT_BIAS_OVERFLOW ||
               status==TENSOR_BAD_SHAPE)?32u:0u);
        return;
    case 15:
        status=detect_run(argument);
        reply(status,status==OK?28u:
              status==DETECT_CANDIDATE_OVERFLOW?16u:0u);
        return;
    case 17:
        // 控制边界：data_len || argument>1u；仅在该条件成立时进入本分支。
        if(data_len || argument>1u) {reply(BAD_LENGTH,0);return;}
        // 控制边界：argument==1u；仅在该条件成立时进入本分支。
        if(argument==1u) {
            s3_jobs=0;s3_fallbacks=0;s3_lut_jobs=0;
            s3_read_total=0;s3_write_total=0;
            s3_wait_ticks_total=0;s3_active_cycles_total=0;
            s3_stall_cycles_total=0;
        }
        set32(data,S3_ID);set32(data+4,s3_jobs);
        set32(data+8,s3_fallbacks);set32(data+12,s3_lut_jobs);
        set32(data+16,s3_read_total);set32(data+20,s3_write_total);
        set32(data+24,(uint32_t)s3_wait_ticks_total);
        set32(data+28,(uint32_t)(s3_wait_ticks_total>>32));
        set32(data+32,(uint32_t)s3_active_cycles_total);
        set32(data+36,(uint32_t)(s3_active_cycles_total>>32));
        set32(data+40,(uint32_t)s3_stall_cycles_total);
        set32(data+44,(uint32_t)(s3_stall_cycles_total>>32));
        reply(OK,48);return;
    case 18: {
        /* DTCM-only FAST_PROFILE snapshot. The host reads once after all
         * graph batches; no per-op UART traffic or tensor CRC is introduced. */
        if(data_len || argument>1u) {reply(BAD_LENGTH,0);return;}
        // 控制边界：argument==1u；仅在该条件成立时进入本分支。
        if(argument==1u) {
            for(uint32_t i=0;i<P_COUNTER_COUNT;i++)profile_counters[i]=0u;
            profile_batches=0;profile_ops=0;profile_errors=0;
            profile_session=1u;
        }
        set32(data,PROFILE_ID);set32(data+4,2u);
        set32(data+8,P_COUNTER_COUNT);
        set32(data+12,((1u<<(P_DECODE_TICKS+1u))-1u) |
              (1u<<P_V2_PREPROCESS_TICKS) | (1u<<P_DISPLAY_RESIZE_TICKS) |
              (1u<<P_DDR_FRAME_TO_DISPLAY_READY_TICKS) | (0x1fu<<P_WINDOW_GATHER_TICKS));
        set32(data+16,HZ);set32(data+20,BOARD_NPU_HZ);
        set32(data+24,93750000u);set32(data+28,profile_batches);
        set32(data+32,profile_ops);set32(data+36,profile_errors);
        for(uint32_t i=0;i<P_COUNTER_COUNT;i++) {
            set32(data+40u+i*8u,(uint32_t)profile_counters[i]);
            set32(data+44u+i*8u,(uint32_t)(profile_counters[i]>>32));
        }
        reply(OK,40u+P_COUNTER_COUNT*8u);return;
    }
    case 16: {
        /* Quantized 320-square model input. The caller must first verify a
         * completed valid capture when source comes from the camera. */
        if(data_len!=4u) { reply(BAD_LENGTH,0);return; }
        uint32_t destination=get32(data);
        // 控制边界：(argument&1u) || !range(argument,SOC_PP320_SOURCE_BYTES) ||；仅在该条件成立时进入本分支。
        if((argument&1u) || !range(argument,SOC_PP320_SOURCE_BYTES) ||
           !range(destination,SOC_PP320_TARGET_BYTES) ||
           overlap(argument,SOC_PP320_SOURCE_BYTES,
                   destination,SOC_PP320_TARGET_BYTES)) {
            reply(BAD_RANGE,0);return;
        }
        // 控制边界：camera_writing()||live_preview_memory_owned()；仅在该条件成立时进入本分支。
        if(camera_writing()||live_preview_memory_owned()) { reply(CAMERA_NOT_READY,0);return; }
        count=ticks();
        // 硬件/可见性边界：cache_invalidate(); /* the frame was written by the camera DMA */。
        // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
        cache_invalidate();   /* the frame was written by the camera DMA */
        uint32_t image_result=image_preprocess320(argument,destination,soc_model_input_lut);
        // 控制边界：image_result!=OK；仅在该条件成立时进入本分支。
        if(image_result!=OK){reply(image_result,0);return;}
        // 硬件/可见性边界：fence_all();。
        // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
        fence_all();
        uint32_t compute_ticks=ticks()-count;
        count=ticks();
        uint32_t crc=crc_memory(destination,SOC_PP320_TARGET_BYTES);
        uint32_t crc_ticks=ticks()-count;
        set32(data,SOC_PREPROCESS320_ID);set32(data+4,argument);
        set32(data+8,destination);set32(data+12,SOC_PP320_TARGET_BYTES);
        set32(data+16,compute_ticks);set32(data+20,crc);
        set32(data+24,crc_ticks);reply(OK,28u);return;
    }
    default: reply(BAD_COMMAND,0);return;
    }
}
// 服务函数 main。
// 接口参数：void；返回值及副作用由下列函数体定义。
// 参数入口：无位置参数；类型、指针限定及返回约定沿用下列声明。
int main(void) {
    const uint8_t magic[4]={'A','S','T','1'};
    uint8_t value,tail[4];uint32_t matched=0;
    // 硬件/可见性边界：crc_init();R32(0x6000002cu)=3;。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    crc_init();R32(0x6000002cu)=3;
    startup_tcm_diagnostics();
    text("SOC_MONITOR_READY build=" BOARD_BUILD_ID " cpu_hz=" BOARD_CPU_HZ_TEXT " protocol=1\r\n");
    // 硬件/可见性边界：R32(0x50000000u)=4;。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    R32(0x50000000u)=4;
    for(;;) {
        monitor_background_allowed=1u;
        int received=rx(&value,cmos2_continuous?HZ/100:HZ/4);
        monitor_background_allowed=0u;
        if(!received) { matched=0;cmos2_idle_step();continue; }
        if(value!=magic[matched]) { matched=(value==magic[0]);continue; }
        if(++matched<4) continue;
        matched=0;
        if(!receive(header,16)) { drain();continue; }
        sequence=get32(header);opcode=get32(header+4);
        uint32_t argument=get32(header+8);data_len=get32(header+12);
        if(data_len>MAX_DATA) { drain();reply(BAD_LENGTH,0);continue; }
        if(!receive(data,data_len) || !receive(tail,4)) { drain();reply(RX_TIMEOUT,0);continue; }
        if(R32(0x6000002cu)&3u) { R32(0x6000002cu)=3;reply(UART_ERROR,0);continue; }
        uint32_t crc=crc_bytes(crc_bytes(0xffffffffu,header,16),data,data_len)^0xffffffffu;
        if(crc!=get32(tail)) { reply(BAD_CRC,0);continue; }
        execute(argument);
        /* Do not let repeated host status requests starve autonomous capture. */
        if(cmos2_continuous && !(R32(0x60000024u)&1u))cmos2_idle_step();
    }
}
