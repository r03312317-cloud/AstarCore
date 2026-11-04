/* Reproduce interaction at collision distance and prevent through-wall use. */
#include "game.h"
#include <stdint.h>
#include <stdio.h>

static game_t game;
static uint16_t fb[FB_WIDTH * FB_HEIGHT];

typedef struct {
    const char *name;
    int x, y;
    uint8_t level;
} approach_t;

static void setup(void)
{
    game_init(&game, 0);
    game.state = GS_PLAY;
    game.redraw_all = game.sync_full = game.dirty_count = 0;
    for (int i = 0; i < GAME_MAP_W * GAME_MAP_H; ++i) game.map[i] = TILE_GRASS;
    for (int i = 0; i < 3; ++i) { game.npc[i].x = 0; game.npc[i].y = 0; }
}

int main(void)
{
    const int tx = 21, ty = 6;
    const approach_t a[] = {
        {"below", tx*20+2, (ty+2)*20, BTN_UP},
        {"above", tx*20+2, (ty-2)*20, BTN_DOWN},
        {"left", (tx-2)*20, ty*20, BTN_RIGHT},
        {"right", (tx+2)*20, ty*20, BTN_LEFT},
    };
    int fails = 0;
    for (unsigned i = 0; i < sizeof(a)/sizeof(a[0]); ++i) {
        for (int gap = 0; gap <= 8; gap += 4) {
            setup();
            game.map[ty * GAME_MAP_W + tx] = TILE_CHEST;
            game.player.x = (int16_t)a[i].x;
            game.player.y = (int16_t)a[i].y;
            for (int t = 0; t < 30; ++t) game_frame(&game, 0, a[i].level, t*16, fb);
            switch (a[i].level) {
            case BTN_UP:    game.player.y += gap; break;
            case BTN_DOWN:  game.player.y -= gap; break;
            case BTN_LEFT:  game.player.x += gap; break;
            default:        game.player.x -= gap; break;
            }
            game_frame(&game, BTN_A, BTN_A, 500, fb);
            int ok = game.opened[1] && game.shards == 1 && game.state == GS_DIALOG;
            printf("chest from %s gap=%d %s\n", a[i].name, gap, ok ? "PASS" : "FAIL");
            fails += !ok;
        }
    }

    setup();
    game.npc[0].x = 300; game.npc[0].y = 160;
    game.player.x = 300; game.player.y = 160; game.player.dir = DIR_UP;
    game_frame(&game, BTN_A, BTN_A, 500, fb);
    int npc_ok = game.state == GS_DIALOG && game.dialog_count == 2;
    printf("overlapping NPC %s\n", npc_ok ? "PASS" : "FAIL");
    fails += !npc_ok;

    setup();
    game.map[ty * GAME_MAP_W + tx] = TILE_CHEST;
    game.map[ty * GAME_MAP_W + tx - 1] = TILE_WALL;
    game.player.x = 386; game.player.y = ty*20; game.player.dir = DIR_RIGHT;
    game_frame(&game, BTN_A, BTN_A, 500, fb);
    int blocked_ok = !game.opened[1] && game.state == GS_PLAY;
    printf("wall blocks interaction %s\n", blocked_ok ? "PASS" : "FAIL");
    fails += !blocked_ok;
    return fails ? 1 : 0;
}
