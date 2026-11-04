// [ARCH] 继承的 HAL 服务于原游戏与探针，Mario 有独立适配层。
// [ARCH] 未调用功能不列为 Mario 实板已验证。
/* -------------------------------------------------------------------------
 * game_hal.h -- the only interface between the game code and a platform.
 *
 * Two implementations exist:
 *   platform/soc/soc_platform.c   real board (MMIO, DDR framebuffer, HDMI)
 *   platform/host/host_platform.c PC simulation (memory framebuffer, PNG dump)
 *
 * Keeping the game code free of MMIO addresses is what makes the host build a
 * faithful test of the same sources that run on the FPGA.
 * ------------------------------------------------------------------------- */
#ifndef GAME_HAL_H
#define GAME_HAL_H

#include <stdint.h>

typedef struct {
    uint32_t  width;
    uint32_t  height;
    uint16_t *fb[2];         /* the two DDR frame buffers                   */
    uint32_t  fb_bytes;
} hal_video_t;

void     hal_init(void);
uint16_t *hal_fb(int index);          /* 0 or 1: DDR frame buffer base         */
uint32_t hal_now_ms(void);
uint32_t hal_frames(void);            /* vertical blanks since reset          */
uint8_t  hal_buttons(void);           /* debounced level, BTN_* bits          */
uint8_t  hal_buttons_pressed(void);   /* one-shot press events (W1C)          */
void     hal_log(const char *text);
void     hal_log_hex(uint32_t value);

/* Present a buffer.  Returns 0 on success; the flip takes effect at the next
 * vertical blank.  hal_active_fb() reports what the raster reads right now. */
int      hal_present(uint16_t *fb);
uint16_t *hal_active_fb(void);
uint32_t hal_vsync_count(void);

/* Raw video status word (GVID_STATUS): [3] ddr_ready is the only way to tell a
 * failed DDR calibration from a hung CPU during board bring-up. */
uint32_t hal_video_status(void);

/* Wait until the raster scans `fb`.  Returns 0 on success, 1 on timeout. */
int      hal_wait_active(uint16_t *fb);

/* Host only: advance the virtual raster and optionally dump the active frame.
 * hal_wait_active() drives this automatically on the host build. */
void     hal_host_tick(void);
int      hal_host_dump(const char *path);
int      hal_is_host(void);

#endif /* GAME_HAL_H */
