#!/bin/bash
set -e
BASE=~/zephyr_git/pic64gx-zephyr/demos/pic64_smp_hello

build_and_check() {
    source ~/.zephyrenv/bin/activate
    export ZEPHYR_BASE=/home/m77107/zephyr/zephyr
    export ZEPHYR_SDK_INSTALL_DIR=/home/m77107/zephyr-sdk-1.0.1
    west build -b pic64gx_curiosity_kit/pic64gx1000/u54/smp \
      -d ~/zephyr/build/pic64_smp_hello -p always \
      $BASE > /tmp/build_iso.log 2>&1
    tail -4 /tmp/build_iso.log
}

echo "=== TEST 1: demo_manager only (start in game, restart) ==="
python3 - <<'EOF'
BASE = '/home/m77107/zephyr_git/pic64gx-zephyr/demos/pic64_smp_hello'
dm = BASE + '/src/demo_manager.c'
with open(dm) as f: src = f.read()
src = src.replace(
    '\t/* Load initial screen */\n\tload_screen(0);',
    '\tin_game_mode = true;\n\tload_game_screen();'
)
src = src.replace(
    '\t\tif (in_game_mode && screen_game_is_done()) {\n\t\t\tin_game_mode = false;\n\t\t\tload_screen(0);  /* back to HUD */\n\t\t\tnext_switch = now + CYCLE_MS;\n\t\t}',
    '\t\tif (in_game_mode && screen_game_is_done()) {\n\t\t\tload_game_screen();\n\t\t\tnext_switch = now + CYCLE_MS;\n\t\t}'
)
with open(dm, 'w') as f: f.write(src)
print("demo_manager patched")
EOF
build_and_check
echo "Reverting..."
cd ~/zephyr_git/pic64gx-zephyr && git checkout -- demos/pic64_smp_hello/src/demo_manager.c
