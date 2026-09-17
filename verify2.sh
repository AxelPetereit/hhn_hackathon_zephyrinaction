#!/bin/bash
echo "=== SCROLL_SPD ==="
grep "SCROLL_SPD" ~/zephyr_git/pic64gx-zephyr/demos/pic64_smp_hello/src/screen_game.c

echo "=== CMakeLists: screen files ==="
grep "screen_" ~/zephyr_git/pic64gx-zephyr/demos/pic64_smp_hello/CMakeLists.txt

echo "=== demo_manager: no workers or cycling ==="
grep -c "worker\|CYCLE_MS\|screens\[" ~/zephyr_git/pic64gx-zephyr/demos/pic64_smp_hello/src/demo_manager.c && echo "WARN: still has old code" || echo "OK - clean"

echo "=== demo_manager size ==="
wc -l ~/zephyr_git/pic64gx-zephyr/demos/pic64_smp_hello/src/demo_manager.c
