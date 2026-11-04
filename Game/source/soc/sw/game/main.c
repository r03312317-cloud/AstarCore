/* -------------------------------------------------------------------------
 * main.c -- rv32_soc_Game boot and frame loop (platform independent).
 *
 * The loop keeps both DDR buffers identical: every frame applies the dirty
 * rectangles to the buffer that is NOT being scanned and then publishes it.
 * The scan-out latches the new descriptor at the next vertical blank, so the
 * visible picture is always a complete, tear-free frame.
 * ------------------------------------------------------------------------- */
#include "game.h"
#include "game_hal.h"

static game_t g_game;

static void wait_ms(uint32_t ms)
{
    uint32_t t0 = hal_now_ms();
    while ((uint32_t)(hal_now_ms() - t0) < ms) { }
}

/* Hold A while powering up: report the button mask and the video status over
 * UART instead of starting the game.  With no working display this is the only
 * way to tell a mis-mapped button from a dead pin, and to see whether DDR
 * finished calibration (status bit 3) before blaming the firmware. */
static void diag_loop(void)
{
    uint8_t  last = 0xff;
    uint32_t next = hal_now_ms() + 500;

    hal_log("DIAG: press each button, watch the mask\n");
    for (;;) {
        uint8_t level = hal_buttons();
        if (level != last) {
            last = level;
            hal_log("btn=");
            hal_log_hex(level);
            hal_log("\n");
        }
        if ((int32_t)(hal_now_ms() - next) >= 0) {
            next = hal_now_ms() + 500;
            hal_log("st=");
            hal_log_hex(hal_video_status());
            hal_log(" vs=");
            hal_log_hex(hal_frames());
            hal_log(" fb=");
            hal_log_hex((uint32_t)(uintptr_t)hal_active_fb());
            hal_log("\n");
        }
    }
}

int main(void)
{
    game_t *g = &g_game;

    /* Print before touching any other peripheral.  hal_init() writes the game
     * video window, which crosses into the DDR clock domain through an MMIO
     * CDC; if that domain is not running the CPU waits there forever and a
     * banner placed after it would never appear. */
    hal_log("rv32_soc_Game boot\n");

    hal_init();
    /* status word: bit0 busy, bit1 published, bit2 commit error, bit3 ddr ready.
     * Printing it here separates "the video window accepted the write" from
     * "the DDR user clock never came up". */
    hal_log("init ok st=");
    hal_log_hex(hal_video_status());
    hal_log("\n");

    if (!hal_is_host()) {
        wait_ms(80);                    /* let the debouncer settle        */
        if (hal_buttons() & BTN_A) diag_loop();
    }

    game_init(g, hal_now_ms());

    uint16_t *b0 = hal_fb(0);
    uint16_t *b1 = hal_fb(1);

    /* first buffer: full picture, then show it */
    game_render_full(g, b0);
    if (hal_present(b0)) hal_log("present b0 retry\n");
    if (hal_wait_active(b0)) hal_log("active b0 timeout\n");

    /* second buffer: same picture, prepared while b0 is on screen */
    game_render_full(g, b1);
    g->redraw_all = 0;  /* both buffers already hold the initial title */

    int front = 0;
    uint32_t last_log = 0;

    for (;;) {
        uint16_t *back = front ? b0 : b1;
        uint8_t level = hal_buttons();
        uint8_t pressed = hal_buttons_pressed();

        game_frame(g, pressed, level, hal_now_ms(), back);

        /* One retry only: a persistent stall is a hardware problem and a
         * blocking UART line per frame would make it worse. */
        if (hal_present(back) && hal_present(back))
            hal_log("present failed\n");
        if (hal_wait_active(back)) hal_log("active timeout\n");
        front ^= 1;

        if ((g->frames - last_log) > 3600u) {
            last_log = g->frames;
            hal_log("fps heartbeat\n");
        }
    }
}
