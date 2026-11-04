#ifndef SOC_SHARED_TENSOR_HARDWARE_H
#define SOC_SHARED_TENSOR_HARDWARE_H
/* Static model uses exact signedINT8 Pool/Add/Upsample in the one existing
 * Concat native DMA backend. Accepted failures never switch to CPU software. */
static uint32_t shared_tensor_jobs,shared_tensor_failures;
static uint32_t shared_tensor_hardware_run(uint32_t input,uint32_t aux,uint32_t output,
        const soc_tensor_shape *s,const soc_tensor_layout *l) {
    uint32_t mode;
    if((input|aux|output|s->input_c)&15u)return TENSOR_BAD_SHAPE;
    if(s->kind==SOC_TOP_ADD)mode=1u;
    else if(s->kind==SOC_TOP_UPSAMPLE && s->stride_h==2u && s->stride_w==2u &&
            ((s->input_h==10u && s->input_w==10u && s->input_c==128u) ||
             (s->input_h==20u && s->input_w==20u && s->input_c==64u)))mode=2u;
    else if(s->kind==SOC_TOP_POOL && s->input_h==10u && s->input_w==10u &&
            s->input_c==128u && s->kernel_h==5u && s->kernel_w==5u &&
            s->stride_h==1u && s->stride_w==1u && s->pad_top==2u &&
            s->pad_left==2u && s->pad_bottom==2u && s->pad_right==2u)mode=3u;
    else return TENSOR_BAD_SHAPE;
    if(concat_timeout_latched || R32(CONCAT_MMIO+0x40u)!=0x31534e54u)
        return CONCAT_HARDWARE_ERROR;
    uint32_t begin=ticks(),state;
    while(1) {
        state=R32(CONCAT_MMIO+0x1cu);
        if(state&(1u<<16))return CONCAT_HARDWARE_ERROR;
        if(!(state&(1u<<15)))return DDR_UNAVAILABLE;
        if(state&(1u<<17))break;
        if((uint32_t)(ticks()-begin)>HZ*2u)return CONCAT_HARDWARE_TIMEOUT;
    }
    R32(CONCAT_MMIO+0x38u)=mode;
    R32(CONCAT_MMIO+0x3cu)=(s->input_h<<16)|s->input_w;
    R32(CONCAT_MMIO+0x04u)=input;R32(CONCAT_MMIO+0x08u)=aux;
    R32(CONCAT_MMIO+0x0cu)=output;R32(CONCAT_MMIO+0x10u)=s->input_h*s->input_w;
    R32(CONCAT_MMIO+0x14u)=(s->aux_c<<16)|s->input_c;
    R32(CONCAT_MMIO+0x18u)=0u;
    fence_all();R32(CONCAT_MMIO)=1u;
    uint32_t poll_begin=ticks();
    while(!(R32(CONCAT_MMIO+0x1cu)&2u)) {
        if((uint32_t)(ticks()-begin)>HZ*2u) {
            concat_timeout_latched=1u;shared_tensor_failures++;
            return CONCAT_HARDWARE_TIMEOUT;
        }
    }
    uint32_t waited=ticks()-poll_begin;
    fence_all();state=R32(CONCAT_MMIO+0x1cu);
    uint32_t read=R32(CONCAT_MMIO+0x20u),written=R32(CONCAT_MMIO+0x24u);
    if(graph_profile_active)profile_counters[P_CPU_POLL_TICKS]+=waited;
    if((state&0x7fe0u) || (state&(1u<<16)) ||
       read!=l->input_bytes+l->aux_bytes || written!=l->output_bytes) {
        shared_tensor_failures++;return CONCAT_HARDWARE_ERROR;
    }
    shared_tensor_jobs++;return OK;
}
#endif
