#!/usr/bin/env python3
"""
Pixel-accurate reconstruction of the Flappy Bird WAIT (start) screen.
All layout constants, colours, RNG seeds and text taken verbatim from
screen_game.c so the render matches what the board draws.
"""

from PIL import Image, ImageDraw, ImageFont


# ── Colours (from screen_game.c) ─────────────────────────────────────────────
def rgb(hexv):
    return ((hexv >> 16) & 0xFF, (hexv >> 8) & 0xFF, hexv & 0xFF)


C_SKY = rgb(0x0D1117)
C_GROUND = rgb(0x3D2B1F)
C_GROUND_H = rgb(0x6B4423)
C_PIPE = rgb(0x3FB950)
C_PIPE_CAP = rgb(0x2D8A3A)
C_MC_RED = rgb(0xC0392B)
C_WHITE = rgb(0xE6EDF3)
C_SUBTLE = rgb(0x8B949E)
C_OVERLAY = rgb(0x161B22)

# ── Layout constants ─────────────────────────────────────────────────────────
SCR_W, SCR_H = 1280, 720
PLAYER_X, PLAYER_SZ = 160, 44
PIPE_W, PIPE_CAP_H = 80, 18
GAP_H = 180
PIPE_SPACING = 430
N_PIPES = 3
GROUND_Y, GROUND_H = 672, 48
GAP_MIN = GAP_H // 2 + 50
GAP_MAX = GROUND_Y - GAP_H // 2 - 50
N_STARS = 20
PY_START = 300  # player Y in WAIT state (py = 300.0f)

FONT_DIR = "/home/m77107/zephyr/modules/lib/gui/lvgl/scripts/built_in_font"
FONT_MED = FONT_DIR + "/Montserrat-Medium.ttf"

img = Image.new("RGB", (SCR_W, SCR_H), C_SKY)
draw = ImageDraw.Draw(img, "RGBA")


# ── Stars (xorshift seed 0xCAFEBABE, exactly as in screen_game_create) ───────
def xorshift32(x):
    x ^= (x << 13) & 0xFFFFFFFF
    x ^= x >> 17
    x ^= (x << 5) & 0xFFFFFFFF
    return x & 0xFFFFFFFF


star_rng = 0xCAFEBABE
for i in range(N_STARS):
    star_rng = xorshift32(star_rng)
    sx = star_rng % SCR_W
    star_rng = xorshift32(star_rng)
    sy = star_rng % (GROUND_Y - 20)
    sz = 4 if (i % 3 == 0) else 3
    # stars are white at 60% opacity, circular
    draw.ellipse([sx, sy, sx + sz, sy + sz], fill=(255, 255, 255, 153))

# ── Ground + highlight strip ─────────────────────────────────────────────────
draw.rectangle([0, GROUND_Y, SCR_W, GROUND_Y + GROUND_H], fill=C_GROUND)
draw.rectangle([0, GROUND_Y, SCR_W, GROUND_Y + 4], fill=C_GROUND_H)

# ── Pipes (xorshift seed 0xDEADBEEF for gap centres, as rand_gap_cy) ─────────
pipe_rng = 0xDEADBEEF


def rand_gap_cy():
    global pipe_rng
    pipe_rng = xorshift32(pipe_rng)
    return GAP_MIN + (pipe_rng % (GAP_MAX - GAP_MIN))


# pipe_reset called with x = SCR_W + i*PIPE_SPACING, in order i=0,1,2
pipes = []
for i in range(N_PIPES):
    x = SCR_W + i * PIPE_SPACING
    gap_cy = rand_gap_cy()
    pipes.append((x, gap_cy))


def draw_pipe(x, gap_cy):
    top_h = gap_cy - GAP_H // 2
    bot_y = gap_cy + GAP_H // 2
    bot_h = GROUND_Y - bot_y
    # Top body
    if top_h > PIPE_CAP_H:
        draw.rectangle([x, 0, x + PIPE_W, top_h - PIPE_CAP_H], fill=C_PIPE)
    # Top cap (wider)
    if top_h > 0:
        draw.rectangle(
            [x - 5, top_h - PIPE_CAP_H, x - 5 + PIPE_W + 10, top_h], fill=C_PIPE_CAP
        )
    # Bottom cap
    if bot_h > 0:
        draw.rectangle(
            [x - 5, bot_y, x - 5 + PIPE_W + 10, bot_y + PIPE_CAP_H], fill=C_PIPE_CAP
        )
    # Bottom body
    if bot_h > PIPE_CAP_H:
        draw.rectangle([x, bot_y + PIPE_CAP_H, x + PIPE_W, GROUND_Y], fill=C_PIPE)


for x, gap_cy in pipes:
    if x < SCR_W:  # only draw pipes visible on screen
        draw_pipe(x, gap_cy)

# ── Player: Microchip logo with rounded corners, at (PLAYER_X, PY_START) ─────
logo = Image.open("/mnt/c/developers/Zephyr_HelloFPGA/microchip_logo.png").convert(
    "RGBA"
)
logo = logo.resize((PLAYER_SZ, PLAYER_SZ), Image.LANCZOS)
# rounded corner mask r=8 (matches the sprite baked into the game)
mask = Image.new("L", (PLAYER_SZ, PLAYER_SZ), 0)
ImageDraw.Draw(mask).rounded_rectangle(
    [0, 0, PLAYER_SZ - 1, PLAYER_SZ - 1], radius=8, fill=255
)
logo.putalpha(mask)
img.paste(logo, (PLAYER_X, PY_START), logo)

# ── Score "0" top-center (Montserrat 48, white, y offset 12) ─────────────────
f_score = ImageFont.truetype(FONT_MED, 48)
score_txt = "0"
bb = draw.textbbox((0, 0), score_txt, font=f_score)
tw = bb[2] - bb[0]
draw.text(((SCR_W - tw) // 2 - bb[0], 12), score_txt, font=f_score, fill=C_WHITE)

# ── Status panel: 700x150 centered, C_OVERLAY 80% opa, red border r=10 ───────
panel_w, panel_h = 700, 150
px = (SCR_W - panel_w) // 2
py = (SCR_H - panel_h) // 2
# 80% opacity overlay
draw.rounded_rectangle(
    [px, py, px + panel_w, py + panel_h],
    radius=10,
    fill=(C_OVERLAY[0], C_OVERLAY[1], C_OVERLAY[2], 204),
    outline=C_MC_RED,
    width=2,
)

# Main label "FLAPPY MICROCHIP" (Montserrat 32, red, y offset -22 from center)
f_main = ImageFont.truetype(FONT_MED, 32)
main_txt = "FLAPPY MICROCHIP"
bb = draw.textbbox((0, 0), main_txt, font=f_main)
tw = bb[2] - bb[0]
cx = SCR_W // 2
cy = SCR_H // 2
draw.text(
    (cx - tw // 2 - bb[0], cy - 22 - (bb[3] - bb[1]) // 2 - bb[1]),
    main_txt,
    font=f_main,
    fill=C_MC_RED,
)

# Sub label "Press JUMP (SW2) to start" (Montserrat 20, subtle, y offset +20)
f_sub = ImageFont.truetype(FONT_MED, 20)
sub_txt = "Press JUMP (SW2) to start"
bb = draw.textbbox((0, 0), sub_txt, font=f_sub)
tw = bb[2] - bb[0]
draw.text(
    (cx - tw // 2 - bb[0], cy + 20 - (bb[3] - bb[1]) // 2 - bb[1]),
    sub_txt,
    font=f_sub,
    fill=C_SUBTLE,
)

out = "/mnt/c/developers/Zephyr_HelloFPGA/flappy_startscreen.png"
img.save(out)
print(f"Saved: {out}")
print(f"Resolution: {SCR_W}x{SCR_H}")
print(f"Pipe positions (x, gap_cy): {pipes}")
