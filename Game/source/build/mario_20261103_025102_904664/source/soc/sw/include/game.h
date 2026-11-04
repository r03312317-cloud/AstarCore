/* -------------------------------------------------------------------------
 * game.h -- "RV32 Courier", the original 2D RPG demo.
 *
 * Rendering model: the CPU owns two RGB565 frame buffers in DDR.  It draws
 * only the rectangles that changed since the previous frame (a full 640x360
 * redraw would cost about 230k pixel stores, far too much for 60 Hz).  The
 * HDMI scan-out reads the other buffer, so the visible picture is always a
 * complete frame.
 * ------------------------------------------------------------------------- */
#ifndef GAME_H
#define GAME_H

#include <stdint.h>
#include "game_assets.h"
#include "game_regs.h"

#define COLOR(r, g, b) ((uint16_t)((((r) >> 3) << 11) | (((g) >> 2) << 5) | ((b) >> 3)))

#define C_BLACK      COLOR(0, 0, 0)
#define C_WHITE      COLOR(255, 255, 255)
#define C_INK        COLOR(24, 20, 30)
#define C_PANEL      COLOR(28, 34, 56)
#define C_PANEL_EDGE COLOR(90, 140, 200)
#define C_GOLD       COLOR(242, 193, 78)
#define C_RED        COLOR(210, 70, 60)
#define C_GREEN      COLOR(120, 210, 120)
#define C_DIM        COLOR(150, 156, 176)

#define HUD_H 28
#define DIALOG_Y 240
#define DIALOG_H 112

#define GAME_ACTOR_MAX 4
#define GAME_DIRTY_MAX 4

/* Game states */
enum {
    GS_TITLE = 0,
    GS_PLAY,
    GS_DIALOG,
    GS_WIN
};

/* Actor direction, index into g_player[] */
enum { DIR_DOWN = 0, DIR_UP = 1, DIR_LEFT = 2, DIR_RIGHT = 3 };

typedef struct {
    int16_t  x, y;        /* sprite top-left, pixels                        */
    uint8_t  dir;
    uint8_t  moving;
    uint8_t  anim;
    uint8_t  skin;        /* 0 = player, 1..3 = npc                         */
    uint8_t  home_x, home_y; /* tile anchor (NPCs stand still)              */
    const char *name;
} actor_t;

typedef struct {
    uint8_t  state;
    uint8_t  prev_state;
    uint8_t  shards;
    uint8_t  opened[4];
    uint8_t  map[GAME_MAP_W * GAME_MAP_H];
    actor_t  player;
    actor_t  npc[3];
    uint32_t start_ms;
    uint32_t elapsed_ms;
    uint32_t frames;
    uint8_t  dialog_line;
    uint8_t  dialog_count;
    const char *dialog[3];
    uint8_t  dialog_wait;      /* frames to wait before accepting input     */
    uint8_t  redraw_all;
    uint8_t  sync_full;        /* previous full redraw is missing in back buffer */
    uint8_t  dirty_count;
    int16_t  dirty[GAME_DIRTY_MAX][4];   /* x0,y0,x1,y1 (exclusive)          */
} game_t;

void game_init(game_t *g, uint32_t now_ms);
void game_frame(game_t *g, uint8_t pressed, uint8_t level, uint32_t now_ms,
                uint16_t *fb);

/* shared helpers (render side) */
void game_render_full(game_t *g, uint16_t *fb);
void game_render_rect(game_t *g, uint16_t *fb, int x0, int y0, int x1, int y1);

#endif /* GAME_H */
