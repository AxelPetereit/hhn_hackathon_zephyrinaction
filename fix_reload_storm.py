#!/usr/bin/env python3
"""Fix: add reload cooldown in demo_manager to prevent the old game_tick_cb
from triggering repeated load_game_screen() calls during the 400ms fade-out."""

dm = "/home/m77107/zephyr_git/pic64gx-zephyr/demos/pic64_smp_hello/src/demo_manager.c"
with open(dm) as f:
    src = f.read()

# 1. Add static cooldown variable after the existing statics
src = src.replace(
    "static bool     in_game_mode;",
    "static bool     in_game_mode;\nstatic int64_t  game_last_load;  /* ms timestamp of last load_game_screen() */",
)

# 2. Replace the bare screen_game_is_done() check with a guarded version
old_check = (
    "\t\t/* ── Poll game-done flag → return to HUD ───────────────────── */\n"
    "\t\tif (in_game_mode && screen_game_is_done()) {\n"
    "\t\t\tin_game_mode = false;\n"
    "\t\t\tload_screen(0);  /* back to HUD */\n"
    "\t\t\tnext_switch = now + CYCLE_MS;\n"
    "\t\t}"
)
new_check = (
    "\t\t/* ── Poll game-done flag → restart game ─────────────────────── */\n"
    "\t\t/* Guard: the old game_tick_cb runs for FADE_MS after screen swap\n"
    "\t\t * and keeps setting game_done=true every 33 ms once elapsed>=3000.\n"
    "\t\t * The cooldown prevents repeated load_game_screen() calls. */\n"
    "\t\tif (in_game_mode && screen_game_is_done() &&\n"
    "\t\t    (now - game_last_load) > (FADE_MS + 100)) {\n"
    "\t\t\tgame_last_load = now;\n"
    "\t\t\tload_game_screen();\n"
    "\t\t\tnext_switch = now + CYCLE_MS;\n"
    "\t\t}"
)

if old_check in src:
    src = src.replace(old_check, new_check)
    print("original pattern replaced OK")
else:
    # Already modified by our previous apply_all.py run
    old_check2 = (
        "\t\tif (in_game_mode && screen_game_is_done()) {\n"
        "\t\t\t/* Restart game - stay in game */\n"
        "\t\t\tload_game_screen();\n"
        "\t\t\tnext_switch = now + CYCLE_MS;\n"
        "\t\t}"
    )
    new_check2 = (
        "\t\t/* Guard against reload storm: old game_tick_cb fires every 33 ms\n"
        "\t\t * during FADE_MS and keeps setting game_done=true. */\n"
        "\t\tif (in_game_mode && screen_game_is_done() &&\n"
        "\t\t    (now - game_last_load) > (FADE_MS + 100)) {\n"
        "\t\t\tgame_last_load = now;\n"
        "\t\t\tload_game_screen();\n"
        "\t\t\tnext_switch = now + CYCLE_MS;\n"
        "\t\t}"
    )
    if old_check2 in src:
        src = src.replace(old_check2, new_check2)
        print("modified pattern replaced OK")
    else:
        print("ERROR: pattern not found")
        import re

        m = re.search(r"screen_game_is_done\(\).*?}", src, re.DOTALL)
        if m:
            print(repr(m.group()[:300]))

with open(dm, "w") as f:
    f.write(src)
