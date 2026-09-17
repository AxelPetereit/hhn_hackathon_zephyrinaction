#!/usr/bin/env python3

BASE = "/home/m77107/zephyr_git/pic64gx-zephyr/demos/pic64_smp_hello"

# 1. screen_game.c: ersetze lv_image durch alten lv_obj Block
sg = BASE + "/src/screen_game.c"
with open(sg) as f:
    src = f.read()

src = src.replace('#include "microchip_logo_img.h"\n', "")

src = src.replace(
    """\t/* ── Player: Microchip logo image (ARGB8888, pre-baked rounded corners) */
\tplayer_obj = lv_image_create(scr);
\tlv_image_set_src(player_obj, &microchip_logo_img);
\tlv_obj_set_style_bg_opa(player_obj, LV_OPA_TRANSP, 0);
\tlv_obj_set_style_border_width(player_obj, 0, 0);
\tlv_obj_set_style_pad_all(player_obj, 0, 0);""",
    """\t/* ── Player: Microchip logo (red rounded rect + white M) ─────────── */
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
\tlv_obj_align(m_lbl, LV_ALIGN_CENTER, 0, 0);""",
)

with open(sg, "w") as f:
    f.write(src)
print("screen_game.c: logo reverted to M-box")

# 2. CMakeLists.txt: microchip_logo_img.c entfernen
cmake = BASE + "/CMakeLists.txt"
with open(cmake) as f:
    c = f.read()

c = c.replace("    src/microchip_logo_img.c\n", "")

with open(cmake, "w") as f:
    f.write(c)
print("CMakeLists.txt: microchip_logo_img.c removed")

# 3. prj.conf: CONFIG_LV_USE_IMAGE=y entfernen
prj = BASE + "/prj.conf"
with open(prj) as f:
    p = f.read()

p = p.replace("CONFIG_LV_USE_IMAGE=y\n", "")

with open(prj, "w") as f:
    f.write(p)
print("prj.conf: LV_USE_IMAGE removed")

print("Done.")
