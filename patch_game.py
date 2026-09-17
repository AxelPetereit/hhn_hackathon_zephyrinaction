#!/usr/bin/env python3
import re, sys

path = "/home/m77107/zephyr_git/pic64gx-zephyr/demos/pic64_smp_hello/src/screen_game.c"

with open(path) as f:
    src = f.read()

# 1. Reset both_hold_count in screen_game_create()
src = src.replace(
    "\tgame_done   = false;\n\tbtn_inited  = false;",
    "\tgame_done       = false;\n\tbtn_inited      = false;\n\tboth_hold_count = 0;",
)

# 2. Add both-buttons exit check after btn_init_once() in game_tick_cb
old_init = (
    "\tbtn_init_once();\n\n\tbool flap  = flap_edge();\n\tbool enter = enter_edge();"
)
new_init = """\tbtn_init_once();

\t/* Both SW1+SW2 held for 2 consecutive ticks (66 ms) -> exit to demo */
\tif (gpio_pin_get_dt(&btn_flap) == 1 &&
\t    gpio_pin_get_dt(&btn_enter) == 1) {
\t\tif (++both_hold_count >= 2) {
\t\t\tboth_hold_count = 0;
\t\t\tgame_done = true;
\t\t\treturn;
\t\t}
\t} else {
\t\tboth_hold_count = 0;
\t}

\tbool flap  = flap_edge();
\tbool enter = enter_edge();"""
src = src.replace(old_init, new_init)

# 3. Replace GAME_OVER block: remove 3s auto-exit and SW1-exit, add SW2 restart
old_over = """\tcase GAME_OVER:
\t\t/* Return after 3 s or on SW1 press */
\t\t{
\t\t\tint64_t elapsed = k_uptime_get() - over_time_ms;

\t\t\tif (elapsed >= 3000 || enter) {
\t\t\t\tgame_done = true;
\t\t\t}
\t\t}
\t\tbreak;"""
new_over = """\tcase GAME_OVER:
\t\t/* SW2 = restart; SW1+SW2 = exit (handled above) */
\t\tif (flap) {
\t\t\tenter_wait();
\t\t}
\t\tbreak;"""
src = src.replace(old_over, new_over)

# 4. Update hint text in enter_over(): "SW1 to exit" -> "SW1+SW2 to exit"
src = src.replace('"Best: %d   SW1 to exit"', '"Best: %d  SW1+SW2: exit"')

with open(path, "w") as f:
    f.write(src)

print("OK - all patches applied")
