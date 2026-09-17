#!/usr/bin/env python3

path = "/home/m77107/zephyr_git/pic64gx-zephyr/demos/pic64_smp_hello/src/demo_manager.c"

with open(path) as f:
    src = f.read()

# 1. Start directly in game mode instead of loading screen 0
src = src.replace(
    "\t/* Load initial screen */\n\tload_screen(0);",
    "\t/* Start directly in Flappy Bird */\n\tin_game_mode = true;\n\tload_game_screen();",
)

# 2. Update overlay hint text: "SW1: EXIT" -> "SW1+SW2: EXIT" when in game
src = src.replace(
    'lv_label_set_text(game_hint, "SW1: EXIT");',
    'lv_label_set_text(game_hint, "SW1+SW2: EXIT");',
)

# 3. Update overlay hint text: "SW1: GAME" -> "SW1: GAME" (keep, shown in demo mode)
# Also update initial overlay hint to be empty (will be set on first update)
src = src.replace(
    'lv_label_set_text(game_hint, "SW1: GAME");\n\tlv_obj_set_style_text_font(game_hint',
    'lv_label_set_text(game_hint, "");\n\tlv_obj_set_style_text_font(game_hint',
)

# 4. Update comment about SW1 in game mode (cosmetic)
src = src.replace(
    "\t\t/* If in_game_mode, screen_game handles SW1 internally\n\t\t * (it returns to demo via screen_game_is_done() below). */",
    "\t\t/* If in_game_mode, exit is handled by SW1+SW2 in screen_game.\n\t\t * SW1 alone does nothing while in game. */",
)

with open(path, "w") as f:
    f.write(src)

print("OK - demo_manager patches applied")
