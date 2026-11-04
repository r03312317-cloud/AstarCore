#ifndef SOC_CONCAT_HARDWARE_H
#define SOC_CONCAT_HARDWARE_H
/* Included after monitor helpers, before tensor_run. Only Concat is offloaded.
 * Unaligned bases/channels use the retained software with a counted reason.
 * Accepted hardware errors/timeouts never fall back over uncertain output. */
#define CONCAT_MMIO 0x60001400u
#define CONCAT_ID 0x31544143u
static uint32_t concat_jobs,concat_sw_layers,concat_fallbacks;
static uint32_t concat_failures,concat_last_error,concat_timeout_latched;
static uint32_t concat_unaligned_fallbacks;
static uint64_t concat_wait_total,concat_read_total,concat_write_total;
static uint64_t concat_active_total,concat_stall_total;
static int concat_fast_supported(uint32_t input,uint32_t aux,uint32_t output,
                                 const soc_tensor_shape *s) {
    return s->kind==SOC_TOP_CONCAT && s->input_c<=65535u &&
           s->aux_c<=65535u && !((input|aux|output|s->input_c|s->aux_c)&15u);
}
static uint32_t concat_hardware_impl(uint32_t input,uint32_t aux,uint32_t output,
        const soc_tensor_shape *s,const soc_tensor_layout *l) {
    if(!concat_fast_supported(input,aux,output,s))return TENSOR_BAD_SHAPE;
    if(concat_timeout_latched || R32(CONCAT_MMIO+0x34u)!=CONCAT_ID)
        return CONCAT_HARDWARE_ERROR;
    uint32_t begin=ticks(),state;
    while(1) {
        live_preview_service();
        state=R32(CONCAT_MMIO+0x1cu);
        if(state&(1u<<16))return CONCAT_HARDWARE_ERROR;
        if(!(state&(1u<<15)))return DDR_UNAVAILABLE;
        if(state&(1u<<17))break;
        if((uint32_t)(ticks()-begin)>HZ*2u)return CONCAT_HARDWARE_TIMEOUT;
    }
    R32(CONCAT_MMIO+0x38u)=0u; /* Shared backend: restore Concat mode after Tensor. */
    R32(CONCAT_MMIO+0x04u)=input;R32(CONCAT_MMIO+0x08u)=aux;
    R32(CONCAT_MMIO+0x0cu)=output;
    R32(CONCAT_MMIO+0x10u)=s->input_h*s->input_w;
    R32(CONCAT_MMIO+0x14u)=(s->aux_c<<16)|s->input_c;
    R32(CONCAT_MMIO+0x18u)=0u; /* This firmware uses bounded polling. */
    fence_all();R32(CONCAT_MMIO)=1u;
    uint32_t poll_begin=ticks();
    while(!(R32(CONCAT_MMIO+0x1cu)&2u)) {
        live_preview_service();
        if((uint32_t)(ticks()-begin)>HZ*2u)return CONCAT_HARDWARE_TIMEOUT;
    }
    uint32_t waited=ticks()-poll_begin;
    fence_all();state=R32(CONCAT_MMIO+0x1cu);
    uint32_t read=R32(CONCAT_MMIO+0x20u),written=R32(CONCAT_MMIO+0x24u);
    uint32_t active=R32(CONCAT_MMIO+0x28u),stalled=R32(CONCAT_MMIO+0x2cu);
    concat_wait_total+=waited;concat_read_total+=read;concat_write_total+=written;
    concat_active_total+=active;concat_stall_total+=stalled;
    if(graph_profile_active)profile_counters[P_CPU_POLL_TICKS]+=waited;
    if((state&0x7fe0u) || (state&(1u<<16)) ||
       read!=l->input_bytes+l->aux_bytes || written!=l->output_bytes)
        return CONCAT_HARDWARE_ERROR;
    concat_jobs++;
    return OK;
}
static uint32_t concat_hardware_run(uint32_t input,uint32_t aux,uint32_t output,
        const soc_tensor_shape *s,const soc_tensor_layout *l) {
    uint32_t status=concat_hardware_impl(input,aux,output,s,l);
    if(status!=OK) {
        concat_failures++;concat_last_error=status;
        if(status==CONCAT_HARDWARE_TIMEOUT)concat_timeout_latched=1u;
    }
    return status;
}
#endif
