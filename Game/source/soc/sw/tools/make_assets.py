#!/usr/bin/env python3
"""Generate every pixel-art asset used by rv32_soc_Game.

The art is original and produced procedurally, so the project carries no
third-party asset licence.  The script writes:

    sw/game/game_assets.c   C arrays compiled into the firmware
    sw/game/game_assets.h   declarations and geometry
    docs/assets/map_preview.png / tiles_preview.png   documentation previews

Everything is deterministic: re-running the script produces identical bytes.
"""
from __future__ import annotations

import os
import struct
import sys
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import pixelfont  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
OUT_C = ROOT / "sw" / "game" / "game_assets.c"
OUT_H = ROOT / "sw" / "game" / "game_assets.h"
OUT_DOC = ROOT / "docs" / "assets"

TILE = 20
MAP_W, MAP_H = 32, 18
SPR_W, SPR_H = 16, 20
TRANSPARENT = 0xF81F  # magenta key, never used as a real colour

# --------------------------------------------------------------------------
# tiny canvas
# --------------------------------------------------------------------------


class Img:
    def __init__(self, w: int, h: int, fill=None):
        self.w = w
        self.h = h
        self.px = [[fill for _ in range(w)] for _ in range(h)]

    def put(self, x: int, y: int, c):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[y][x] = c

    def rect(self, x0: int, y0: int, x1: int, y1: int, c):
        for y in range(y0, y1):
            for x in range(x0, x1):
                self.put(x, y, c)

    def hline(self, x0: int, x1: int, y: int, c):
        for x in range(x0, x1):
            self.put(x, y, c)

    def vline(self, x: int, y0: int, y1: int, c):
        for y in range(y0, y1):
            self.put(x, y, c)

    def blit(self, src: "Img", dx: int, dy: int):
        for y in range(src.h):
            for x in range(src.w):
                c = src.px[y][x]
                if c is not None:
                    self.put(dx + x, dy + y, c)


def rgb565(c) -> int:
    if c is None:
        return TRANSPARENT
    r, g, b = c
    return ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)


def mix(a, b, t: float):
    return tuple(int(a[i] * (1 - t) + b[i] * t) for i in range(3))


def h32(x: int, y: int, seed: int = 0) -> int:
    n = (x * 73856093) ^ (y * 19349663) ^ (seed * 83492791)
    n = (n ^ (n >> 13)) * 1274126177
    return (n ^ (n >> 16)) & 0x7FFFFFFF


# --------------------------------------------------------------------------
# palette
# --------------------------------------------------------------------------
GRASS = (0x4C, 0x8C, 0x4C)
GRASS_D = (0x3C, 0x74, 0x3E)
GRASS_L = (0x5F, 0xA0, 0x56)
PATH = (0xC7, 0xA6, 0x78)
PATH_D = (0xB2, 0x90, 0x62)
PATH_L = (0xD8, 0xBC, 0x90)
WATER = (0x3B, 0x6C, 0xB4)
WATER_L = (0x57, 0x8C, 0xCC)
TREE_D = (0x27, 0x5E, 0x35)
TREE_L = (0x37, 0x7F, 0x45)
TRUNK = (0x6A, 0x49, 0x2C)
ROOF = (0x9E, 0x3B, 0x2C)
ROOF_D = (0x7B, 0x2A, 0x1F)
WALL = (0xE3, 0xD2, 0xA8)
WALL_D = (0xC6, 0xB3, 0x87)
DOOR = (0x5A, 0x39, 0x22)
WINDOW = (0x7F, 0xB6, 0xD9)
SAND = (0xDE, 0xCD, 0x97)
SAND_D = (0xC8, 0xB5, 0x7E)
ROCK = (0x8C, 0x91, 0x9C)
ROCK_D = (0x6B, 0x71, 0x7D)
FENCE = (0x8A, 0x63, 0x3D)
FENCE_D = (0x6B, 0x4B, 0x2C)
FLOWER = (0xE0, 0x5C, 0x7A)
FLOWER_C = (0xF7, 0xD1, 0x54)
CHEST = (0xA5, 0x5C, 0x24)
CHEST_D = (0x7E, 0x44, 0x18)
GOLD = (0xF2, 0xC1, 0x4E)
SIGN = (0xB8, 0x8B, 0x55)
LT_RED = (0xD1, 0x4B, 0x3A)   # lighthouse stripes
LT_WHITE = (0xEC, 0xE6, 0xD8)
LT_GLASS = (0xFF, 0xE2, 0x8A)

# --------------------------------------------------------------------------
# tiles
# --------------------------------------------------------------------------
TILE_NAMES = [
    "grass", "path", "water", "tree", "wall", "roof", "door", "fence",
    "sand", "rock", "flower", "chest", "chest_open", "sign", "bridge", "goal",
]
# solid[type] = 1 blocks the player
TILE_SOLID = [0, 0, 1, 1, 1, 1, 0, 1, 0, 1, 0, 1, 1, 1, 0, 1]


def tile_grass() -> Img:
    t = Img(TILE, TILE)
    for y in range(TILE):
        for x in range(TILE):
            n = h32(x // 2, y // 2, 1) % 100
            t.put(x, y, GRASS if n > 12 else GRASS_D)
    for i in range(9):
        x = h32(i, 3, 7) % (TILE - 2)
        y = h32(i, 9, 5) % (TILE - 3)
        t.put(x, y, GRASS_L)
        t.put(x + 1, y, GRASS_L)
        t.put(x, y + 1, GRASS_D)
    return t


def tile_path() -> Img:
    t = Img(TILE, TILE)
    for y in range(TILE):
        for x in range(TILE):
            n = h32(x, y, 2) % 100
            t.put(x, y, PATH if n > 14 else PATH_D)
    for i in range(6):
        x = h32(i, 1, 11) % (TILE - 2)
        y = h32(i, 2, 13) % (TILE - 2)
        t.put(x, y, PATH_L)
        t.put(x + 1, y, PATH_L)
    return t


def tile_water() -> Img:
    t = Img(TILE, TILE)
    for y in range(TILE):
        for x in range(TILE):
            t.put(x, y, WATER if ((x + y) // 5) % 3 else WATER_L)
    for i in range(4):
        y = 3 + i * 5
        x0 = (i * 6 + 2) % (TILE - 8)
        t.hline(x0, x0 + 6, y, WATER_L)
    return t


def tile_tree() -> Img:
    t = Img(TILE, TILE, GRASS)
    for y in range(TILE):
        for x in range(TILE):
            n = h32(x // 2, y // 2, 3) % 100
            t.put(x, y, GRASS if n > 12 else GRASS_D)
    t.rect(8, 12, 12, 19, TRUNK)
    t.rect(7, 13, 8, 18, mix(TRUNK, (0, 0, 0), 0.2))
    # canopy
    for y in range(1, 13):
        half = 8 - abs(y - 7) // 2
        for x in range(10 - half, 10 + half):
            n = h32(x, y, 4) % 100
            t.put(x, y, TREE_L if n > 30 else TREE_D)
    for x in range(3, 17):
        t.put(x, 1, TREE_D)
    return t


def tile_wall() -> Img:
    t = Img(TILE, TILE, WALL)
    for x in range(TILE):
        t.put(x, 0, WALL_D)
        t.put(x, TILE - 1, WALL_D)
    for y in range(3, 15, 6):
        t.hline(0, TILE, y, WALL_D)
    t.rect(3, 4, 8, 8, WINDOW)
    t.rect(12, 4, 17, 8, WINDOW)
    t.rect(3, 4, 8, 5, mix(WINDOW, (255, 255, 255), 0.4))
    t.rect(12, 4, 17, 5, mix(WINDOW, (255, 255, 255), 0.4))
    return t


def tile_roof() -> Img:
    t = Img(TILE, TILE, ROOF)
    for y in range(0, TILE, 4):
        t.hline(0, TILE, y, ROOF_D)
        off = (y // 4) % 2
        for x in range(off * 3, TILE, 6):
            t.vline(x, y, min(y + 4, TILE), ROOF_D)
    t.hline(0, TILE, 0, mix(ROOF, (0, 0, 0), 0.25))
    return t


def tile_door() -> Img:
    t = tile_wall()
    t.rect(5, 5, 15, 19, DOOR)
    t.rect(5, 5, 6, 19, mix(DOOR, (0, 0, 0), 0.3))
    t.rect(6, 6, 14, 7, mix(DOOR, (255, 220, 160), 0.2))
    t.put(13, 12, GOLD)
    return t


def tile_fence() -> Img:
    t = Img(TILE, TILE, GRASS)
    for y in range(TILE):
        for x in range(TILE):
            n = h32(x // 2, y // 2, 3) % 100
            t.put(x, y, GRASS if n > 12 else GRASS_D)
    for x in (3, 16):
        t.vline(x, 4, 19, FENCE)
        t.vline(x + 1, 4, 19, FENCE_D)
    t.hline(2, 18, 8, FENCE)
    t.hline(2, 18, 9, FENCE_D)
    t.hline(2, 18, 14, FENCE)
    t.hline(2, 18, 15, FENCE_D)
    return t


def tile_sand() -> Img:
    t = Img(TILE, TILE)
    for y in range(TILE):
        for x in range(TILE):
            n = h32(x, y, 6) % 100
            t.put(x, y, SAND if n > 18 else SAND_D)
    for i in range(4):
        x = h32(i, 4, 21) % (TILE - 1)
        y = h32(i, 8, 22) % (TILE - 1)
        t.put(x, y, mix(SAND, (255, 255, 255), 0.35))
    return t


def tile_rock() -> Img:
    t = Img(TILE, TILE, GRASS)
    for y in range(TILE):
        for x in range(TILE):
            n = h32(x // 2, y // 2, 3) % 100
            t.put(x, y, GRASS if n > 12 else GRASS_D)
    t.rect(4, 8, 16, 19, ROCK)
    t.rect(3, 11, 5, 19, ROCK)
    t.rect(15, 11, 18, 19, ROCK)
    t.rect(4, 8, 16, 10, mix(ROCK, (255, 255, 255), 0.25))
    t.rect(6, 14, 9, 17, ROCK_D)
    return t


def tile_flower() -> Img:
    t = tile_grass()
    for (fx, fy) in ((5, 8), (12, 5), (9, 14)):
        t.put(fx, fy, FLOWER)
        t.put(fx + 1, fy, FLOWER)
        t.put(fx, fy + 1, FLOWER)
        t.put(fx + 1, fy + 1, FLOWER_C)
        t.put(fx, fy + 2, GRASS_D)
    return t


def tile_chest(open_: bool) -> Img:
    t = Img(TILE, TILE, GRASS)
    for y in range(TILE):
        for x in range(TILE):
            n = h32(x // 2, y // 2, 3) % 100
            t.put(x, y, GRASS if n > 12 else GRASS_D)
    if not open_:
        t.rect(3, 8, 17, 18, CHEST)
        t.rect(3, 8, 17, 10, CHEST_D)
        t.rect(9, 8, 11, 18, GOLD)
        t.rect(3, 12, 17, 14, CHEST_D)
        t.put(10, 13, GOLD)
    else:
        t.rect(3, 11, 17, 18, CHEST)
        t.rect(3, 11, 17, 12, CHEST_D)
        t.rect(2, 4, 18, 8, CHEST_D)
        t.rect(4, 13, 16, 17, (40, 24, 12))
        t.rect(8, 13, 12, 16, GOLD)
    return t


def tile_sign() -> Img:
    t = tile_grass()
    t.rect(9, 12, 11, 20, FENCE_D)
    t.rect(3, 5, 17, 13, SIGN)
    t.rect(3, 5, 17, 6, mix(SIGN, (255, 255, 255), 0.3))
    t.rect(4, 7, 16, 8, FENCE_D)
    t.rect(4, 9, 16, 10, FENCE_D)
    t.rect(4, 11, 11, 12, FENCE_D)
    return t


def tile_bridge() -> Img:
    t = Img(TILE, TILE, WATER)
    for x in range(TILE):
        for y in range(TILE):
            t.put(x, y, WATER if ((x + y) // 5) % 3 else WATER_L)
    for y in range(TILE):
        for x in range(2, TILE - 2):
            n = h32(x, y, 31) % 100
            t.put(x, y, (0x9A, 0x6E, 0x3E) if n > 25 else (0x84, 0x5C, 0x30))
    t.hline(2, TILE - 2, 0, (0x6B, 0x47, 0x24))
    t.hline(2, TILE - 2, TILE - 1, (0x6B, 0x47, 0x24))
    return t


def tile_goal() -> Img:
    """Lighthouse door: the goal tile."""
    t = Img(TILE, TILE)
    for y in range(TILE):
        for x in range(TILE):
            t.put(x, y, LT_WHITE if ((y // 5) % 2 == 0) else LT_RED)
    t.rect(4, 4, 16, 20, (0x2A, 0x2A, 0x33))
    t.rect(5, 5, 15, 20, (0x3B, 0x3B, 0x46))
    t.rect(7, 2, 13, 8, LT_GLASS)
    return t


TILE_FUNCS = [
    tile_grass, tile_path, tile_water, tile_tree, tile_wall, tile_roof,
    tile_door, tile_fence, tile_sand, tile_rock, tile_flower,
    lambda: tile_chest(False), lambda: tile_chest(True), tile_sign,
    tile_bridge, tile_goal,
]

# --------------------------------------------------------------------------
# characters
# --------------------------------------------------------------------------


def draw_hero(body, trim, hair, skin, satchel, dir_: str, step: int) -> Img:
    s = Img(SPR_W, SPR_H)
    # legs
    if step:
        s.rect(5, 16, 7, 20, (0x33, 0x2B, 0x24))
        s.rect(9, 15, 11, 20, (0x33, 0x2B, 0x24))
    else:
        s.rect(5, 16, 7, 19, (0x33, 0x2B, 0x24))
        s.rect(9, 16, 11, 19, (0x33, 0x2B, 0x24))
    # body
    s.rect(4, 9, 12, 17, body)
    s.rect(4, 9, 12, 10, trim)
    s.rect(4, 15, 12, 17, mix(body, (0, 0, 0), 0.2))
    # arms
    if step:
        s.rect(3, 10, 4, 15, body)
        s.rect(12, 11, 13, 16, body)
    else:
        s.rect(3, 11, 4, 16, body)
        s.rect(12, 10, 13, 15, body)
    # head
    s.rect(4, 2, 12, 9, skin)
    s.rect(4, 2, 12, 4, hair)
    if dir_ == "down":
        s.rect(4, 2, 12, 4, hair)
        s.put(6, 6, (0x22, 0x22, 0x2A)); s.put(7, 6, (0x22, 0x22, 0x2A))
        s.put(9, 6, (0x22, 0x22, 0x2A)); s.put(10, 6, (0x22, 0x22, 0x2A))
        s.rect(7, 8, 9, 9, mix(skin, (0, 0, 0), 0.25))
    elif dir_ == "up":
        s.rect(4, 2, 12, 8, hair)
    elif dir_ == "left":
        s.rect(4, 2, 12, 4, hair)
        s.rect(4, 2, 6, 9, hair)
        s.put(5, 6, (0x22, 0x22, 0x2A)); s.put(6, 6, (0x22, 0x22, 0x2A))
    else:
        s.rect(4, 2, 12, 4, hair)
        s.rect(10, 2, 12, 9, hair)
        s.put(9, 6, (0x22, 0x22, 0x2A)); s.put(10, 6, (0x22, 0x22, 0x2A))
    # satchel (courier)
    s.rect(11, 11, 15, 15, satchel)
    s.rect(11, 11, 15, 12, mix(satchel, (255, 255, 255), 0.2))
    # scarf
    s.rect(4, 8, 12, 9, trim)
    return s


def make_sprites():
    hero_body = (0x35, 0x62, 0xA8)
    hero_trim = (0xD9, 0x4B, 0x3B)
    hair = (0x3B, 0x2A, 0x1E)
    skin = (0xE8, 0xB9, 0x8E)
    satchel = (0x8A, 0x5A, 0x2E)
    dirs = ["down", "up", "left", "right"]
    player = []
    for d in dirs:
        frames = []
        for step in (0, 1):
            frames.append(draw_hero(hero_body, hero_trim, hair, skin, satchel, d, step))
        player.append(frames)

    npcs = []
    for (body, trim, hair_c) in (
        ((0x7A, 0x4C, 0x9E), (0xE0, 0xC0, 0x60), (0x5A, 0x3A, 0x22)),
        ((0x2E, 0x7F, 0x6E), (0xDD, 0xDD, 0xDD), (0x8A, 0x8A, 0x8A)),
        ((0xA8, 0x6A, 0x3A), (0x40, 0x50, 0x70), (0x2A, 0x2A, 0x2A)),
    ):
        npcs.append(draw_hero(body, trim, hair_c, skin, (0x6B, 0x4A, 0x2C), "down", 0))
    return player, npcs


# --------------------------------------------------------------------------
# map
# --------------------------------------------------------------------------
# The village is assembled from explicit rectangles so that coordinates stay
# readable and cannot drift by a character.  Legend:
#   0 grass 1 path 2 water 3 tree 4 wall 5 roof 6 door 7 fence 8 sand
#   9 rock 10 flower 11 chest 13 sign 14 bridge 15 lighthouse door (goal)
T_GRASS, T_PATH, T_WATER, T_TREE, T_WALL, T_ROOF, T_DOOR, T_FENCE = range(8)
T_SAND, T_ROCK, T_FLOWER, T_CHEST, T_CHEST_OPEN, T_SIGN, T_BRIDGE, T_GOAL = range(8, 16)

MAP_OPS = [
    # border forest
    ("rect", 0, 0, 32, 1, T_TREE),
    ("rect", 0, 17, 32, 18, T_TREE),
    ("rect", 0, 0, 1, 18, T_TREE),
    ("rect", 31, 0, 32, 18, T_TREE),
    # two decorative tree clumps
    ("rect", 15, 1, 17, 5, T_TREE),
    ("rect", 19, 12, 20, 14, T_TREE),
    # main road (horizontal) and village square path
    ("rect", 1, 9, 31, 10, T_PATH),
    ("rect", 4, 4, 5, 9, T_PATH),
    ("rect", 26, 9, 27, 15, T_PATH),
    ("rect", 13, 10, 14, 16, T_PATH),
    # pond with sand shore
    ("rect", 9, 5, 17, 9, T_SAND),
    ("rect", 10, 6, 16, 9, T_WATER),
    ("point", 9, 8, T_WATER),
    ("point", 16, 5, T_WATER),
    # house A: north-west
    ("rect", 2, 2, 8, 4, T_ROOF),
    ("rect", 2, 4, 8, 6, T_WALL),
    ("point", 4, 5, T_DOOR),
    ("point", 6, 5, T_SIGN),
    # house B: north-east
    ("rect", 23, 2, 29, 4, T_ROOF),
    ("rect", 23, 4, 29, 6, T_WALL),
    ("point", 25, 5, T_DOOR),
    # house C: south-west
    ("rect", 2, 12, 8, 14, T_ROOF),
    ("rect", 2, 14, 8, 16, T_WALL),
    ("point", 5, 15, T_DOOR),
    # lighthouse: stone tower with the goal door at the bottom
    ("rect", 27, 11, 30, 12, T_ROOF),
    ("rect", 27, 12, 30, 15, T_WALL),
    ("point", 28, 14, T_GOAL),
    # fences
    ("rect", 1, 11, 2, 12, T_FENCE),
    ("rect", 9, 11, 12, 12, T_FENCE),
    ("rect", 21, 11, 22, 12, T_FENCE),
    ("rect", 30, 16, 31, 17, T_FENCE),
    # bridge across the pond outlet
    ("rect", 12, 9, 14, 10, T_BRIDGE),
    # scattered decoration
    ("point", 3, 8, T_FLOWER),
    ("point", 11, 12, T_FLOWER),
    ("point", 18, 4, T_FLOWER),
    ("point", 22, 8, T_FLOWER),
    ("point", 6, 16, T_FLOWER),
    ("point", 24, 16, T_FLOWER),
    ("point", 18, 7, T_ROCK),
    ("point", 29, 7, T_ROCK),
    ("point", 7, 11, T_ROCK),
    # four chests, three of them hold a shard (see game_logic.c)
    ("point", 5, 7, T_CHEST),
    ("point", 21, 6, T_CHEST),
    ("point", 11, 15, T_CHEST),
    ("point", 25, 13, T_CHEST),
]


def build_map():
    grid = [[T_GRASS for _ in range(MAP_W)] for _ in range(MAP_H)]
    for op in MAP_OPS:
        if op[0] == "rect":
            _, x0, y0, x1, y1, t = op
            for y in range(y0, y1):
                for x in range(x0, x1):
                    grid[y][x] = t
        elif op[0] == "point":
            _, x, y, t = op
            grid[y][x] = t
        else:
            raise ValueError(op)
    return grid


# --------------------------------------------------------------------------
# PNG output (documentation only)
# --------------------------------------------------------------------------


def write_png(path: Path, img: Img):
    raw = bytearray()
    for y in range(img.h):
        raw.append(0)
        for x in range(img.w):
            c = img.px[y][x] or (0, 0, 0)
            raw += bytes(c)

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data +
                struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", img.w, img.h, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png)


# --------------------------------------------------------------------------
# emit C
# --------------------------------------------------------------------------


def emit_c(tiles, player, npcs, grid):
    lines = []
    lines.append("// Generated by sw/tools/make_assets.py -- do not edit.\n")
    lines.append("// Original pixel art, produced procedurally, no third-party assets.\n")
    lines.append('#include "game_assets.h"\n\n')

    def arr(name, ctype, values, per_line=12):
        out = [f"const {ctype} {name}[{len(values)}] = {{\n"]
        for i in range(0, len(values), per_line):
            chunk = ", ".join(str(v) for v in values[i:i + per_line])
            out.append("    " + chunk + ",\n")
        out.append("};\n\n")
        return "".join(out)

    lines.append("const uint16_t g_tiles[GAME_TILE_COUNT][GAME_TILE_PIXELS] = {\n")
    for t in tiles:
        flat = [rgb565(t.px[y][x]) for y in range(TILE) for x in range(TILE)]
        lines.append("    {\n")
        for i in range(0, len(flat), 10):
            lines.append("        " + ", ".join(str(v) for v in flat[i:i + 10]) + ",\n")
        lines.append("    },\n")
    lines.append("};\n\n")

    lines.append("const uint16_t g_player[4][2][GAME_SPRITE_PIXELS] = {\n")
    for d in range(4):
        lines.append("    {\n")
        for f in range(2):
            flat = [rgb565(player[d][f].px[y][x]) for y in range(SPR_H) for x in range(SPR_W)]
            lines.append("        {\n")
            for i in range(0, len(flat), 10):
                lines.append("            " + ", ".join(str(v) for v in flat[i:i + 10]) + ",\n")
            lines.append("        },\n")
        lines.append("    },\n")
    lines.append("};\n\n")

    lines.append("const uint16_t g_npc[GAME_NPC_SKINS][GAME_SPRITE_PIXELS] = {\n")
    for n in npcs:
        flat = [rgb565(n.px[y][x]) for y in range(SPR_H) for x in range(SPR_W)]
        lines.append("    {\n")
        for i in range(0, len(flat), 10):
            lines.append("        " + ", ".join(str(v) for v in flat[i:i + 10]) + ",\n")
        lines.append("    },\n")
    lines.append("};\n\n")

    font_rows = []
    for code in range(32, 127):
        ch = chr(code)
        rows = pixelfont.GLYPH_ROWS.get(ch.upper(), pixelfont.GLYPH_ROWS["?"])
        for r in rows:
            font_rows.append(int(r.replace("#", "1").replace(".", "0")[::-1], 2))
    lines.append(arr("g_font", "uint8_t", font_rows, 14))

    flat_map = [grid[y][x] for y in range(MAP_H) for x in range(MAP_W)]
    lines.append(arr("g_map", "uint8_t", flat_map, 16))
    lines.append(arr("g_tile_solid", "uint8_t", TILE_SOLID, 16))
    return "".join(lines)


def emit_h():
    return f"""// Generated by sw/tools/make_assets.py -- do not edit.
#ifndef GAME_ASSETS_H
#define GAME_ASSETS_H

#include <stdint.h>

#define GAME_TILE_W        {TILE}
#define GAME_TILE_H        {TILE}
#define GAME_TILE_PIXELS   {TILE * TILE}
#define GAME_TILE_COUNT    16
#define GAME_MAP_W         {MAP_W}
#define GAME_MAP_H         {MAP_H}
#define GAME_SPRITE_W      {SPR_W}
#define GAME_SPRITE_H      {SPR_H}
#define GAME_SPRITE_PIXELS {SPR_W * SPR_H}
#define GAME_NPC_SKINS     3
#define GAME_FONT_FIRST    32
#define GAME_FONT_COUNT    95
#define GAME_SPRITE_KEY    0xF81Fu

extern const uint16_t g_tiles[GAME_TILE_COUNT][GAME_TILE_PIXELS];
extern const uint16_t g_player[4][2][GAME_SPRITE_PIXELS];
extern const uint16_t g_npc[GAME_NPC_SKINS][GAME_SPRITE_PIXELS];
extern const uint8_t  g_font[GAME_FONT_COUNT * 7];
extern const uint8_t  g_map[GAME_MAP_W * GAME_MAP_H];
extern const uint8_t  g_tile_solid[GAME_TILE_COUNT];

/* tile indices, mirrored in TILE_NAMES of the generator */
enum {{
    TILE_GRASS = 0, TILE_PATH, TILE_WATER, TILE_TREE, TILE_WALL, TILE_ROOF,
    TILE_DOOR, TILE_FENCE, TILE_SAND, TILE_ROCK, TILE_FLOWER, TILE_CHEST,
    TILE_CHEST_OPEN, TILE_SIGN, TILE_BRIDGE, TILE_GOAL
}};

#endif
"""


def main() -> int:
    tiles = [f() for f in TILE_FUNCS]
    player, npcs = make_sprites()
    grid = build_map()
    OUT_C.parent.mkdir(parents=True, exist_ok=True)
    OUT_C.write_text(emit_c(tiles, player, npcs, grid), encoding="utf-8")
    OUT_H.write_text(emit_h(), encoding="utf-8")

    # documentation previews
    world = Img(MAP_W * TILE, MAP_H * TILE)
    for y in range(MAP_H):
        for x in range(MAP_W):
            world.blit(tiles[grid[y][x]], x * TILE, y * TILE)
    hero = player[0][0]
    world.blit(hero, 16 * TILE, 10 * TILE)
    write_png(OUT_DOC / "map_preview.png", world)

    sheet = Img(TILE * len(tiles), TILE)
    for i, t in enumerate(tiles):
        sheet.blit(t, i * TILE, 0)
    write_png(OUT_DOC / "tiles_preview.png", sheet)

    print(f"tiles={len(tiles)} map={MAP_W}x{MAP_H} c={OUT_C.stat().st_size} bytes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
