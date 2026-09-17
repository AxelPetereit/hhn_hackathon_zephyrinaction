#!/usr/bin/env python3
"""
Senior-dev fix: restart the game IN PLACE instead of reloading the screen.

Root cause: the single static `game_timer` gets clobbered when a second game
screen is created while the first fades out. The old screen's LV_EVENT_DELETE
callback then deletes the NEW timer, leaving the fresh WAIT screen with no
physics timer — SW2 does nothing.

Fix:
  - screen_game.c GAME_OVER: SW2 (flap) → enter_wait() on the SAME screen.
    Never signal game_done for restart. The screen + timer live forever.
  - demo_manager.c: remove the screen_game_is_done() reload block entirely.
"""

SG = "/home/m77107/zephyr_git/pic64gx-zephyr/demos/pic64_smp_hello/src/screen_game.c"
DM = "/home/m77107/zephyr_git/pic64gx-zephyr/demos/pic64_smp_hello/src/demo_manager.c"

# ── screen_game.c: GAME_OVER restarts in place ──────────────────────────────
with open(SG) as f:
    sg = f.read()

old_over = (
    "\tcase GAME_OVER:\n"
    "\t\t/* Return after 3 s or on SW1 press */\n"
    "\t\t{\n"
    "\t\t\tint64_t elapsed = k_uptime_get() - over_time_ms;\n"
    "\n"
    "\t\t\tif (elapsed >= 3000 || enter || flap) {\n"
    "\t\t\t\tgame_done = true;\n"
    "\t\t\t}\n"
    "\t\t}\n"
    "\t\tbreak;"
)
new_over = (
    "\tcase GAME_OVER:\n"
    "\t\t/* SW2 (flap) restarts the game IN PLACE — same screen, same\n"
    "\t\t * timer. No screen reload, so no timer-clobbering race. */\n"
    "\t\tif (flap) {\n"
    "\t\t\tenter_wait();\n"
    "\t\t}\n"
    "\t\tbreak;"
)

if old_over in sg:
    sg = sg.replace(old_over, new_over)
    print("screen_game.c: GAME_OVER now restarts in place")
else:
    print("ERROR: GAME_OVER block not found in screen_game.c")
    import re

    m = re.search(r"case GAME_OVER:.*?break;", sg, re.DOTALL)
    if m:
        print(repr(m.group()))

with open(SG, "w") as f:
    f.write(sg)

# ── demo_manager.c: remove the reload block ─────────────────────────────────
with open(DM) as f:
    dm = f.read()

# Remove the guarded restart block we added earlier
old_block = (
    "\t\t/* ── Poll game-done flag → return to HUD ───────────────────── */\n"
    "\t\t/* Cooldown: old game_tick_cb fires for ~FADE_MS after screen swap and\n"
    "\t\t * sets game_done=true every 33 ms (elapsed>=3000 stays true). Without\n"
    "\t\t * the guard, load_game_screen() fires ~12x, killing each new session. */\n"
    "\t\tif (in_game_mode && screen_game_is_done() &&\n"
    "\t\t    (now - game_last_load) > (FADE_MS + 100)) {\n"
    "\t\t\tgame_last_load = now;\n"
    "\t\t\tload_game_screen();\n"
    "\t\t\tnext_switch = now + CYCLE_MS;\n"
    "\t\t}"
)
new_block = (
    "\t\t/* Game restarts itself in place (screen_game GAME_OVER handles SW2).\n"
    "\t\t * We never leave game mode, so no reload logic is needed here. */"
)

if old_block in dm:
    dm = dm.replace(old_block, new_block)
    print("demo_manager.c: reload block removed")
else:
    print("WARN: demo_manager reload block not found (trying looser match)")
    import re

    # Fallback: remove any if-block referencing screen_game_is_done()
    m = re.search(
        r"\t\t/\* [^\n]*Poll game-done[^\n]*\*/.*?if \(in_game_mode && screen_game_is_done\(\).*?\n\t\t\}",
        dm,
        re.DOTALL,
    )
    if m:
        dm = dm.replace(m.group(), new_block)
        print("demo_manager.c: reload block removed (fallback)")
    else:
        print("ERROR: could not find reload block")

with open(DM, "w") as f:
    f.write(dm)

print("Done.")
