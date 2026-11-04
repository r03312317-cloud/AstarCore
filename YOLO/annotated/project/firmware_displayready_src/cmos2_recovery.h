// 架构导读：cmos2_recovery。
// 裸机控制固件组件，提供本文件定义的状态检查、数据结构和服务函数。
#ifndef SOC_CMOS2_RECOVERY_H
#define SOC_CMOS2_RECOVERY_H
#include <stdint.h>
/* Only a completed, rejected camera frame can be skipped. A DMA timeout,
 * busy writer, unavailable DDR or busy NPU must stop the loop. */
static inline int soc_cmos2_capture_can_resume(uint32_t result,uint32_t phase,
        uint32_t camera_status,uint32_t ddr_status,uint32_t npu_status) {
    return result==13u && phase==1u &&
           (camera_status&7u)==5u && (camera_status&0x50u)==0x50u &&
           (ddr_status&15u)==3u && (npu_status&3u)==1u;
}
#endif
