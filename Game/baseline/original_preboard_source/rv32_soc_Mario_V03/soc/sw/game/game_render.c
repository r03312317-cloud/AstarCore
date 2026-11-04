/* -------------------------------------------------------------------------
 * game_render.c -- software renderer for the 640x360 RGB565 frame buffer.
 *
 * Only 32-bit stores are issued, and every sprite/tile X coordinate is even,
 * so one store always covers two adjacent pixels.  That halves the number of
 * non-cacheable DDR write transactions, which is the real cost on this SoC.
 * ------------------------------------------------------------------------- */
#include "game.h"
#include <stddef.h>

#define SCREEN_W FB_WIDTH
#define SCREEN_H FB_HEIGHT

static inline void px(uint16_t *fb, int x, int y, uint16_t c)
{
    if ((unsigned)x >= SCREEN_W || (unsigned)y >= SCREEN_H) return;
    fb[(unsigned)y * SCREEN_W + (unsigned)x] = c;
}

/* two pixels at an even X */
static inline void px2(uint16_t *fb, int x, int y, uint16_t c)
{
    if ((unsigned)y >= SCREEN_H || (unsigned)x >= SCREEN_W) return;
    if (x + 1 >= SCREEN_W) { fb[(unsigned)y * SCREEN_W + (unsigned)x] = c; return; }
    ((uint32_t *)fb)[((unsigned)y * (SCREEN_W / 2)) + ((unsigned)x >> 1)] =
        (uint32_t)c | ((uint32_t)c << 16);
}

static void fill_rect(uint16_t *fb, int x0, int y0, int x1, int y1, uint16_t c)
{
    if (x0 < 0) x0 = 0;
    if (y0 < 0) y0 = 0;
    if (x1 > SCREEN_W) x1 = SCREEN_W;
    if (y1 > SCREEN_H) y1 = SCREEN_H;
    for (int y = y0; y < y1; y++) {
        int x = x0;
        if (x & 1) { px(fb, x, y, c); x++; }
        for (; x + 1 < x1; x += 2) px2(fb, x, y, c);
        if (x < x1) px(fb, x, y, c);
    }
}

static void frame_rect(uint16_t *fb, int x0, int y0, int x1, int y1, uint16_t c)
{
    fill_rect(fb, x0, y0, x1, y0 + 2, c);
    fill_rect(fb, x0, y1 - 2, x1, y1, c);
    fill_rect(fb, x0, y0, x0 + 2, y1, c);
    fill_rect(fb, x1 - 2, y0, x1, y1, c);
}

/* ---- text -------------------------------------------------------------- */
static void draw_char(uint16_t *fb, int x, int y, char ch, uint16_t color, int scale)
{
    unsigned code = (unsigned char)ch;
    if (code < 32 || code > 126) code = '?';
    const uint8_t *rows = &g_font[(code - 32) * 7];
    for (int r = 0; r < 7; r++) {
        uint8_t bits = rows[r];
        for (int c = 0; c < 5; c++) {
            if (bits & (1u << c)) {
                if (scale == 1) px(fb, x + c, y + r, color);
                else fill_rect(fb, x + c * scale, y + r * scale,
                               x + c * scale + scale, y + r * scale + scale, color);
            }
        }
    }
}

static int text_width(const char *s, int scale)
{
    int n = 0;
    while (s[n]) n++;
    return n * 6 * scale;
}

static void draw_text(uint16_t *fb, int x, int y, const char *s, uint16_t color, int scale)
{
    while (*s) {
        draw_char(fb, x, y, *s, color, scale);
        x += 6 * scale;
        s++;
    }
}

static void draw_text_center(uint16_t *fb, int y, const char *s, uint16_t color, int scale)
{
    draw_text(fb, (SCREEN_W - text_width(s, scale)) / 2, y, s, color, scale);
}

/* ---- world ------------------------------------------------------------- */
static int map_tile(const game_t *g, int tx, int ty)
{
    if ((unsigned)tx >= GAME_MAP_W || (unsigned)ty >= GAME_MAP_H) return TILE_TREE;
    return g->map[ty * GAME_MAP_W + tx];
}

static void draw_tile_clip(uint16_t *fb, int tile, int dx, int dy,
                           int cx0, int cy0, int cx1, int cy1)
{
    const uint16_t *src = g_tiles[tile];
    int y0 = cy0 - dy; if (y0 < 0) y0 = 0;
    int y1 = cy1 - dy; if (y1 > GAME_TILE_H) y1 = GAME_TILE_H;
    int x0 = cx0 - dx; if (x0 < 0) x0 = 0;
    int x1 = cx1 - dx; if (x1 > GAME_TILE_W) x1 = GAME_TILE_W;
    if (x0 & 1) x0--;                       /* keep pair alignment */
    for (int y = y0; y < y1; y++) {
        const uint16_t *row = src + y * GAME_TILE_W;
        for (int x = x0; x < x1; x += 2)
            px2(fb, dx + x, dy + y, row[x]);
    }
}

static void draw_sprite_clip(uint16_t *fb, const uint16_t *src, int dx, int dy,
                             int cx0, int cy0, int cx1, int cy1)
{
    int y0 = cy0 - dy; if (y0 < 0) y0 = 0;
    int y1 = cy1 - dy; if (y1 > GAME_SPRITE_H) y1 = GAME_SPRITE_H;
    int x0 = cx0 - dx; if (x0 < 0) x0 = 0;
    int x1 = cx1 - dx; if (x1 > GAME_SPRITE_W) x1 = GAME_SPRITE_W;
    for (int y = y0; y < y1; y++) {
        const uint16_t *row = src + y * GAME_SPRITE_W;
        for (int x = x0; x < x1; x++) {
            uint16_t c = row[x];
            if (c != GAME_SPRITE_KEY) px(fb, dx + x, dy + y, c);
        }
    }
}

static const uint16_t *actor_pixels(const game_t *g, const actor_t *a)
{
    if (a->skin == 0)
        return g_player[a->dir & 3][a->anim & 1];
    return g_npc[(a->skin - 1) % GAME_NPC_SKINS];
}

static void draw_actor_clip(game_t *g, uint16_t *fb, const actor_t *a,
                            int cx0, int cy0, int cx1, int cy1)
{
    draw_sprite_clip(fb, actor_pixels(g, a), a->x, a->y, cx0, cy0, cx1, cy1);
}

/* ---- overlays ---------------------------------------------------------- */
/* 9x11 diamond: outline in both states, gold fill plus a highlight when the
 * shard has been collected. */
static void shard_icon(uint16_t *fb, int x, int y, int filled)
{
    uint16_t edge = filled ? C_GOLD : C_DIM;
    uint16_t body = filled ? C_GOLD : C_PANEL;
    for (int row = 0; row < 11; row++) {
        int half = (row < 6) ? row : 10 - row;
        for (int col = 4 - half; col <= 4 + half; col++) {
            int border = (col == 4 - half) || (col == 4 + half);
            uint16_t c = border ? edge : body;
            if (filled && col == 3 - half / 2 && row > 2 && row < 6) c = C_WHITE;
            px(fb, x + col, y + row, c);
        }
    }
}

static void draw_hud(game_t *g, uint16_t *fb)
{
    fill_rect(fb, 0, 0, SCREEN_W, HUD_H, C_PANEL);
    fill_rect(fb, 0, HUD_H - 2, SCREEN_W, HUD_H, C_PANEL_EDGE);
    for (int i = 0; i < 3; i++) shard_icon(fb, 8 + i * 20, 6, i < g->shards);

    uint32_t secs = g->elapsed_ms / 1000u;
    char buf[24];
    int n = 0;
    buf[n++] = 'T'; buf[n++] = 'I'; buf[n++] = 'M'; buf[n++] = 'E'; buf[n++] = ' ';
    if (secs >= 600) buf[n++] = (char)('0' + (secs / 600) % 10);
    buf[n++] = (char)('0' + (secs / 60) % 10);
    buf[n++] = ':';
    buf[n++] = (char)('0' + (secs / 10) % 6);
    buf[n++] = (char)('0' + secs % 10);
    buf[n] = 0;
    draw_text(fb, SCREEN_W - text_width(buf, 2) - 8, 7, buf, C_DIM, 2);
}

static void word_wrap(const char *src, char *dst, int width)
{
    int col = 0, i = 0;
    while (*src) {
        if (col >= width && *src == ' ') { dst[i++] = '\n'; col = 0; src++; continue; }
        dst[i++] = *src;
        if (*src == '\n') col = 0; else col++;
        src++;
    }
    dst[i] = 0;
}

static void draw_dialog(game_t *g, uint16_t *fb)
{
    fill_rect(fb, 12, DIALOG_Y, SCREEN_W - 12, DIALOG_Y + DIALOG_H, C_PANEL);
    frame_rect(fb, 12, DIALOG_Y, SCREEN_W - 12, DIALOG_Y + DIALOG_H, C_PANEL_EDGE);

    const char *line = (g->dialog_line < g->dialog_count) ? g->dialog[g->dialog_line]
                                                          : "";
    char wrapped[220];
    word_wrap(line, wrapped, 48);
    int y = DIALOG_Y + 14;
    const char *p = wrapped;
    while (*p && y < DIALOG_Y + DIALOG_H - 20) {
        char row[56];
        int n = 0;
        while (*p && *p != '\n' && n < 55) row[n++] = *p++;
        if (*p == '\n') p++;
        row[n] = 0;
        draw_text(fb, 28, y, row, C_WHITE, 2);
        y += 18;
    }
    if (g->dialog_line + 1 < g->dialog_count)
        draw_text(fb, SCREEN_W - 110, DIALOG_Y + DIALOG_H - 22, "A >", C_GOLD, 2);
    else
        draw_text(fb, SCREEN_W - 130, DIALOG_Y + DIALOG_H - 22, "A CLOSE", C_GOLD, 2);
}

static void draw_title(uint16_t *fb)
{
    fill_rect(fb, 0, 0, SCREEN_W, SCREEN_H, C_PANEL);
    for (int i = 0; i < 40; i++) {
        int x = (i * 97) % SCREEN_W;
        int y = (i * 53) % SCREEN_H;
        px(fb, x, y, C_PANEL_EDGE);
    }
    draw_text_center(fb, 96, "RV32 COURIER", C_GOLD, 4);
    draw_text_center(fb, 152, "THE BEACON WENT DARK", C_WHITE, 2);
    draw_text_center(fb, 214, "FIND 3 STAR SHARDS", C_DIM, 2);
    draw_text_center(fb, 238, "AND RELIGHT THE LIGHTHOUSE", C_DIM, 2);
    draw_text_center(fb, 300, "PRESS A TO START", C_GREEN, 2);
}

static void draw_win(game_t *g, uint16_t *fb)
{
    fill_rect(fb, 0, 0, SCREEN_W, SCREEN_H, C_PANEL);
    draw_text_center(fb, 88, "QUEST COMPLETE", C_GOLD, 4);
    draw_text_center(fb, 150, "THE BEACON BURNS AGAIN", C_WHITE, 2);

    uint32_t secs = g->elapsed_ms / 1000u;
    char buf[24];
    int n = 0;
    buf[n++] = 'T'; buf[n++] = 'I'; buf[n++] = 'M'; buf[n++] = 'E'; buf[n++] = ' ';
    buf[n++] = (char)('0' + (secs / 60) / 10 % 6);
    buf[n++] = (char)('0' + (secs / 60) % 10);
    buf[n++] = ':';
    buf[n++] = (char)('0' + (secs % 60) / 10);
    buf[n++] = (char)('0' + (secs % 10));
    buf[n] = 0;
    draw_text_center(fb, 196, buf, C_DIM, 3);
    draw_text_center(fb, 300, "PRESS A TO PLAY AGAIN", C_GREEN, 2);
}

/* ---- public entry points ----------------------------------------------- */
void game_render_rect(game_t *g, uint16_t *fb, int x0, int y0, int x1, int y1)
{
    if (x0 < 0) x0 = 0;
    if (y0 < 0) y0 = 0;
    if (x1 > SCREEN_W) x1 = SCREEN_W;
    if (y1 > SCREEN_H) y1 = SCREEN_H;
    if (x0 >= x1 || y0 >= y1) return;

    int tx0 = x0 / GAME_TILE_W;
    int ty0 = y0 / GAME_TILE_H;
    int tx1 = (x1 + GAME_TILE_W - 1) / GAME_TILE_W;
    int ty1 = (y1 + GAME_TILE_H - 1) / GAME_TILE_H;

    for (int ty = ty0; ty < ty1 && ty < GAME_MAP_H; ty++) {
        for (int tx = tx0; tx < tx1 && tx < GAME_MAP_W; tx++) {
            draw_tile_clip(fb, map_tile(g, tx, ty), tx * GAME_TILE_W, ty * GAME_TILE_H,
                           x0, y0, x1, y1);
        }
    }

    for (int i = 0; i < 3; i++) draw_actor_clip(g, fb, &g->npc[i], x0, y0, x1, y1);
    draw_actor_clip(g, fb, &g->player, x0, y0, x1, y1);

    if (y0 < HUD_H) draw_hud(g, fb);
    if (g->state == GS_DIALOG && y1 > DIALOG_Y) draw_dialog(g, fb);
}

void game_render_full(game_t *g, uint16_t *fb)
{
    /* The title and victory screens cover every pixel, so drawing the world
     * underneath would double the (expensive, non-cached DDR) store count for
     * nothing.  A full-screen redraw is ~115k 32-bit stores, which is already
     * the dominant cost of a state transition. */
    if (g->state == GS_TITLE) { draw_title(fb); return; }
    if (g->state == GS_WIN) { draw_win(g, fb); return; }
    game_render_rect(g, fb, 0, 0, SCREEN_W, SCREEN_H);
}
