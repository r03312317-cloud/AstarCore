/* Compare every incremental frame with a full rendering of the same state. */
#include "game.h"
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static game_t game;
static uint16_t buffers[2][FB_WIDTH * FB_HEIGHT];
static uint16_t reference[FB_WIDTH * FB_HEIGHT];
static unsigned frame;

static int step(uint8_t pressed, uint8_t level, uint32_t ms, const char *stage)
{
    uint16_t *back = buffers[frame++ & 1u];
    game_frame(&game, pressed, level, ms, back);
    memset(reference, 0, sizeof(reference));
    game_render_full(&game, reference);
    size_t mismatches = 0;
    for (size_t i = 0; i < FB_WIDTH * FB_HEIGHT; ++i)
        if (back[i] != reference[i]) ++mismatches;
    if (mismatches) {
        printf("FAIL stage=%s frame=%u state=%u differing_pixels=%zu\n",
               stage, frame, game.state, mismatches);
        return 1;
    }
    return 0;
}

int main(void)
{
    game_init(&game, 0);
    game_render_full(&game, buffers[0]);
    game_render_full(&game, buffers[1]);
    game.redraw_all = 0; /* both startup buffers already contain the title */
    if (step(0, 0, 16, "title_idle")) return 1;
    if (step(BTN_A, BTN_A, 32, "title_to_game")) return 1;
    if (step(0, 0, 48, "game_second_buffer")) return 1;
    for (unsigned n = 0; n < 12; ++n)
        if (step(0, BTN_RIGHT, 64 + n*16, "movement")) return 1;
    if (step(BTN_B, BTN_B, 300, "dialog_open")) return 1;
    for (unsigned n = 0; n < 9; ++n)
        if (step(0, 0, 316 + n*16, "dialog_wait")) return 1;
    if (step(BTN_A, BTN_A, 476, "dialog_next_line")) return 1;
    for (unsigned n = 0; n < 5; ++n)
        if (step(0, 0, 492 + n*16, "dialog_line_wait")) return 1;
    if (step(BTN_A, BTN_A, 588, "dialog_close")) return 1;
    if (step(0, 0, 1040, "hud_timer")) return 1;
    if (step(0, 0, 1056, "hud_timer_second_buffer")) return 1;
    puts("PASS: both buffers match full redraw through title, movement, dialog and timer");
    return 0;
}
