#!/usr/bin/env python3
sg = "/home/m77107/zephyr_git/pic64gx-zephyr/demos/pic64_smp_hello/src/screen_game.c"
with open(sg) as f:
    src = f.read()

# Replace lazy btn init with eager init in screen_game_create()
# so the old session's game_tick_cb can't overwrite our fresh state
old = "\tgame_done   = false;\n\tbtn_inited  = false;"
new = (
    "\tgame_done        = false;\n"
    "\t/* Configure buttons and seed edge-detection state immediately.\n"
    "\t * Setting btn_inited=true here prevents the OLD session's\n"
    "\t * game_tick_cb (still running during the 400 ms fade-out) from\n"
    "\t * calling btn_init_once() again and corrupting prev_flap_state. */\n"
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

if old in src:
    src = src.replace(old, new)
    print("OK - button race condition fixed")
else:
    print("ERROR: target not found")

with open(sg, "w") as f:
    f.write(src)
