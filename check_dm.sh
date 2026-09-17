#!/bin/bash
grep -n "screen_game_is_done\|game_last_load\|Restart\|in_game_mode" \
  ~/zephyr_git/pic64gx-zephyr/demos/pic64_smp_hello/src/demo_manager.c | head -20
