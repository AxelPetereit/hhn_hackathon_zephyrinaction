#!/bin/bash
echo "=== screen_game.c: timer lifecycle ==="
grep -n "game_timer\|game_screen_delete_cb\|lv_timer_create\|lv_timer_delete\|screen_game_create\|LV_EVENT_DELETE\|game_done\|enter_wait\|GAME_WAIT" \
  ~/zephyr_git/pic64gx-zephyr/demos/pic64_smp_hello/src/screen_game.c

echo ""
echo "=== demo_manager.c: load_game_screen + is_done ==="
grep -n "load_game_screen\|screen_game_is_done\|lv_screen_load\|game_last_load\|in_game_mode" \
  ~/zephyr_git/pic64gx-zephyr/demos/pic64_smp_hello/src/demo_manager.c
