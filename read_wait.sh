#!/bin/bash
F=~/zephyr_git/pic64gx-zephyr/demos/pic64_smp_hello/src/screen_game.c
echo "=== enter_wait / WAIT text ==="
grep -n "FLAPPY MICROCHIP\|Press JUMP\|enter_wait\|status_show" "$F"
echo ""
echo "=== status panel layout ==="
grep -n "status_panel\|status_lbl\|sub_lbl\|set_size\|LV_ALIGN\|font_montserrat\|score_lbl\|player" "$F" | head -50
echo ""
echo "=== initial py (player start Y) ==="
grep -n "py    =\|py =\|py=" "$F"
