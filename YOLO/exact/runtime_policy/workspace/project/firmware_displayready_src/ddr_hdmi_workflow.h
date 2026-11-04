/* Included after the original Graph204 and real decode/NMS. */
#define DISPLAY_MMIO 0x60001500u
#define VIDEO_MMIO 0x60001600u
#define DISPLAY_ID 0x31505344u
#define VIDEO_ID 0x32544956u
#define WORKFLOW_ID 0x31524456u
#define WORKFLOW_WORDS 40u
#include "cycle_timer64.h"
#define ticks64 soc_ticks64
static void set64(uint8_t *p,uint64_t value) {
    set32(p,(uint32_t)value);set32(p+4,(uint32_t)(value>>32));
}
#include "v2_hardware.h"
static uint64_t fixed_snapshot(uint32_t address) {
    uint32_t low=R32(address),high=R32(address+4u);
    return ((uint64_t)high<<32)|low;
}
static uint32_t build_word(uint32_t first) {
    uint32_t value=0;
    for(uint32_t i=0;i<8u;i++) {
        uint8_t h=(uint8_t)BOARD_BUILD_ID[first+i];
        value=(value<<4)|(h>='a'?(uint32_t)(h-'a'+10u):(uint32_t)(h-'0'));
    }
    return value;
}
static uint32_t displayready_run(uint32_t configuration) {
    uint32_t c[WORKFLOW_WORDS],phase=0,result=OK,detected=0,chosen=0;
    uint32_t xy[2]={0,0},score=0,klass=0,display_state=0,video_state=0;
    uint32_t ready_ok=0,hdmi_ok=0;
    uint64_t t[11]={0}; // T0,TP0,TP1,TG0,TG1,TB,TF,TR,TC,TH,TE
    static const uint32_t model_words[8]={0x18fd72fbu,0x092deebdu,0x240531a5u,0x23e272adu,
        0xfb273633u,0x55c7c15au,0x4a0702d2u,0xf5b07c90u};
    if(data_len)return BAD_LENGTH;
    if((configuration&3u)||!range(configuration,sizeof(c)))return BAD_RANGE;
    for(uint32_t i=0;i<WORKFLOW_WORDS;i++)c[i]=R32(configuration+i*4u);
    if(c[0]!=WORKFLOW_ID||c[1]!=2u||c[2]!=0x81000000u||c[3]!=0x80100000u||
       (c[4]!=0x82000000u&&c[4]!=0x82100000u)||
       !range(c[2],SOC_V2_SOURCE_BYTES)||!range(c[3],SOC_V2_OUTPUT_BYTES)||
       !range(c[4],SOC_DISPLAY_BYTES)||(c[6]&3u)||(c[7]&3u)||
       !range(c[6],GRAPH_MAX_OPS*GRAPH_WORDS_PER_OP*4u)||
       !range(c[7],GRAPH_MAX_OPS*GRAPH_TRACE_WORDS*4u)||
       c[13]!=6u||c[18]>=c[13]||!c[16]||c[16]>1024u||!c[17]||c[17]>64u||c[17]>c[16]||
       c[6]>=0x81000000u-GRAPH_MAX_OPS*GRAPH_WORDS_PER_OP*4u||
       c[7]>=0x81000000u-GRAPH_MAX_OPS*GRAPH_TRACE_WORDS*4u||
       !range(c[8],c[9])||c[8]+c[9]>0x81000000u||
       !range(c[10],96u)||c[10]>0x81000000u-96u||
       !range(c[11],c[17]*sizeof(soc_detection))||c[11]>0x81000000u-c[17]*sizeof(soc_detection)||
       !range(c[12],c[16]*sizeof(soc_detection))||c[12]>0x81000000u-c[16]*sizeof(soc_detection)||
       c[19]!=(GRAPH_FAST_FLAG|GRAPH_S3_FLAG|GRAPH_S3_FUSE_LUT_FLAG|GRAPH_PROFILE_FLAG)||
       !c[20]||c[21]>1u||c[30]!=build_word(0u)||c[31]!=build_word(8u)||
       c[32]!=5184u||c[33]!=0x35363552u||c[34]!=2592u||c[35]!=1944u||
       c[36]!=1280u||c[37]!=640u||c[38]!=480u||c[39]||
       R32(c[6])!=10u||R32(c[6]+4u)!=c[3])return BAD_RANGE;
    for(uint32_t i=0;i<8u;i++)if(c[22u+i]!=model_words[i])return BAD_RANGE;
    if(camera_writing())return CAMERA_NOT_READY;
    if(R32(DISPLAY_MMIO)!=DISPLAY_ID||R32(VIDEO_MMIO)!=VIDEO_ID)return BAD_COMMAND;
    // Scoped framebuffer proof tracks IMG only. The old 5MP path writes the
    // framebuffer from CPU, so reject BEFORE it can publish an untracked FB.
    if(R32(DISPLAY_MMIO+4u)&0x80000000u)return DISPLAY_BAD_STATE;
    if(R32(0x60000008u)!=HZ)return DISPLAY_BAD_STATE;
    if(R32(DISPLAY_MMIO+4u)&2u) {
        if(R32(DISPLAY_MMIO+0x2cu)!=0u)return DISPLAY_BAD_STATE;
        R32(DISPLAY_MMIO)=8u;fence_all();
    }
    if(R32(DISPLAY_MMIO+0x30u)==c[4]&&(R32(DISPLAY_MMIO+4u)&16u))return DISPLAY_BAD_STATE;
    // Arm one-shot hardware event snapshots before accepting this START.
    R32(VIDEO_MMIO)=0u;R32(VIDEO_MMIO+8u)=c[20];R32(VIDEO_MMIO+12u)=c[5];R32(VIDEO_MMIO)=1u;
    fence_all();profile_session=1u;t[0]=ticks64();phase=1;t[1]=ticks64();
    if(c[21]==0u) {
        v2_hw_tp0=0;v2_hw_tp1=0;result=v2_hardware_run(c[2],c[3]);
        t[1]=v2_hw_tp0;t[2]=v2_hw_tp1;
    }
    else {
        result=soc_preprocess5mp_rgb565_v2((const volatile uint8_t *)(uintptr_t)c[2],
            SOC_V2_SOURCE_BYTES,SOC_V2_SOURCE_ROW_BYTES,
            (volatile int8_t *)(uintptr_t)c[3],SOC_V2_OUTPUT_BYTES,soc_model_input_lut);
        if(result!=SOC_V2_OK)result=V2_SOFTWARE_ERROR;
    }
    fence_all();if(c[21])t[2]=ticks64();if(result!=OK)goto finish;
    profile_counters[P_V2_PREPROCESS_TICKS]+=t[2]-t[1];
    phase=2;data_len=16u;
    set32(data,c[19]|GRAPH_MAX_OPS);set32(data+4,c[7]);set32(data+8,c[8]);set32(data+12,c[9]);
    t[3]=ticks64();result=graph_run(c[6]);t[4]=ticks64();if(result!=OK)goto finish;
    phase=3;data_len=40u;
    set32(data,3u);set32(data+4,c[13]);set32(data+8,320u);set32(data+12,320u);
    set32(data+16,c[14]);set32(data+20,c[15]);set32(data+24,c[16]);set32(data+28,c[17]);
    set32(data+32,c[11]);set32(data+36,c[12]);result=detect_run(c[10]);
    if(result!=OK)goto finish;
    detected=get32(data+8);
    for(uint32_t i=0;i<detected;i++) {
        const volatile soc_detection *d=(const volatile soc_detection *)(uintptr_t)(c[11]+i*sizeof(soc_detection));
        uint32_t q[4]={d->x1_q16,d->y1_q16,d->x2_q16,d->y2_q16},candidate_xy[2];
        if(d->class_id!=c[18]||(chosen&&d->score_q15<=score))continue;
        soc_display_map_box(q,candidate_xy);
        if((candidate_xy[0]&65535u)>=(candidate_xy[1]&65535u)||(candidate_xy[0]>>16)>=(candidate_xy[1]>>16))continue;
        xy[0]=candidate_xy[0];xy[1]=candidate_xy[1];score=d->score_q15;klass=d->class_id;chosen=1u;
    }
    t[5]=ticks64();phase=4;
    R32(DISPLAY_MMIO+8u)=c[4];R32(DISPLAY_MMIO+12u)=c[5];R32(DISPLAY_MMIO+0x54u)=c[20];
    fence_all();R32(DISPLAY_MMIO)=1u;fence_all();display_state=R32(DISPLAY_MMIO+4u);
    if(!(display_state&2u)||(display_state&0x00ff0000u)){result=DISPLAY_BAD_STATE;goto finish;}
    soc_display_resize5mp((const volatile uint8_t *)(uintptr_t)c[2],(volatile uint16_t *)(uintptr_t)c[4]);
    fence_all();profile_counters[P_DISPLAY_RESIZE_TICKS]+=ticks64()-t[5];
    R32(DISPLAY_MMIO+16u)=xy[0];R32(DISPLAY_MMIO+20u)=xy[1];
    R32(DISPLAY_MMIO+24u)=score;R32(DISPLAY_MMIO+28u)=klass;R32(DISPLAY_MMIO+32u)=chosen;
    R32(DISPLAY_MMIO)=2u;fence_all();phase=5;
    uint64_t wait_start=ticks64();
    for(;;) {
        display_state=R32(DISPLAY_MMIO+4u);
        if(display_state&0x00ff0000u){result=DISPLAY_WRITE_ERROR;goto finish;}
        if(R32(DISPLAY_MMIO+0x28u)==SOC_DISPLAY_BYTES&&R32(DISPLAY_MMIO+0x2cu)==0u)break;
        if(ticks64()-wait_start>(uint64_t)HZ*5u){result=DISPLAY_WRITE_TIMEOUT;goto finish;}
    }
    t[6]=fixed_snapshot(DISPLAY_MMIO+0x60u);R32(DISPLAY_MMIO)=4u;fence_all();
    display_state=R32(DISPLAY_MMIO+4u);t[7]=fixed_snapshot(DISPLAY_MMIO+0x68u);
    if(!(display_state&4u)||(display_state&0x00ff0000u)||R32(DISPLAY_MMIO+0x30u)!=c[4]||
       R32(DISPLAY_MMIO+0x34u)!=c[5]||R32(DISPLAY_MMIO+0x58u)!=c[20]||
       R32(DISPLAY_MMIO+0x48u)!=chosen){result=DISPLAY_BAD_STATE;goto finish;}
    ready_ok=1u;phase=6;
    profile_counters[P_DDR_FRAME_TO_DISPLAY_READY_TICKS]+=t[7]-t[0];
    // Digital frame completion is a distinct endpoint from READY. First-ever
    // publication switches the standby bars to DDR at a safe frame boundary.
    R32(VIDEO_MMIO+0x10u)=2u;fence_all();wait_start=ticks64();phase=7;
    for(;;) {
        video_state=R32(VIDEO_MMIO+4u);
        if(video_state&8u)break;
        if(ticks64()-wait_start>(uint64_t)HZ*2u){result=HDMI_FRAME_TIMEOUT;goto finish;}
    }
    t[8]=fixed_snapshot(VIDEO_MMIO+0x30u);t[9]=fixed_snapshot(VIDEO_MMIO+0x38u);
    t[10]=fixed_snapshot(VIDEO_MMIO+0x40u);
    if((video_state&0x1eu)!=0x1eu||R32(VIDEO_MMIO+0x18u)!=0u||R32(VIDEO_MMIO+0x2cu)!=0u)
        {result=HDMI_FRAME_ERROR;goto finish;}
    hdmi_ok=1u;phase=8;
finish:
    for(uint32_t i=0;i<256u;i++)data[i]=0;
    set32(data,WORKFLOW_ID);set32(data+4,2u);set32(data+8,phase);set32(data+12,result);
    set32(data+16,c[5]);set32(data+20,c[4]);set32(data+24,detected);set32(data+28,chosen);
    set32(data+32,xy[0]);set32(data+36,xy[1]);set32(data+40,score);set32(data+44,klass);
    set32(data+48,display_state);set32(data+52,R32(0x60000008u));set32(data+56,c[20]);set32(data+60,c[21]);
    set32(data+64,video_state);set32(data+68,R32(VIDEO_MMIO+0x2cu));
    set32(data+72,R32(VIDEO_MMIO+0x48u));set32(data+76,R32(VIDEO_MMIO+0x14u));
    set32(data+80,R32(VIDEO_MMIO+0x18u));set32(data+84,R32(VIDEO_MMIO+0x1cu));
    set32(data+88,R32(VIDEO_MMIO+0x20u));set32(data+92,R32(VIDEO_MMIO+0x4cu));
    for(uint32_t i=0;i<11u;i++)set64(data+96u+i*8u,t[i]);
    set32(data+184,R32(DISPLAY_MMIO+0x24u));set32(data+188,R32(DISPLAY_MMIO+0x28u));
    set32(data+192,R32(DISPLAY_MMIO+0x4cu));set32(data+196,R32(VIDEO_MMIO+0x24u));
    set32(data+200,R32(VIDEO_MMIO+0x28u));set32(data+204,R32(S2_MMIO+0x10u));
    set32(data+208,R32(S2_MMIO+0x1cu));set32(data+212,R32(S2_MMIO+0x0cu));
    set32(data+216,c[19]);set32(data+220,GRAPH_MAX_OPS);
    set32(data+224,ready_ok|(hdmi_ok<<1)|4u|(c[21]==0u?8u:0u));
    return result;
}
