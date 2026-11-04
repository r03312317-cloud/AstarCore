// 架构导读：conv_service_batch_contract。
#ifndef SOC_CONV_SERVICE_BATCH_CONTRACT_H
#define SOC_CONV_SERVICE_BATCH_CONTRACT_H
#include <stdint.h>
/* GEX1 callers pass 16 without reading its undefined capability register.
 * Direct 1x1 HWC jobs have no Window allocation: zero scratch is legal.
 * Unknown capabilities and insufficient actual Window buffers fail closed. */
static inline uint32_t conv_service_effective_window_rows(uint32_t cap,
        uint32_t k,uint32_t scratch_stride,int needs_window) {
    if((cap!=16u&&cap!=64u)||k==0u||k>1152u)return 0u;
    if(!needs_window)return 16u;
    if(scratch_stride<k*16u)return 0u;
    return cap==64u&&scratch_stride>=k*64u?64u:16u;
}
#endif
