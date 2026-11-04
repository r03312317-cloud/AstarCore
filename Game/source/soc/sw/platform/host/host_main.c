/* -------------------------------------------------------------------------
 * host_main.c -- automated playthrough of the real game code on the PC.
 *
 * This is not a separate implementation: it links the same game_logic.c and
 * game_render.c as the FPGA build and only replaces the HAL.  A scripted courier
 * walks to every chest, opens it and then enters the lighthouse, which proves
 * that the level is completable and that the renderer produces the frames that
 * are dumped along the way.
 * ------------------------------------------------------------------------- */
#include "game.h"
#include "game_hal.h"
#include "game_regs.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void host_set_buttons(uint8_t level);

#define MAX_WAYPOINTS 128

typedef struct {
    int tx, ty;
    const char *label;
} goal_t;

static const goal_t GOALS[] = {
    { 5, 7, "chest_pond" },
    { 21, 6, "chest_east" },
    { 11, 15, "chest_south" },
    { 25, 13, "chest_key" },
    { 28, 14, "lighthouse" },
};
#define GOAL_COUNT ((int)(sizeof(GOALS) / sizeof(GOALS[0])))

static game_t g;

/* ---- BFS over walkable tiles ------------------------------------------- */
static int tile_solid(int tx, int ty)
{
    if ((unsigned)tx >= GAME_MAP_W || (unsigned)ty >= GAME_MAP_H) return 1;
    return g_tile_solid[g.map[ty * GAME_MAP_W + tx]];
}

static int bfs(int sx, int sy, int tx, int ty, int *path, int max_path)
{
    static int prev[GAME_MAP_W * GAME_MAP_H];
    static int queue[GAME_MAP_W * GAME_MAP_H];
    for (int i = 0; i < GAME_MAP_W * GAME_MAP_H; i++) prev[i] = -2;
    int head = 0, tail = 0;
    int start = sy * GAME_MAP_W + sx;
    prev[start] = -1;
    queue[tail++] = start;

    int goal_cell = -1;
    while (head < tail && goal_cell < 0) {
        int cell = queue[head++];
        int cx = cell % GAME_MAP_W, cy = cell / GAME_MAP_W;
        static const int dx[4] = { 0, 0, -1, 1 };
        static const int dy[4] = { -1, 1, 0, 0 };
        for (int d = 0; d < 4; d++) {
            int nx = cx + dx[d], ny = cy + dy[d];
            if ((unsigned)nx >= GAME_MAP_W || (unsigned)ny >= GAME_MAP_H) continue;
            int ncell = ny * GAME_MAP_W + nx;
            if (prev[ncell] != -2) continue;
            if (tile_solid(nx, ny)) continue;
            prev[ncell] = cell;
            if (nx == tx && ny == ty) { goal_cell = ncell; break; }
            queue[tail++] = ncell;
        }
    }
    if (goal_cell < 0) return 0;

    int rev[MAX_WAYPOINTS];
    int n = 0;
    int cell = goal_cell;
    while (cell != start && n < MAX_WAYPOINTS) {
        rev[n++] = cell;
        cell = prev[cell];
    }
    if (cell != start) return 0;
    for (int i = 0; i < n; i++) path[i] = rev[n - 1 - i];
    return n;
}

/* Find a walkable tile next to (tx,ty) and path to it. */
static int plan_to(int tx, int ty, int *path)
{
    static const int dx[4] = { 0, 0, -1, 1 };
    static const int dy[4] = { -1, 1, 0, 0 };
    int sx = g.player.x / GAME_TILE_W;
    int sy = g.player.y / GAME_TILE_H;
    int best_n = 0;
    int best[MAX_WAYPOINTS];
    for (int d = 0; d < 4; d++) {
        int nx = tx + dx[d], ny = ty + dy[d];
        if ((unsigned)nx >= GAME_MAP_W || (unsigned)ny >= GAME_MAP_H) continue;
        if (tile_solid(nx, ny)) continue;
        int cand[MAX_WAYPOINTS];
        int n = bfs(sx, sy, nx, ny, cand, MAX_WAYPOINTS);
        if (n > 0 && (best_n == 0 || n < best_n)) {
            best_n = n;
            memcpy(best, cand, sizeof(int) * (size_t)n);
        }
        if (nx == sx && ny == sy) { best_n = 1; best[0] = ny * GAME_MAP_W + nx; break; }
    }
    if (best_n == 0) return 0;
    memcpy(path, best, sizeof(int) * (size_t)best_n);
    return best_n;
}

/* ---- scripted courier --------------------------------------------------- */
typedef struct {
    int goal;
    int path[MAX_WAYPOINTS];
    int path_len;
    int path_pos;
    int stuck;
    int last_x, last_y;
    int press_cooldown;
    int dialog_wait;
} bot_t;

static void bot_reset(bot_t *b)
{
    b->goal = 0;
    b->path_len = 0;
    b->path_pos = 0;
    b->stuck = 0;
    b->last_x = -1;
    b->last_y = -1;
    b->press_cooldown = 0;
    b->dialog_wait = 0;
}

static void face_target(int tx, int ty)
{
    int px = g.player.x + GAME_SPRITE_W / 2;
    int py = g.player.y + GAME_SPRITE_H / 2;
    int dx = tx * GAME_TILE_W + GAME_TILE_W / 2 - px;
    int dy = ty * GAME_TILE_H + GAME_TILE_H / 2 - py;
    if (dx < 0) dx = -dx;
    if (dy < 0) dy = -dy;
    if (dx >= dy)
        g.player.dir = (tx * GAME_TILE_W + 10 > px) ? DIR_RIGHT : DIR_LEFT;
    else
        g.player.dir = (ty * GAME_TILE_H + 10 > py) ? DIR_DOWN : DIR_UP;
}

static uint8_t bot_step(bot_t *b)
{
    uint8_t level = 0;

    if (g.state == GS_TITLE) return (g.frames % 12 == 0) ? BTN_A : 0;

    if (g.state == GS_DIALOG) {
        b->dialog_wait++;
        return (b->dialog_wait % 14 == 0) ? BTN_A : 0;
    }

    if (g.state == GS_WIN) return 0;

    /* GS_PLAY */
    if (b->goal >= GOAL_COUNT) return 0;

    if (b->path_len == 0 || b->path_pos >= b->path_len) {
        if (b->path_len > 0) {
            /* arrived next to the target: face it and interact */
            face_target(GOALS[b->goal].tx, GOALS[b->goal].ty);
            b->press_cooldown++;
            if (b->press_cooldown > 2) {
                b->press_cooldown = 0;
                b->goal++;
                b->path_len = 0;
                b->path_pos = 0;
            }
            return BTN_A;
        }
        b->path_len = plan_to(GOALS[b->goal].tx, GOALS[b->goal].ty, b->path);
        b->path_pos = 0;
        if (b->path_len == 0) {
            b->goal++;
            return 0;
        }
        return 0;
    }

    if (g.player.x == b->last_x && g.player.y == b->last_y) b->stuck++;
    else b->stuck = 0;
    b->last_x = g.player.x;
    b->last_y = g.player.y;
    if (b->stuck > 90) {
        b->path_len = 0;
        b->path_pos = 0;
        b->stuck = 0;
        return 0;
    }

    int cell = b->path[b->path_pos];
    int wx = cell % GAME_MAP_W, wy = cell / GAME_MAP_W;
    int target_x = wx * GAME_TILE_W + 2;
    int target_y = wy * GAME_TILE_H;
    int dx = target_x - g.player.x;
    int dy = target_y - g.player.y;

    if (dx > 1) level = BTN_RIGHT;
    else if (dx < -1) level = BTN_LEFT;
    else if (dy > 1) level = BTN_DOWN;
    else if (dy < -1) level = BTN_UP;
    else b->path_pos++;
    return level;
}

int main(int argc, char **argv)
{
    const char *dump_dir = ".";
    int max_frames = 4000;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--dump-dir") && i + 1 < argc) dump_dir = argv[++i];
        else if (!strcmp(argv[i], "--frames") && i + 1 < argc) max_frames = atoi(argv[++i]);
    }

    hal_init();
    game_init(&g, 0);

    uint16_t *b0 = hal_fb(0), *b1 = hal_fb(1);
    game_render_full(&g, b0);
    hal_present(b0);
    hal_wait_active(b0);
    game_render_full(&g, b1);
    g.redraw_all = 0;   /* both buffers already hold the initial title */

    bot_t bot;
    bot_reset(&bot);
    int front = 0;
    int last_shards = -1;
    int last_state = -1;
    char path[512];

    snprintf(path, sizeof(path), "%s/host_000_title.ppm", dump_dir);
    hal_host_dump(path);

    for (int frame = 0; frame < max_frames; frame++) {
        uint16_t *back = front ? b0 : b1;
        uint8_t level = bot_step(&bot);
        host_set_buttons(level);

        uint8_t pressed = hal_buttons_pressed();
        game_frame(&g, pressed, level, hal_now_ms(), back);
        hal_present(back);
        hal_wait_active(back);
        front ^= 1;

        if (g.state != last_state) {
            last_state = g.state;
            if (g.state == GS_DIALOG || g.state == GS_PLAY) {
                snprintf(path, sizeof(path), "%s/host_f%04d_state%d.ppm",
                         dump_dir, frame, g.state);
                hal_host_dump(path);
            }
        }
        if ((int)g.shards != last_shards) {
            last_shards = g.shards;
            snprintf(path, sizeof(path), "%s/host_f%04d_shard%d.ppm",
                     dump_dir, frame, g.shards);
            hal_host_dump(path);
        }
        if (g.state == GS_WIN) {
            snprintf(path, sizeof(path), "%s/host_f%04d_win.ppm", dump_dir, frame);
            hal_host_dump(path);
            printf("WIN frame=%d time=%u ms shards=%u\n", frame, g.elapsed_ms, g.shards);
            return 0;
        }
    }

    snprintf(path, sizeof(path), "%s/host_last.ppm", dump_dir);
    hal_host_dump(path);
    printf("NO WIN state=%d shards=%u goal=%d frame=%d\n",
           g.state, g.shards, bot.goal, max_frames);
    return 1;
}
