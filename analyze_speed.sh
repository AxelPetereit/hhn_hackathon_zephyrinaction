#!/bin/bash
echo "=== LVGL tick source in Zephyr port ==="
find ~/zephyr/zephyr/modules/lvgl -name "*.c" | xargs grep -l "tick\|lv_task_handler\|lv_timer_handler" 2>/dev/null

echo ""
echo "=== lv_tick_get / tick configuration ==="
find ~/zephyr/zephyr/modules/lvgl -name "*.c" -o -name "*.h" | xargs grep -n "lv_tick\|LV_TICK\|k_uptime\|sys_clock" 2>/dev/null | head -20

echo ""
echo "=== Zephyr LVGL tick period config ==="
find ~/zephyr/zephyr/modules/lvgl -name "Kconfig*" | xargs grep -n "TICK\|tick" 2>/dev/null | head -20

echo ""
echo "=== game timer period in built binary (check lv_timer_create call) ==="
grep -n "lv_timer_create" ~/zephyr_git/pic64gx-zephyr/demos/pic64_smp_hello/src/screen_game.c

echo ""
echo "=== RENDER_MS in demo_manager ==="
grep -n "RENDER_MS\|k_sleep\|lv_timer_handler" ~/zephyr_git/pic64gx-zephyr/demos/pic64_smp_hello/src/demo_manager.c

echo ""
echo "=== VDB size (affects render time per frame) ==="
grep "VDB\|vdb\|Z_VDB" ~/zephyr_git/pic64gx-zephyr/demos/pic64_smp_hello/prj.conf

echo ""
echo "=== Screen resolution and pipeline ==="
grep "SCR_W\|SCR_H\|PIPE_SPACING\|SCROLL_SPD" ~/zephyr_git/pic64gx-zephyr/demos/pic64_smp_hello/src/screen_game.c | head -10
