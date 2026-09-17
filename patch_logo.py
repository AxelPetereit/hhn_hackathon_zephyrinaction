#!/usr/bin/env python3

path = "/home/m77107/zephyr_git/pic64gx-zephyr/demos/pic64_smp_hello/src/screen_game.c"

with open(path) as f:
    src = f.read()

# 1. Add logo include after the existing includes
src = src.replace(
    '#include "vdma_disp.h"', '#include "vdma_disp.h"\n#include "microchip_logo_img.h"'
)

# 2. Replace the old player lv_obj block (red rect + M label) with lv_image
old_player = """\t/* ── Player: Microchip logo (red rounded rect + white M) ─────────── */
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

new_player = """\t/* ── Player: Microchip logo image (ARGB8888, pre-baked rounded corners) */
\tplayer_obj = lv_image_create(scr);
\tlv_image_set_src(player_obj, &microchip_logo_img);
\tlv_obj_set_style_bg_opa(player_obj, LV_OPA_TRANSP, 0);
\tlv_obj_set_style_border_width(player_obj, 0, 0);
\tlv_obj_set_style_pad_all(player_obj, 0, 0);"""

if old_player in src:
    src = src.replace(old_player, new_player)
    print("Player block replaced OK")
else:
    print("ERROR: player block not found - check indentation")
    # Print surrounding context to debug
    idx = src.find("Player: Microchip logo")
    if idx >= 0:
        print("Found partial match at:", idx)
        print(repr(src[idx - 5 : idx + 200]))

with open(path, "w") as f:
    f.write(src)
print("Done")
