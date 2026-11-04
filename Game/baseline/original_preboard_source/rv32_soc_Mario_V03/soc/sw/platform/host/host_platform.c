/* -------------------------------------------------------------------------
 * host_platform.c -- PC build of the game HAL.
 *
 * The framebuffers live in normal host memory, the raster is virtual (one
 * hal_wait_active() call = one 60 Hz frame) and the buttons come from the
 * scripted player in host_main.c.  The game code below the HAL is byte for
 * byte the code that runs on the FPGA, which is what makes this a meaningful
 * functional test rather than a reimplementation.
 * ------------------------------------------------------------------------- */
#include "game_regs.h"
#include "game_hal.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static uint16_t fb0_mem[FB_WIDTH * FB_HEIGHT];
static uint16_t fb1_mem[FB_WIDTH * FB_HEIGHT];

static uint16_t *active_fb_ptr = fb0_mem;
static uint16_t *pending_fb_ptr = fb0_mem;
static uint32_t now_ms_q;
static uint32_t frame_q;
static uint8_t  button_level;
static uint8_t  button_events;
static int      host_present_error;

void hal_init(void)
{
    memset(fb0_mem, 0, sizeof(fb0_mem));
    memset(fb1_mem, 0, sizeof(fb1_mem));
    active_fb_ptr = fb0_mem;
    pending_fb_ptr = fb0_mem;
    now_ms_q = 0;
    frame_q = 0;
    button_level = 0;
    button_events = 0;
}

uint16_t *hal_fb(int index) { return (index & 1) ? fb1_mem : fb0_mem; }

uint32_t hal_now_ms(void) { return now_ms_q; }
uint32_t hal_frames(void) { return frame_q; }
uint32_t hal_vsync_count(void) { return frame_q; }
uint32_t hal_video_status(void) { return 0x0fu; }   /* ready | ddr_ready */

uint8_t hal_buttons(void) { return button_level; }
uint8_t hal_buttons_pressed(void)
{
    uint8_t ev = button_events;
    button_events = 0;
    return ev;
}

/* The harness sets the level directly and derives the edge events. */
void host_set_buttons(uint8_t level)
{
    uint8_t press = (uint8_t)(level & ~button_level);
    button_level = level;
    button_events |= press;
}

int hal_present(uint16_t *fb)
{
    pending_fb_ptr = fb;
    return host_present_error;
}

uint16_t *hal_active_fb(void) { return active_fb_ptr; }

void hal_host_tick(void)
{
    /* one 60 Hz frame */
    now_ms_q += 16;
    frame_q++;
    active_fb_ptr = pending_fb_ptr;
}

int hal_wait_active(uint16_t *fb)
{
    for (int i = 0; i < 8; i++) {
        hal_host_tick();
        if (active_fb_ptr == fb) return 0;
    }
    return 1;
}

void hal_log(const char *text)
{
    fputs(text, stdout);
    fflush(stdout);
}

void hal_log_hex(uint32_t value) { printf("0x%08x", value); }

int hal_is_host(void) { return 1; }

static void rgb565_to_rgb888(uint16_t p, unsigned char *out)
{
    unsigned r = (p >> 11) & 0x1f, g = (p >> 5) & 0x3f, b = p & 0x1f;
    out[0] = (unsigned char)((r << 3) | (r >> 2));
    out[1] = (unsigned char)((g << 2) | (g >> 4));
    out[2] = (unsigned char)((b << 3) | (b >> 2));
}

int hal_host_dump(const char *path)
{
    FILE *f = fopen(path, "wb");
    if (!f) return -1;
    fprintf(f, "P6\n%d %d\n255\n", FB_WIDTH, FB_HEIGHT);
    unsigned char row[FB_WIDTH * 3];
    for (int y = 0; y < FB_HEIGHT; y++) {
        for (int x = 0; x < FB_WIDTH; x++)
            rgb565_to_rgb888(active_fb_ptr[y * FB_WIDTH + x], &row[x * 3]);
        fwrite(row, 1, sizeof(row), f);
    }
    fclose(f);
    return 0;
}
