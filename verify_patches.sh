#!/bin/bash
echo "=== screen_game.c ==="
grep -n "SCROLL_SPD\|both_hold_count\|SW1+SW2\|SW2 = restart\|both_hold" \
  ~/zephyr_git/pic64gx-zephyr/demos/pic64_smp_hello/src/screen_game.c

echo ""
echo "=== demo_manager.c ==="
grep -n "Start directly\|in_game_mode = true\|SW1+SW2\|load_game_screen" \
  ~/zephyr_git/pic64gx-zephyr/demos/pic64_smp_hello/src/demo_manager.c
