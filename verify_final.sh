#!/bin/bash
echo "=== screen_game.c GAME_OVER ==="
sed -n '383,392p' ~/zephyr_git/pic64gx-zephyr/demos/pic64_smp_hello/src/screen_game.c
echo ""
echo "=== demo_manager.c restart region ==="
sed -n '270,275p' ~/zephyr_git/pic64gx-zephyr/demos/pic64_smp_hello/src/demo_manager.c
echo ""
echo "=== button init in create ==="
grep -n "btn_inited       = true" ~/zephyr_git/pic64gx-zephyr/demos/pic64_smp_hello/src/screen_game.c
