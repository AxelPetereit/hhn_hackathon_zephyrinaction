#!/bin/bash
echo "=== game_tick_cb GAME_PLAY (should have _draw_bg_to, no pipe_erase loop) ==="
grep -n "_draw_bg_to\|pipe_erase\|frame_ready" \
  ~/zephyr_git/pic64gx-zephyr/demos/pic64_smp_hello/src/screen_game.c

echo ""
echo "=== demo_manager flip logic ==="
grep -n "flip\|frame_ready" \
  ~/zephyr_git/pic64gx-zephyr/demos/pic64_smp_hello/src/demo_manager.c
