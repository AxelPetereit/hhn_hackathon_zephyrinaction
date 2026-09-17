#!/usr/bin/env python3
"""
Patch original pic64gx-zephyr repo:
  1. demo_manager.c : start in game, restart after game over
  2. screen_game.c  : replace M-box with Microchip logo (RGB565, no alpha overhead)
  3. CMakeLists.txt : add microchip_logo_img.c
  4. Generate microchip_logo_img.c/h as RGB565 (corners tinted with sky colour)
"""

from PIL import Image, ImageDraw
import os, sys

BASE = "/home/m77107/zephyr_git/pic64gx-zephyr/demos/pic64_smp_hello"
SRC = BASE + "/src"

# ── 1. demo_manager.c ─────────────────────────────────────────────────────────
dm = SRC + "/demo_manager.c"
with open(dm) as f:
    src = f.read()

src = src.replace(
    "\t/* Load initial screen */\n\tload_screen(0);",
    "\t/* Start directly in Flappy Bird */\n\tin_game_mode = true;\n\tload_game_screen();",
)
# Remove the game→HUD reload block entirely. Game restarts in place
# (screen_game GAME_OVER handles SW2), so demo_manager never leaves game mode.
# This avoids the timer-clobbering race from reloading the game screen.
src = src.replace(
    "\t\tif (in_game_mode && screen_game_is_done()) {\n"
    "\t\t\tin_game_mode = false;\n"
    "\t\t\tload_screen(0);  /* back to HUD */\n"
    "\t\t\tnext_switch = now + CYCLE_MS;\n"
    "\t\t}",
    "\t\t/* Game restarts itself in place (screen_game GAME_OVER handles SW2).\n"
    "\t\t * We never leave game mode, so no reload logic is needed here. */",
)
with open(dm, "w") as f:
    f.write(src)
print("demo_manager.c patched")

# ── 2. Generate microchip_logo_img.c/h as RGB565 ──────────────────────────────
C_SKY_R, C_SKY_G, C_SKY_B = 0x0D, 0x11, 0x17  # sky background colour

img = Image.open("/mnt/c/developers/Zephyr_HelloFPGA/microchip_logo.png").convert("RGB")
img = img.resize((44, 44), Image.LANCZOS)

# Rounded corner mask
mask = Image.new("L", (44, 44), 0)
draw = ImageDraw.Draw(mask)
draw.rounded_rectangle([0, 0, 43, 43], radius=8, fill=255)

pix = img.load()
data = bytearray()
for y in range(44):
    for x in range(44):
        r, g, b = pix[x, y]
        if mask.getpixel((x, y)) == 0:
            r, g, b = C_SKY_R, C_SKY_G, C_SKY_B  # corner → sky colour
        rgb565 = ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3)
        data += bytes([rgb565 & 0xFF, rgb565 >> 8])  # little-endian

hex_lines = [
    "    " + ", ".join(f"0x{b:02X}" for b in data[i : i + 16]) + ","
    for i in range(0, len(data), 16)
]

c_src = f"""\
/* SPDX-License-Identifier: Apache-2.0
 * Auto-generated — do not edit.
 * LVGL v9 RGB565 image, 44x44 px, rounded corners r=8, corners = C_SKY.
 */
#include "microchip_logo_img.h"

static const uint8_t logo_data[{len(data)}] = {{
{chr(10).join(hex_lines)}
}};

const lv_image_dsc_t microchip_logo_img = {{
    .header = {{
        .magic      = LV_IMAGE_HEADER_MAGIC,
        .cf         = LV_COLOR_FORMAT_RGB565,
        .flags      = 0,
        .w          = 44,
        .h          = 44,
        .stride     = 88u,
        .reserved_2 = 0,
    }},
    .data_size  = {len(data)}u,
    .data       = logo_data,
    .reserved   = NULL,
    .reserved_2 = NULL,
}};
"""

h_src = """\
/* SPDX-License-Identifier: Apache-2.0 — auto-generated */
#ifndef MICROCHIP_LOGO_IMG_H
#define MICROCHIP_LOGO_IMG_H
#include <lvgl.h>
extern const lv_image_dsc_t microchip_logo_img;
#endif
"""

with open(SRC + "/microchip_logo_img.c", "w") as f:
    f.write(c_src)
with open(SRC + "/microchip_logo_img.h", "w") as f:
    f.write(h_src)
print(f"Logo RGB565 generated: {len(data)} bytes")

# ── 3. screen_game.c — replace player block ───────────────────────────────────
sg = SRC + "/screen_game.c"
with open(sg) as f:
    src = f.read()

# Add header include
src = src.replace(
    "#include <lvgl.h>",
    '#include <lvgl.h>\n#include "microchip_logo_img.h"',
    1,  # only first occurrence
)

# Replace the original M-box player block (exact text from original repo)
old_player = (
    '\t/* ── Player: 44×44 Microchip red rounded rectangle with bold white "M" label. */\n'
    "\tplayer_obj = lv_obj_create(scr);\n"
    "\tlv_obj_set_size(player_obj, PLAYER_SZ, PLAYER_SZ);\n"
    "\tlv_obj_set_style_bg_color(player_obj, lv_color_hex(C_MC_RED), LV_PART_MAIN);\n"
    "\tlv_obj_set_style_bg_opa(player_obj, LV_OPA_COVER, LV_PART_MAIN);\n"
    "\tlv_obj_set_style_border_width(player_obj, 0, LV_PART_MAIN);\n"
    "\tlv_obj_set_style_radius(player_obj, 8, LV_PART_MAIN);\n"
    "\tlv_obj_set_style_pad_all(player_obj, 0, LV_PART_MAIN);\n"
    "\tlv_obj_set_scrollbar_mode(player_obj, LV_SCROLLBAR_MODE_OFF);\n"
    "\n"
    "\tlv_obj_t *m_lbl = lv_label_create(player_obj);\n"
    "\n"
    '\tlv_label_set_text(m_lbl, "M");\n'
    "\tlv_obj_set_style_text_font(m_lbl, &lv_font_montserrat_32, LV_PART_MAIN);\n"
    "\tlv_obj_set_style_text_color(m_lbl, lv_color_white(), LV_PART_MAIN);\n"
    "\tlv_obj_align(m_lbl, LV_ALIGN_CENTER, 0, 0);"
)

new_player = (
    "\t/* ── Player: Microchip logo (RGB565, rounded corners) ───────────── */\n"
    "\tplayer_obj = lv_image_create(scr);\n"
    "\tlv_image_set_src(player_obj, &microchip_logo_img);\n"
    "\tlv_obj_set_style_bg_opa(player_obj, LV_OPA_TRANSP, 0);\n"
    "\tlv_obj_set_style_border_width(player_obj, 0, 0);\n"
    "\tlv_obj_set_style_pad_all(player_obj, 0, 0);"
)

if old_player in src:
    src = src.replace(old_player, new_player)
    print("screen_game.c: player replaced OK")
else:
    # Fallback: search without the first comment line
    old_player2 = (
        "\tplayer_obj = lv_obj_create(scr);\n"
        "\tlv_obj_set_size(player_obj, PLAYER_SZ, PLAYER_SZ);\n"
        "\tlv_obj_set_style_bg_color(player_obj, lv_color_hex(C_MC_RED), LV_PART_MAIN);\n"
        "\tlv_obj_set_style_bg_opa(player_obj, LV_OPA_COVER, LV_PART_MAIN);\n"
        "\tlv_obj_set_style_border_width(player_obj, 0, LV_PART_MAIN);\n"
        "\tlv_obj_set_style_radius(player_obj, 8, LV_PART_MAIN);\n"
        "\tlv_obj_set_style_pad_all(player_obj, 0, LV_PART_MAIN);\n"
        "\tlv_obj_set_scrollbar_mode(player_obj, LV_SCROLLBAR_MODE_OFF);\n"
        "\n"
        "\tlv_obj_t *m_lbl = lv_label_create(player_obj);\n"
        "\n"
        '\tlv_label_set_text(m_lbl, "M");\n'
        "\tlv_obj_set_style_text_font(m_lbl, &lv_font_montserrat_32, LV_PART_MAIN);\n"
        "\tlv_obj_set_style_text_color(m_lbl, lv_color_white(), LV_PART_MAIN);\n"
        "\tlv_obj_align(m_lbl, LV_ALIGN_CENTER, 0, 0);"
    )
    if old_player2 in src:
        src = src.replace(old_player2, new_player)
        print("screen_game.c: player replaced OK (fallback)")
    else:
        print("ERROR: player block not found! Searching for context...")
        idx = src.find("lv_obj_create(scr)")
        if idx >= 0:
            print(repr(src[max(0, idx - 100) : idx + 400]))
        sys.exit(1)

with open(sg, "w") as f:
    f.write(src)

# ── 4. CMakeLists.txt ─────────────────────────────────────────────────────────
cmake = BASE + "/CMakeLists.txt"
with open(cmake) as f:
    c = f.read()
if "microchip_logo_img.c" not in c:
    c = c.replace(
        "    src/screen_game.c", "    src/microchip_logo_img.c\n    src/screen_game.c"
    )
    with open(cmake, "w") as f:
        f.write(c)
    print("CMakeLists.txt: logo source added")

# ── 5. screen_game.c — GAME_OVER restarts the game IN PLACE ──────────────────
# SW2 (flap) calls enter_wait() on the same screen. No screen reload, so the
# single static game_timer is never clobbered by a second create/delete cycle.
with open(sg) as f:
    src = f.read()
old_over = (
    "\tcase GAME_OVER:\n"
    "\t\t/* Return after 3 s or on SW1 press */\n"
    "\t\t{\n"
    "\t\t\tint64_t elapsed = k_uptime_get() - over_time_ms;\n"
    "\n"
    "\t\t\tif (elapsed >= 3000 || enter) {\n"
    "\t\t\t\tgame_done = true;\n"
    "\t\t\t}\n"
    "\t\t}\n"
    "\t\tbreak;"
)
new_over = (
    "\tcase GAME_OVER:\n"
    "\t\t/* SW2 (flap) restarts the game IN PLACE — same screen, same\n"
    "\t\t * timer. No screen reload, so no timer-clobbering race. */\n"
    "\t\tif (flap) {\n"
    "\t\t\tenter_wait();\n"
    "\t\t}\n"
    "\t\tbreak;"
)
if old_over in src:
    src = src.replace(old_over, new_over)
    print("screen_game.c: GAME_OVER restarts in place")
else:
    print("WARN: GAME_OVER block not matched in apply_all")
with open(sg, "w") as f:
    f.write(src)

# ── 6. screen_game.c — fix button race (eager init in screen_game_create) ────
with open(sg) as f:
    src = f.read()
old_init = "\tgame_done   = false;\n\tbtn_inited  = false;"
new_init = (
    "\tgame_done        = false;\n"
    "\tif (gpio_is_ready_dt(&btn_flap)) {\n"
    "\t\tgpio_pin_configure_dt(&btn_flap, GPIO_INPUT);\n"
    "\t}\n"
    "\tif (gpio_is_ready_dt(&btn_enter)) {\n"
    "\t\tgpio_pin_configure_dt(&btn_enter, GPIO_INPUT);\n"
    "\t}\n"
    "\tprev_flap_state  = gpio_pin_get_dt(&btn_flap);\n"
    "\tprev_enter_state = gpio_pin_get_dt(&btn_enter);\n"
    "\tbtn_inited       = true;"
)
if old_init in src:
    src = src.replace(old_init, new_init)
    print("screen_game.c: button race condition fixed")
with open(sg, "w") as f:
    f.write(src)

# ── 7. screen_game.c — progressive speed-up per passed pipe ──────────────────
with open(sg) as f:
    src = f.read()
src = src.replace(
    "#define SCROLL_SPD  4.00f",
    "#define SCROLL_SPD  4.00f   /* initial scroll speed */\n"
    "#define SPEED_STEP  0.35f   /* added per passed pipe */\n"
    "#define SPEED_MAX  12.00f   /* speed cap */",
)
src = src.replace(
    "static int          score;\nstatic int          best_score;",
    "static int          score;\nstatic int          best_score;\n"
    "static float        scroll_spd;   /* current scroll speed, ramps up per pipe */",
)
src = src.replace(
    "\tpy    = 300.0f;\n\tvy    = 0.0f;\n\tscore = 0;",
    "\tpy    = 300.0f;\n\tvy    = 0.0f;\n\tscore = 0;\n\tscroll_spd = SCROLL_SPD;",
)
src = src.replace("\t\t\tpipe_x[i] -= SCROLL_SPD;", "\t\t\tpipe_x[i] -= scroll_spd;")
src = src.replace(
    "\t\t\tif (!scored[i] && centre < PLAYER_X) {\n"
    "\t\t\t\tscored[i] = true;\n"
    "\t\t\t\tscore++;\n"
    "\t\t\t\tscore_update();\n"
    "\t\t\t}",
    "\t\t\tif (!scored[i] && centre < PLAYER_X) {\n"
    "\t\t\t\tscored[i] = true;\n"
    "\t\t\t\tscore++;\n"
    "\t\t\t\tscore_update();\n"
    "\t\t\t\t/* Speed up a little after each pipe, up to the cap */\n"
    "\t\t\t\tscroll_spd += SPEED_STEP;\n"
    "\t\t\t\tif (scroll_spd > SPEED_MAX) {\n"
    "\t\t\t\t\tscroll_spd = SPEED_MAX;\n"
    "\t\t\t\t}\n"
    "\t\t\t}",
)
with open(sg, "w") as f:
    f.write(src)
print("screen_game.c: progressive speed-up added")

# ── 8. screen_game.c — larger pipe gap (kid-friendly) ────────────────────────
with open(sg) as f:
    src = f.read()
src = src.replace(
    "#define GAP_H         180",
    "#define GAP_H         280   /* larger gap = easier for kids */",
)
with open(sg, "w") as f:
    f.write(src)
print("screen_game.c: pipe gap widened to 280px")

print("\nAll done. Ready to build.")
