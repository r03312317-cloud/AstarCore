/* Included after graph_run/detect_run; no AST1 replies inside this workflow. */
// 架构导读：display_workflow。
// 裸机控制固件组件，提供本文件定义的状态检查、数据结构和服务函数。
#define DISPLAY_MMIO 0x60001200u
#define DISPLAY_ID 0x31505344u
#define WORKFLOW_ID 0x31524456u /* VDR1 */
#define WORKFLOW_WORDS 24u
#include "cycle_timer64.h"
#define ticks64 soc_ticks64
// 服务函数 set64。
// 接口参数：uint8_t *p,uint64_t value；返回值及副作用由下列函数体定义。
// 参数入口：p, value；类型、指针限定及返回约定沿用下列声明。
static void set64(uint8_t *p,uint64_t value) {
    set32(p,(uint32_t)value);set32(p+4,(uint32_t)(value>>32));
}
// 服务函数 displayready_run。
// 接口参数：uint32_t configuration；返回值及副作用由下列函数体定义。
// 参数入口：configuration；类型、指针限定及返回约定沿用下列声明。
static uint32_t displayready_run(uint32_t configuration) {
    uint32_t c[WORKFLOW_WORDS],phase=0,result=OK,detected=0,chosen=0;
    uint32_t xy[2]={0,0},score=0,klass=0,display_state=0;
    uint64_t t[7]={0,0,0,0,0,0,0};
    if(data_len)return BAD_LENGTH;
    if((configuration&3u) || !range(configuration,sizeof(c)))return BAD_RANGE;
    for(uint32_t i=0;i<WORKFLOW_WORDS;i++)c[i]=R32(configuration+i*4u);
    /* Fixed memory plan: low model input, separate 5MP replay and display pool.
     * Descriptors, outputs, scratch and immutable asset safety also remain
     * checked by the original graph/detection functions. */
    if(c[0]!=WORKFLOW_ID||c[1]!=1u||c[2]!=0x81000000u||c[3]!=0x80100000u||
       (c[4]!=0x82000000u && c[4]!=0x82100000u)||
       !range(c[2],SOC_V2_SOURCE_BYTES)||!range(c[3],SOC_V2_OUTPUT_BYTES)||
       !range(c[4],SOC_DISPLAY_BYTES)||(c[6]&3u)||(c[7]&3u)||
       !range(c[6],GRAPH_MAX_OPS*GRAPH_WORDS_PER_OP*4u)||
       !range(c[7],GRAPH_MAX_OPS*GRAPH_TRACE_WORDS*4u)||
       c[13]!=6u||c[18]>=c[13]||!c[16]||c[16]>1024u||!c[17]||c[17]>64u||c[17]>c[16]||
       c[6]>=0x81000000u-GRAPH_MAX_OPS*GRAPH_WORDS_PER_OP*4u||
       c[7]>=0x81000000u-GRAPH_MAX_OPS*GRAPH_TRACE_WORDS*4u||
       !range(c[8],c[9])||c[8]+c[9]>0x81000000u||
       !range(c[10],96u)||c[10]>0x81000000u-96u||
       !range(c[11],c[17]*sizeof(soc_detection))||
       c[11]>0x81000000u-c[17]*sizeof(soc_detection)||
       !range(c[12],c[16]*sizeof(soc_detection))||
       c[12]>0x81000000u-c[16]*sizeof(soc_detection)||
       c[19]!=(GRAPH_FAST_FLAG|GRAPH_S3_FLAG|GRAPH_S3_FUSE_LUT_FLAG|GRAPH_PROFILE_FLAG)||
       c[20]||c[21]||c[22]||c[23]||
       // 硬件/可见性边界：R32(c[6])!=10u||R32(c[6]+4u)!=c[3])return BAD_RANGE;。
       // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
       R32(c[6])!=10u||R32(c[6]+4u)!=c[3])return BAD_RANGE;
    if(camera_writing())return CAMERA_NOT_READY;
    if(R32(DISPLAY_MMIO)!=DISPLAY_ID)return BAD_COMMAND;
    if(R32(0x60000008u)!=HZ)return DISPLAY_BAD_STATE;
    if(R32(DISPLAY_MMIO+4u)&2u) {
        if(R32(DISPLAY_MMIO+0x2cu)!=0u)return DISPLAY_BAD_STATE;
        // 硬件/可见性边界：R32(DISPLAY_MMIO)=8u;fence_all();。
        // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
        R32(DISPLAY_MMIO)=8u;fence_all();
    }
    if(R32(DISPLAY_MMIO+0x30u)==c[4] && (R32(DISPLAY_MMIO+4u)&16u))return DISPLAY_BAD_STATE;
    profile_session=1u;t[0]=ticks64();phase=1;
    result=soc_preprocess5mp_rgb565_v2((const volatile uint8_t *)(uintptr_t)c[2],
        SOC_V2_SOURCE_BYTES,SOC_V2_SOURCE_ROW_BYTES,
        (volatile int8_t *)(uintptr_t)c[3],SOC_V2_OUTPUT_BYTES,soc_model_input_lut);
    // 硬件/可见性边界：fence_all();t[1]=ticks64();。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    fence_all();t[1]=ticks64();
    if(result!=SOC_V2_OK){result=V2_SOFTWARE_ERROR;goto finish;}
    if(profile_session)profile_counters[P_V2_PREPROCESS_TICKS]+=t[1]-t[0];
    phase=2;data_len=16u;
    set32(data,c[19]|GRAPH_MAX_OPS);set32(data+4,c[7]);
    set32(data+8,c[8]);set32(data+12,c[9]);
    result=graph_run(c[6]);t[2]=ticks64();if(result!=OK)goto finish;
    phase=3;data_len=40u;
    set32(data,3u);set32(data+4,c[13]);set32(data+8,320u);set32(data+12,320u);
    set32(data+16,c[14]);set32(data+20,c[15]);set32(data+24,c[16]);set32(data+28,c[17]);
    set32(data+32,c[11]);set32(data+36,c[12]);
    result=detect_run(c[10]);t[3]=ticks64();if(result!=OK)goto finish;
    detected=get32(data+8);
    for(uint32_t i=0;i<detected;i++) {
        const volatile soc_detection *d=(const volatile soc_detection *)(uintptr_t)(c[11]+i*sizeof(soc_detection));
        uint32_t q[4]={d->x1_q16,d->y1_q16,d->x2_q16,d->y2_q16},candidate_xy[2];
        if(d->class_id!=c[18] || (chosen && d->score_q15<=score))continue;
        soc_display_map_box(q,candidate_xy);
        if((candidate_xy[0]&65535u)>=(candidate_xy[1]&65535u)||
           (candidate_xy[0]>>16)>=(candidate_xy[1]>>16))continue;
        xy[0]=candidate_xy[0];xy[1]=candidate_xy[1];score=d->score_q15;klass=d->class_id;chosen=1u;
    }
    // 硬件/可见性边界：phase=4;R32(DISPLAY_MMIO+8u)=c[4];R32(DISPLAY_MMIO+12u)=c[5];。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    phase=4;R32(DISPLAY_MMIO+8u)=c[4];R32(DISPLAY_MMIO+12u)=c[5];
    // 硬件/可见性边界：fence_all();R32(DISPLAY_MMIO)=1u;fence_all();。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    fence_all();R32(DISPLAY_MMIO)=1u;fence_all();
    // 硬件/可见性边界：display_state=R32(DISPLAY_MMIO+4u);。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    display_state=R32(DISPLAY_MMIO+4u);
    if(!(display_state&2u)||(display_state&0x00ff0000u)){result=DISPLAY_BAD_STATE;goto finish;}
    soc_display_resize5mp((const volatile uint8_t *)(uintptr_t)c[2],
                           (volatile uint16_t *)(uintptr_t)c[4]);
    // 硬件/可见性边界：fence_all();t[4]=ticks64();。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    fence_all();t[4]=ticks64();
    profile_counters[P_DISPLAY_RESIZE_TICKS]+=t[4]-t[3];
    // 硬件/可见性边界：R32(DISPLAY_MMIO+16u)=xy[0];R32(DISPLAY_MMIO+20u)=xy[1];。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    R32(DISPLAY_MMIO+16u)=xy[0];R32(DISPLAY_MMIO+20u)=xy[1];
    // 硬件/可见性边界：R32(DISPLAY_MMIO+24u)=score;R32(DISPLAY_MMIO+28u)=klass;。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    R32(DISPLAY_MMIO+24u)=score;R32(DISPLAY_MMIO+28u)=klass;
    // 硬件/可见性边界：R32(DISPLAY_MMIO+32u)=chosen;。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    R32(DISPLAY_MMIO+32u)=chosen;
    /* This token is issued only after successful real decode/NMS. */
    R32(DISPLAY_MMIO)=2u;fence_all();phase=5;
    for(;;) {
        // 硬件/可见性边界：display_state=R32(DISPLAY_MMIO+4u);。
        // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
        display_state=R32(DISPLAY_MMIO+4u);
        if(display_state&0x00ff0000u){result=DISPLAY_WRITE_ERROR;goto finish;}
        if(R32(DISPLAY_MMIO+0x28u)==SOC_DISPLAY_BYTES && R32(DISPLAY_MMIO+0x2cu)==0u)break;
        if(ticks64()-t[4]>(uint64_t)HZ*5u){result=DISPLAY_WRITE_TIMEOUT;goto finish;}
    }
    // 硬件/可见性边界：t[5]=ticks64();R32(DISPLAY_MMIO)=4u;fence_all();。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    t[5]=ticks64();R32(DISPLAY_MMIO)=4u;fence_all();
    // 硬件/可见性边界：display_state=R32(DISPLAY_MMIO+4u);t[6]=ticks64();。
    // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
    display_state=R32(DISPLAY_MMIO+4u);t[6]=ticks64();
    if(!(display_state&4u)||(display_state&0x00ff0000u)||
       // 硬件/可见性边界：R32(DISPLAY_MMIO+0x30u)!=c[4]||R32(DISPLAY_MMIO+0x34u)!=c[5]||。
       // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
       R32(DISPLAY_MMIO+0x30u)!=c[4]||R32(DISPLAY_MMIO+0x34u)!=c[5]||
       // 硬件/可见性边界：R32(DISPLAY_MMIO+0x48u)!=chosen){result=DISPLAY_BAD_STATE;goto finish;}。
       // 本步骤的顺序影响描述符、DMA 或寄存器访问；不能当作普通缓存变量访问重排。
       R32(DISPLAY_MMIO+0x48u)!=chosen){result=DISPLAY_BAD_STATE;goto finish;}
    phase=6;profile_counters[P_DDR_FRAME_TO_DISPLAY_READY_TICKS]+=t[6]-t[0];
finish:
    if(result!=OK)t[6]=ticks64();
    set32(data,WORKFLOW_ID);set32(data+4,1u);set32(data+8,phase);set32(data+12,result);
    set32(data+16,c[5]);set32(data+20,c[4]);set32(data+24,detected);set32(data+28,chosen);
    set32(data+32,xy[0]);set32(data+36,xy[1]);set32(data+40,score);set32(data+44,klass);
    // 硬件/可见性边界：set32(data+48,display_state);set32(data+52,R32(0x60000008u));。
    set32(data+48,display_state);set32(data+52,R32(0x60000008u));
    for(uint32_t i=0;i<7u;i++)set64(data+56u+i*8u,t[i]);
    set32(data+112,R32(DISPLAY_MMIO+0x24u));set32(data+116,R32(DISPLAY_MMIO+0x28u));
    set32(data+120,R32(DISPLAY_MMIO+0x4cu));set32(data+124,1u); // software V2/resize
    return result;
}
