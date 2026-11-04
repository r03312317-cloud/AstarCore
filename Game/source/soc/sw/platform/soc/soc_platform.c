/* -------------------------------------------------------------------------
 * soc_platform.c -- board implementation of the game HAL.
 *
 * Everything here is MMIO defined in game_regs.h.  The CPU runs at 100 MHz and
 * the CP13 timer counts CPU cycles, so milliseconds are cycles / 100000.
 * ------------------------------------------------------------------------- */
#include "game_regs.h"
#include "game_hal.h"

#define REG32(addr) (*(volatile uint32_t *)(uintptr_t)(addr))

#define CPU_HZ 100000000u
#define CYCLES_PER_MS (CPU_HZ / 1000u)

static uint16_t *const FB_PTR[2] = {
    (uint16_t *)(uintptr_t)FB0_ADDR,
    (uint16_t *)(uintptr_t)FB1_ADDR,
};

static uint32_t read_cycles(void)
{
    uint32_t hi1, lo, hi2;
    do {
        hi1 = REG32(MMIO_TIMER_MS_HI);
        lo = REG32(MMIO_TIMER_MS);
        hi2 = REG32(MMIO_TIMER_MS_HI);
    } while (hi1 != hi2);
    return lo;          /* wraps after ~43 s at 100 MHz; see hal_now_ms()   */
}

void hal_init(void)
{
    /* Bring-up markers: the video window crosses into the DDR clock domain
     * through pg_mmio_cdc, so a broken handshake there stalls the store
     * forever.  One character per step says exactly which write never
     * returned.  Remove once the display path is trusted. */
    hal_log("i1\n");
    REG32(MMIO_GAME_INPUT + GIN_DEBOUNCE_MS) = 6;      /* 6 ms debounce     */
    REG32(MMIO_GAME_INPUT + GIN_REPEAT_DELAY) = 320;
    REG32(MMIO_GAME_INPUT + GIN_REPEAT_PERIOD) = 90;
    hal_log("i2\n");
    REG32(MMIO_GAME_VIDEO + GVID_FB0) = FB0_ADDR;
    hal_log("i3\n");
    REG32(MMIO_GAME_VIDEO + GVID_FB1) = FB1_ADDR;
    hal_log("i4\n");
    REG32(MMIO_GAME_VIDEO + GVID_CTRL) = 0;            /* show frame buffer */
    hal_log("i5\n");
}

uint16_t *hal_fb(int index)
{
    return FB_PTR[index & 1];
}

uint32_t hal_now_ms(void)
{
    /* 32-bit cycle counter + software extension is overkill for a demo; the
     * game only needs a monotonic millisecond value for its timer, so the
     * low 32 bits (43 s wrap) are extended here with a small epoch counter. */
    static uint32_t last_lo;
    static uint32_t epoch;
    uint32_t lo = read_cycles();
    if (lo < last_lo) epoch += (0xFFFFFFFFu / CYCLES_PER_MS); /* one wrap */
    last_lo = lo;
    return epoch + lo / CYCLES_PER_MS;
}

uint32_t hal_frames(void)
{
    return REG32(MMIO_GAME_VIDEO + GVID_VSYNC);
}

uint32_t hal_vsync_count(void)
{
    return REG32(MMIO_GAME_VIDEO + GVID_VSYNC);
}

uint32_t hal_video_status(void)
{
    return REG32(MMIO_GAME_VIDEO + GVID_STATUS);
}

uint8_t hal_buttons(void)
{
    return (uint8_t)(REG32(MMIO_GAME_INPUT + GIN_LEVEL) & 0xffu);
}

uint8_t hal_buttons_pressed(void)
{
    uint32_t events = REG32(MMIO_GAME_INPUT + GIN_PRESSED);
    if (events) REG32(MMIO_GAME_INPUT + GIN_PRESSED) = events; /* W1C */
    return (uint8_t)(events & 0xffu);
}

int hal_present(uint16_t *fb)
{
    /* The commit crosses into the DDR clock domain through pg_mmio_cdc, so the
     * acknowledgement is observed by watching the publication counter rather
     * than by guessing a fixed delay.
     *
     * A commit is only taken at the next vertical blank, so the wait budget has
     * to exceed one 16.7 ms frame; 2 ms (the original value) timed out on
     * essentially every frame. */
    uint32_t before = REG32(MMIO_GAME_VIDEO + GVID_PUBLISHED);
    uint32_t start = read_cycles();
    REG32(MMIO_GAME_VIDEO + GVID_COMMIT) = (uint32_t)(uintptr_t)fb;
    while (REG32(MMIO_GAME_VIDEO + GVID_PUBLISHED) == before) {
        if ((uint32_t)(read_cycles() - start) > 40u * CYCLES_PER_MS)
            return 1;
    }
    return REG32(MMIO_GAME_VIDEO + GVID_ERROR) != 0;
}

uint16_t *hal_active_fb(void)
{
    return (uint16_t *)(uintptr_t)REG32(MMIO_GAME_VIDEO + GVID_ACTIVE_FB);
}

int hal_wait_active(uint16_t *fb)
{
    uint32_t target = (uint32_t)(uintptr_t)fb;
    uint32_t start = read_cycles();
    while (REG32(MMIO_GAME_VIDEO + GVID_ACTIVE_FB) != target) {
        if ((uint32_t)(read_cycles() - start) > 100u * CYCLES_PER_MS)
            return 1;               /* six 60 Hz frames is already a fault  */
    }
    return 0;
}

void hal_log(const char *text)
{
    /* Status word is {overrun, frame, !tx_valid, rx_valid} in bits [3:0], so
     * bit 1 is "transmit holding register free" and bit 0 is "a byte has been
     * received".  Polling bit 0 here deadlocked the very first boot banner:
     * rx_valid stays 0 unless the PC sends something, so the core spun
     * forever, never started the game and never emitted a character.  The
     * bounded spin keeps a future status change from hanging the CPU again. */
    while (*text) {
        uint32_t guard = 0;
        while (!(REG32(MMIO_UART_STATUS) & 2u) && ++guard < 200000u) { }
        REG32(MMIO_UART_TX) = (uint32_t)(uint8_t)*text++;
    }
}

void hal_log_hex(uint32_t value)
{
    char buf[11];
    int n = 0;
    buf[n++] = '0';
    buf[n++] = 'x';
    for (int shift = 28; shift >= 0; shift -= 4) {
        uint32_t digit = (value >> shift) & 0xfu;
        buf[n++] = (char)(digit < 10 ? '0' + digit : 'a' + digit - 10);
    }
    buf[n] = 0;
    hal_log(buf);
}

int hal_is_host(void) { return 0; }
void hal_host_tick(void) { }
int hal_host_dump(const char *path) { (void)path; return -1; }
