/* -------------------------------------------------------------------------
 * game_logic.c -- state machine, collision and interaction for
 * "RV32 Courier".  No hardware access happens here; everything goes
 * through the actor/game state so the host build behaves identically.
 * ------------------------------------------------------------------------- */
#include "game.h"
#include <stddef.h>

#define SPEED_PX 2          /* pixels per frame (always even)               */
#define PLAYER_W GAME_SPRITE_W
#define PLAYER_H GAME_SPRITE_H

/* collision box, relative to the sprite top-left */
#define BOX_X0 3
#define BOX_Y0 11
#define BOX_X1 13
#define BOX_Y1 20

typedef struct {
    int tx, ty;
    int has_shard;
} chest_t;

static const chest_t CHESTS[4] = {
    { 5, 7, 1 },
    { 21, 6, 1 },
    { 11, 15, 1 },
    { 25, 13, 0 },
};

static const char *DLG_ELDER[] = {
    "ELDER: The beacon died the night the star shards scattered.",
    "ELDER: Three shards sleep in chests around the village. Bring them back.",
};
static const char *DLG_GIRL[] = {
    "MIRA: I saw a shard in the chest near the pond!",
    "MIRA: The old fence hides another one, I am sure.",
};
static const char *DLG_FISHER[] = {
    "FISHER: The lighthouse door only opens for a full beacon.",
    "FISHER: Pile up all three shards before you knock.",
};
static const char *DLG_SIGN[] = {
    "RV32 VILLAGE",
    "POP 12.  BEACON KEEPER WANTED.  ASK THE ELDER.",
};
static const char *DLG_SEALED[] = {
    "THE LIGHTHOUSE DOOR IS SEALED.",
    "THREE STAR SHARDS ARE NEEDED TO RELIGHT THE BEACON.",
};
static const char *DLG_KEY[] = {
    "A RUSTY KEY. NOT WHAT THE BEACON NEEDS.",
};

static int map_tile(const game_t *g, int tx, int ty)
{
    if ((unsigned)tx >= GAME_MAP_W || (unsigned)ty >= GAME_MAP_H) return TILE_TREE;
    return g->map[ty * GAME_MAP_W + tx];
}

static void set_tile(game_t *g, int tx, int ty, int tile)
{
    if ((unsigned)tx < GAME_MAP_W && (unsigned)ty < GAME_MAP_H)
        g->map[ty * GAME_MAP_W + tx] = (uint8_t)tile;
}

static int solid_px(const game_t *g, int x, int y)
{
    if (x < 0 || y < 0 || x >= FB_WIDTH || y >= FB_HEIGHT) return 1;
    return g_tile_solid[map_tile(g, x / GAME_TILE_W, y / GAME_TILE_H)];
}

static int box_blocked(const game_t *g, int x, int y)
{
    int x0 = x + BOX_X0, x1 = x + BOX_X1 - 1;
    int y0 = y + BOX_Y0, y1 = y + BOX_Y1 - 1;
    return solid_px(g, x0, y0) || solid_px(g, x1, y0) ||
           solid_px(g, x0, y1) || solid_px(g, x1, y1) ||
           solid_px(g, (x0 + x1) / 2, y0) || solid_px(g, (x0 + x1) / 2, y1);
}

/* ---- small string helpers (no libc on the target) ---------------------- */
static char *append(char *d, const char *s)
{
    while (*s) *d++ = *s++;
    *d = 0;
    return d;
}

static char *append_uint(char *d, uint32_t v)
{
    char tmp[12];
    int n = 0;
    if (v == 0) { *d++ = '0'; *d = 0; return d; }
    while (v && n < 11) { tmp[n++] = (char)('0' + (v % 10u)); v /= 10u; }
    while (n) *d++ = tmp[--n];
    *d = 0;
    return d;
}

/* ---- dialog ------------------------------------------------------------ */
static void open_dialog(game_t *g, const char **lines, int count)
{
    g->prev_state = g->state;
    g->state = GS_DIALOG;
    g->dialog_count = (uint8_t)count;
    g->dialog_line = 0;
    for (int i = 0; i < count && i < 3; i++) g->dialog[i] = lines[i];
    g->dialog_wait = 8;                 /* ignore the opening A press */
}

static void add_dirty(game_t *g, int x0, int y0, int x1, int y1)
{
    if (g->dirty_count >= GAME_DIRTY_MAX) {
        /* merge into the last slot instead of dropping the update */
        int16_t *d = g->dirty[GAME_DIRTY_MAX - 1];
        if (x0 < d[0]) d[0] = (int16_t)x0;
        if (y0 < d[1]) d[1] = (int16_t)y0;
        if (x1 > d[2]) d[2] = (int16_t)x1;
        if (y1 > d[3]) d[3] = (int16_t)y1;
        return;
    }
    int16_t *d = g->dirty[g->dirty_count++];
    d[0] = (int16_t)x0; d[1] = (int16_t)y0; d[2] = (int16_t)x1; d[3] = (int16_t)y1;
}

/* ---- set-up ------------------------------------------------------------ */
static void place_npc(actor_t *a, int tx, int ty, int skin, const char *name)
{
    a->x = (int16_t)(tx * GAME_TILE_W + 2);
    a->y = (int16_t)(ty * GAME_TILE_H - 4);
    a->home_x = (uint8_t)tx;
    a->home_y = (uint8_t)ty;
    a->dir = DIR_DOWN;
    a->moving = 0;
    a->anim = 0;
    a->skin = (uint8_t)skin;
    a->name = name;
}

void game_init(game_t *g, uint32_t now_ms)
{
    for (int i = 0; i < GAME_MAP_W * GAME_MAP_H; i++) g->map[i] = g_map[i];
    g->state = GS_TITLE;
    g->prev_state = GS_TITLE;
    g->shards = 0;
    for (int i = 0; i < 4; i++) g->opened[i] = 0;
    g->start_ms = now_ms;
    g->elapsed_ms = 0;
    g->frames = 0;
    g->dialog_count = 0;
    g->dialog_line = 0;
    g->dialog_wait = 0;
    g->redraw_all = 1;
    g->sync_full = 0;
    g->dirty_count = 0;

    g->player.x = 16 * GAME_TILE_W + 2;
    g->player.y = 10 * GAME_TILE_H;
    g->player.dir = DIR_DOWN;
    g->player.moving = 0;
    g->player.anim = 0;
    g->player.skin = 0;
    g->player.name = "COURIER";

    place_npc(&g->npc[0], 18, 4, 1, "ELDER");
    place_npc(&g->npc[1], 9, 8, 2, "MIRA");
    place_npc(&g->npc[2], 14, 16, 3, "FISHER");
}

/* ---- world update ------------------------------------------------------ */
static void move_player(game_t *g, uint8_t level)
{
    int dx = 0, dy = 0;
    uint8_t dir = g->player.dir;

    if (level & BTN_UP) { dy = -SPEED_PX; dir = DIR_UP; }
    else if (level & BTN_DOWN) { dy = SPEED_PX; dir = DIR_DOWN; }
    else if (level & BTN_LEFT) { dx = -SPEED_PX; dir = DIR_LEFT; }
    else if (level & BTN_RIGHT) { dx = SPEED_PX; dir = DIR_RIGHT; }

    g->player.dir = dir;
    g->player.moving = (dx != 0 || dy != 0);

    if (dx && !box_blocked(g, g->player.x + dx, g->player.y))
        g->player.x = (int16_t)(g->player.x + dx);
    if (dy && !box_blocked(g, g->player.x, g->player.y + dy))
        g->player.y = (int16_t)(g->player.y + dy);
}

static int facing_npc(game_t *g)
{
    for (int i = 0; i < 3; i++) {
        const actor_t *n = &g->npc[i];
        int dx = (n->x - g->player.x);
        int dy = (n->y - g->player.y);
        /* NPCs do not block movement, so the player can overlap one while
         * trying to talk.  Treat that overlap as an interaction as well. */
        if (dx > -14 && dx < 14 && dy > -18 && dy < 18) return i;
        switch (g->player.dir) {
        case DIR_DOWN:  if (dy > 6 && dy < 34 && dx > -20 && dx < 20) return i; break;
        case DIR_UP:    if (dy < -6 && dy > -34 && dx > -20 && dx < 20) return i; break;
        case DIR_LEFT:  if (dx < -6 && dx > -34 && dy > -20 && dy < 20) return i; break;
        default:        if (dx > 6 && dx < 34 && dy > -20 && dy < 20) return i; break;
        }
    }
    return -1;
}

static void interact(game_t *g)
{
    int cx = g->player.x + PLAYER_W / 2;
    int cy = g->player.y + PLAYER_H / 2;
    int tx = 0, ty = 0, tile = TILE_GRASS;

    /* A single point 24-26 pixels away skips over a chest when the player
     * touches its south or west edge.  Check the near tile first, then the
     * farther tile to retain the previous reach.  A solid non-interactable
     * tile blocks the farther probe, so objects cannot be used through walls. */
    for (int distance = 16; distance <= 26; distance += 10) {
        switch (g->player.dir) {
        case DIR_UP:    tx = cx / GAME_TILE_W; ty = (cy - distance) / GAME_TILE_H; break;
        case DIR_DOWN:  tx = cx / GAME_TILE_W; ty = (cy + distance) / GAME_TILE_H; break;
        case DIR_LEFT:  tx = (cx - distance) / GAME_TILE_W; ty = cy / GAME_TILE_H; break;
        default:        tx = (cx + distance) / GAME_TILE_W; ty = cy / GAME_TILE_H; break;
        }
        tile = map_tile(g, tx, ty);
        if (tile == TILE_CHEST || tile == TILE_SIGN || tile == TILE_GOAL ||
            g_tile_solid[tile]) break;
    }

    if (tile == TILE_CHEST) {
        set_tile(g, tx, ty, TILE_CHEST_OPEN);
        add_dirty(g, tx * GAME_TILE_W, ty * GAME_TILE_H,
                  tx * GAME_TILE_W + GAME_TILE_W, ty * GAME_TILE_H + GAME_TILE_H);
        for (int i = 0; i < 4; i++) {
            if (CHESTS[i].tx == tx && CHESTS[i].ty == ty && !g->opened[i]) {
                g->opened[i] = 1;
                if (CHESTS[i].has_shard) {
                    static char msg[64];
                    char *p = msg;
                    p = append(p, "A STAR SHARD!  SHARDS: ");
                    p = append_uint(p, g->shards + 1);
                    p = append(p, "/3");
                    g->shards++;
                    static const char *lines[1];
                    lines[0] = msg;
                    open_dialog(g, lines, 1);
                } else {
                    open_dialog(g, DLG_KEY, 1);
                }
                add_dirty(g, 0, 0, 200, 28);
                return;
            }
        }
        return;
    }
    if (tile == TILE_SIGN) { open_dialog(g, DLG_SIGN, 2); return; }
    if (tile == TILE_GOAL) {
        if (g->shards >= 3) {
            g->state = GS_WIN;
            g->redraw_all = 1;
        } else {
            open_dialog(g, DLG_SEALED, 2);
        }
        return;
    }
    int n = facing_npc(g);
    if (n == 0) { open_dialog(g, DLG_ELDER, 2); return; }
    if (n == 1) { open_dialog(g, DLG_GIRL, 2); return; }
    if (n == 2) { open_dialog(g, DLG_FISHER, 2); return; }
}

static void update(game_t *g, uint8_t pressed, uint8_t level, uint32_t now_ms)
{
    g->frames++;

    switch (g->state) {
    case GS_TITLE:
        if (pressed & BTN_A) {
            game_init(g, now_ms);
            g->state = GS_PLAY;
            g->redraw_all = 1;
        }
        break;

    case GS_PLAY: {
        g->elapsed_ms = now_ms - g->start_ms;
        move_player(g, level);
        if (g->player.moving) g->player.anim = (uint8_t)((g->frames >> 3) & 1);
        else g->player.anim = 0;
        if (pressed & BTN_A) interact(g);
        if (pressed & BTN_B) {
            /* pause is informational: reuse the dialog box */
            static const char *pause[] = {
                "PAUSED.  ARROWS MOVE, A INTERACTS.",
                "B AGAIN TO RESUME.",
            };
            open_dialog(g, pause, 2);
        }
        break;
    }

    case GS_DIALOG:
        g->elapsed_ms = now_ms - g->start_ms;
        if (g->dialog_wait) { g->dialog_wait--; break; }
        if (pressed & (BTN_A | BTN_B)) {
            if (g->dialog_line + 1 < g->dialog_count) {
                g->dialog_line++;
                g->dialog_wait = 4;
            } else {
                g->state = g->prev_state;
                g->dialog_count = 0;
            }
        }
        break;

    case GS_WIN:
        if (pressed & BTN_A) {
            game_init(g, now_ms);
            g->state = GS_TITLE;
            g->redraw_all = 1;
        }
        break;
    default:
        g->state = GS_TITLE;
        break;
    }
}

void game_frame(game_t *g, uint8_t pressed, uint8_t level, uint32_t now_ms,
                uint16_t *fb)
{
    /* The buffer we are about to draw is one publication behind.  Replay the
     * previous frame's damage using the current game state before applying the
     * next input.  Full-screen transitions must also reach the other buffer. */
    if (g->sync_full) {
        game_render_full(g, fb);
    } else {
        for (int i = 0; i < g->dirty_count; i++) {
            const int16_t *d = g->dirty[i];
            game_render_rect(g, fb, d[0], d[1], d[2], d[3]);
        }
    }
    g->sync_full = 0;

    int ox0 = g->player.x - 2, oy0 = g->player.y - 2;
    int ox1 = g->player.x + PLAYER_W + 2, oy1 = g->player.y + PLAYER_H + 2;
    uint8_t old_state = g->state;
    uint8_t old_shards = g->shards;
    uint8_t old_dialog_line = g->dialog_line;
    uint32_t old_seconds = g->elapsed_ms / 1000u;

    g->dirty_count = 0;
    update(g, pressed, level, now_ms);

    if (g->redraw_all) {
        g->redraw_all = 0;
        game_render_full(g, fb);
        g->sync_full = 1;
        return;
    }

    /* Title and win screens are static; drawing world damage on them would
     * punch a small patch of the map through the displayed screen. */
    if (g->state == GS_TITLE || g->state == GS_WIN) return;

    int nx0 = g->player.x - 2, ny0 = g->player.y - 2;
    int nx1 = g->player.x + PLAYER_W + 2, ny1 = g->player.y + PLAYER_H + 2;
    if (nx0 < ox0) ox0 = nx0;
    if (ny0 < oy0) oy0 = ny0;
    if (nx1 > ox1) ox1 = nx1;
    if (ny1 > oy1) oy1 = ny1;
    if (ox0 < 0) ox0 = 0;
    if (oy0 < 0) oy0 = 0;
    if (ox1 > FB_WIDTH) ox1 = FB_WIDTH;
    if (oy1 > FB_HEIGHT) oy1 = FB_HEIGHT;
    if (ox0 < ox1 && oy0 < oy1) add_dirty(g, ox0, oy0, ox1, oy1);

    if (old_state != g->state) {
        if (g->state == GS_DIALOG) add_dirty(g, 8, 236, FB_WIDTH - 8, FB_HEIGHT);
        if (old_state == GS_DIALOG) add_dirty(g, 8, 236, FB_WIDTH - 8, FB_HEIGHT);
    }
    if (g->state == GS_DIALOG && old_state == GS_DIALOG && old_dialog_line != g->dialog_line)
        add_dirty(g, 8, 236, FB_WIDTH - 8, FB_HEIGHT);
    if (old_shards != g->shards) add_dirty(g, 0, 0, 200, HUD_H);
    if (old_seconds != g->elapsed_ms / 1000u) add_dirty(g, 0, 0, FB_WIDTH, HUD_H);

    for (int i = 0; i < g->dirty_count; i++) {
        const int16_t *d = g->dirty[i];
        game_render_rect(g, fb, d[0], d[1], d[2], d[3]);
    }
}
