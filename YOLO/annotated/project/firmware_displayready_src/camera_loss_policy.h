/* User-requested 10% per-frame pixel-loss stop threshold.
 * Sensor count includes pixels seen before FIFO loss. Writer count proves
 * pixels committed to DDR. Do not double-count sensor and writer deficits.
 * Call only for a fully retired capture, never a still-active DMA.
 */
// 架构导读：camera_loss_policy。
#ifndef SOC_CAMERA_LOSS_POLICY_H
#define SOC_CAMERA_LOSS_POLICY_H
#include <stdint.h>
#define CAMERA_EXPECTED_PIXELS (1280u * 720u)
#define CAMERA_LOSS_ABORT_PIXELS (CAMERA_EXPECTED_PIXELS / 10u)
static inline uint32_t camera_lost_pixels(uint32_t written,uint32_t sensor) {
    uint32_t a=written<CAMERA_EXPECTED_PIXELS?CAMERA_EXPECTED_PIXELS-written:0u;
    uint32_t b=sensor<CAMERA_EXPECTED_PIXELS?CAMERA_EXPECTED_PIXELS-sensor:0u;
    return a>b?a:b;
}
static inline uint32_t camera_loss_abort(uint32_t written,uint32_t sensor) {
    return camera_lost_pixels(written,sensor)>=CAMERA_LOSS_ABORT_PIXELS;
}
#endif
