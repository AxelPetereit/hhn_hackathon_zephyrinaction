#!/usr/bin/env python3
"""
Apply three targeted changes to the original repo:
  1. demo_manager.c — start directly in game, restart on game-over (no demo return)
  2. screen_game.c  — replace red M-box with Microchip logo image
  3. CMakeLists.txt + prj.conf — add logo source + LV_USE_IMAGE
"""

BASE = "/home/m77107/zephyr_git/pic64gx-zephyr/demos/pic64_smp_hello"

# ── 1. demo_manager.c ─────────────────────────────────────────────────────────
dm = BASE + "/src/demo_manager.c"
with open(dm) as f:
    src = f.read()

# Start directly in Flappy Bird instead of loading screen 0
src = src.replace(
    "\t/* Load initial screen */\n\tload_screen(0);",
    "\t/* Start directly in Flappy Bird */\n\tin_game_mode = true;\n\tload_game_screen();",
)

# When game is done: restart game instead of returning to HUD
src = src.replace(
    "\t\tif (in_game_mode && screen_game_is_done()) {\n\t\t\tin_game_mode = false;\n\t\t\tload_screen(0);  /* back to HUD */\n\t\t\tnext_switch = now + CYCLE_MS;\n\t\t}",
    "\t\tif (in_game_mode && screen_game_is_done()) {\n\t\t\t/* Restart game — never return to demo */\n\t\t\tload_game_screen();\n\t\t\tnext_switch = now + CYCLE_MS;\n\t\t}",
)

with open(dm, "w") as f:
    f.write(src)
print("demo_manager.c patched")

# ── 2. screen_game.c — replace player widget ──────────────────────────────────
sg = BASE + "/src/screen_game.c"
with open(sg) as f:
    src = f.read()

# Add logo include after existing includes
src = src.replace(
    "#include <lvgl.h>", '#include <lvgl.h>\n#include "microchip_logo_img.h"'
)

# Replace the red lv_obj + M-label block with lv_image
old_player = """\t/* ── Player: 44×44 Microchip red rounded rectangle with bold white "M" label. */
\tplayer_obj = lv_obj_create(scr);
\tlv_obj_set_size(player_obj, PLAYER_SZ, PLAYER_SZ);
\tlv_obj_set_style_bg_color(player_obj, lv_color_hex(C_MC_RED), LV_PART_MAIN);
\tlv_obj_set_style_bg_opa(player_obj, LV_OPA_COVER, LV_PART_MAIN);
\tlv_obj_set_style_border_width(player_obj, 0, LV_PART_MAIN);
\tlv_obj_set_style_radius(player_obj, 8, LV_PART_MAIN);
\tlv_obj_set_style_pad_all(player_obj, 0, LV_PART_MAIN);
\tlv_obj_set_scrollbar_mode(player_obj, LV_SCROLLBAR_MODE_OFF);

\tlv_obj_t *m_lbl = lv_label_create(player_obj);

\tlv_label_set_text(m_lbl, "M");
\tlv_obj_set_style_text_font(m_lbl, &lv_font_montserrat_32, LV_PART_MAIN);
\tlv_obj_set_style_text_color(m_lbl, lv_color_white(), LV_PART_MAIN);
\tlv_obj_align(m_lbl, LV_ALIGN_CENTER, 0, 0);"""

if old_player not in src:
    # Try a shorter match
    old_player = """\tplayer_obj = lv_obj_create(scr);
\tlv_obj_set_size(player_obj, PLAYER_SZ, PLAYER_SZ);
\tlv_obj_set_style_bg_color(player_obj, lv_color_hex(C_MC_RED), LV_PART_MAIN);
\tlv_obj_set_style_bg_opa(player_obj, LV_OPA_COVER, LV_PART_MAIN);
\tlv_obj_set_style_border_width(player_obj, 0, LV_PART_MAIN);
\tlv_obj_set_style_radius(player_obj, 8, LV_PART_MAIN);
\tlv_obj_set_style_pad_all(player_obj, 0, LV_PART_MAIN);
\tlv_obj_set_scrollbar_mode(player_obj, LV_SCROLLBAR_MODE_OFF);

\tlv_obj_t *m_lbl = lv_label_create(player_obj);

\tlv_label_set_text(m_lbl, "M");
\tlv_obj_set_style_text_font(m_lbl, &lv_font_montserrat_32, LV_PART_MAIN);
\tlv_obj_set_style_text_color(m_lbl, lv_color_white(), LV_PART_MAIN);
\tlv_obj_align(m_lbl, LV_ALIGN_CENTER, 0, 0);"""

new_player = """\t/* ── Player: Microchip logo (ARGB8888, rounded corners) ─────────── */
\tplayer_obj = lv_image_create(scr);
\tlv_image_set_src(player_obj, &microchip_logo_img);
\tlv_obj_set_style_bg_opa(player_obj, LV_OPA_TRANSP, 0);
\tlv_obj_set_style_border_width(player_obj, 0, 0);
\tlv_obj_set_style_pad_all(player_obj, 0, 0);"""

if old_player in src:
    src = src.replace(old_player, new_player)
    print("screen_game.c: player replaced with logo")
else:
    print("ERROR: player block not found in screen_game.c")
    # show context to debug
    idx = src.find("lv_obj_create(scr)")
    print(f"  lv_obj_create found at: {idx}")
    print(repr(src[max(0, idx - 100) : idx + 300]))

with open(sg, "w") as f:
    f.write(src)

# ── 3. CMakeLists.txt + prj.conf ──────────────────────────────────────────────
cmake = BASE + "/CMakeLists.txt"
with open(cmake) as f:
    c = f.read()
if "microchip_logo_img.c" not in c:
    c = c.replace(
        "    src/screen_game.c", "    src/microchip_logo_img.c\n    src/screen_game.c"
    )
    with open(cmake, "w") as f:
        f.write(c)
    print("CMakeLists.txt: logo added")
else:
    print("CMakeLists.txt: logo already present")

prj = BASE + "/prj.conf"
with open(prj) as f:
    p = f.read()
if "CONFIG_LV_USE_IMAGE" not in p:
    p += "\nCONFIG_LV_USE_IMAGE=y\n"
    with open(prj, "w") as f:
        f.write(p)
    print("prj.conf: LV_USE_IMAGE added")
else:
    print("prj.conf: LV_USE_IMAGE already set")

print("Done.")
