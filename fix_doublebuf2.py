#!/usr/bin/env python3
"""
Fix double-buffering: only flip after a complete game frame, use full
background redraw each GAME_PLAY tick so stale back-buffer data doesn't matter.
"""

BASE = "/home/m77107/zephyr_git/pic64gx-zephyr"

# ── 1. screen_game.c ─────────────────────────────────────────────────────────
sg = BASE + "/demos/pic64_smp_hello/src/screen_game.c"
with open(sg) as f:
    src = f.read()

# 1a. Add frame_ready flag alongside game_done
src = src.replace(
    "static bool         game_done;\nstatic int          both_hold_count;",
    "static bool         game_done;\nstatic int          both_hold_count;\nstatic bool         frame_ready; /* set each tick; cleared by screen_game_frame_ready() */",
)

# 1b. Reset frame_ready in screen_game_create
src = src.replace(
    "\tgame_done       = false;\n\tbtn_inited      = false;\n\tboth_hold_count = 0;",
    "\tgame_done       = false;\n\tbtn_inited      = false;\n\tboth_hold_count = 0;\n\tframe_ready     = false;",
)

# 1c. GAME_PLAY: add full background redraw before pipe erase, set frame_ready
old_play_start = """\tcase GAME_PLAY:
\t\t/* Player physics */
\t\tvy += GRAVITY;
\t\tif (vy > VEL_MAX) {
\t\t\tvy = VEL_MAX;
\t\t}
\t\tif (flap) {
\t\t\tvy = FLAP_VEL;
\t\t}
\t\tpy += vy;
\t\tlv_obj_set_pos(player_obj, PLAYER_X, (int)py);

\t\t/* Erase old pipe positions */
\t\tfor (int i = 0; i < N_PIPES; i++) {
\t\t\tpipe_erase(i);
\t\t}"""

new_play_start = """\tcase GAME_PLAY:
\t\t/* Player physics */
\t\tvy += GRAVITY;
\t\tif (vy > VEL_MAX) {
\t\t\tvy = VEL_MAX;
\t\t}
\t\tif (flap) {
\t\t\tvy = FLAP_VEL;
\t\t}
\t\tpy += vy;
\t\tlv_obj_set_pos(player_obj, PLAYER_X, (int)py);

\t\t/*
\t\t * Full background redraw to back buffer before pipes.
\t\t * This eliminates stale data from 2 frames ago in the
\t\t * back buffer — no separate erase step needed.
\t\t */
\t\t_draw_bg_to(vdma_disp_back_buf(g_vdma));

\t\t/* (pipe_erase no longer needed — background was just redrawn) */"""

if old_play_start in src:
    src = src.replace(old_play_start, new_play_start)
    print("GAME_PLAY start patched OK")
else:
    print("ERROR: GAME_PLAY start not found")

# 1d. Remove the pipe_erase loop (now replaced by background redraw)
src = src.replace(
    "\t\t/* (pipe_erase no longer needed — background was just redrawn) */\n\n\t\t/* Move pipes */\n\t\tfor (int i = 0; i < N_PIPES; i++) {\n\t\t\tpipe_erase(i);\n\t\t}\n\n\t\t/* Move pipes */",
    "\t\t/* Move pipes */",
)
# Also clean up in case the old erase loop is still there with different spacing
src = src.replace(
    "\t\t/* (pipe_erase no longer needed — background was just redrawn) */\n\n\t\t/* Erase old pipe positions */\n\t\tfor (int i = 0; i < N_PIPES; i++) {\n\t\t\tpipe_erase(i);\n\t\t}\n\n\t\t/* Move pipes */",
    "\t\t/* Move pipes */",
)

# 1e. Set frame_ready at the end of GAME_PLAY before collision check break
src = src.replace(
    "\t\t/* Restore ground highlight (pipes may have overwritten edge row) */\n\t\tyuyv_fill(0, GROUND_Y, SCR_W, 4, YUYV_GROUND_H);\n\n\t\tif (check_collision()) {\n\t\t\tenter_over();\n\t\t}\n\t\tbreak;",
    "\t\t/* Restore ground highlight */\n\t\tyuyv_fill(0, GROUND_Y, SCR_W, 4, YUYV_GROUND_H);\n\n\t\tif (check_collision()) {\n\t\t\tenter_over();\n\t\t}\n\t\tframe_ready = true;\n\t\tbreak;",
)

# 1f. Set frame_ready in GAME_WAIT and GAME_OVER too (player/panel animation)
src = src.replace(
    "\t\tlv_obj_set_pos(player_obj, PLAYER_X, (int)py);\n\t\tbreak;\n\n\tcase GAME_OVER:",
    "\t\tlv_obj_set_pos(player_obj, PLAYER_X, (int)py);\n\t\tframe_ready = true;\n\t\tbreak;\n\n\tcase GAME_OVER:",
)
src = src.replace(
    "\t\t/* SW2 = restart */\n\t\tif (flap) {\n\t\t\tenter_wait();\n\t\t}\n\t\tbreak;",
    "\t\t/* SW2 = restart */\n\t\tif (flap) {\n\t\t\tenter_wait();\n\t\t}\n\t\tframe_ready = true;\n\t\tbreak;",
)

# 1g. Add screen_game_frame_ready() function after screen_game_is_done()
src = src.replace(
    "bool screen_game_is_done(void)\n{\n\tif (game_done) {\n\t\tgame_done = false;\n\t\treturn true;\n\t}\n\treturn false;\n}",
    "bool screen_game_is_done(void)\n{\n\tif (game_done) {\n\t\tgame_done = false;\n\t\treturn true;\n\t}\n\treturn false;\n}\n\nbool screen_game_frame_ready(void)\n{\n\tif (frame_ready) {\n\t\tframe_ready = false;\n\t\treturn true;\n\t}\n\treturn false;\n}",
)

with open(sg, "w") as f:
    f.write(src)
print("screen_game.c written")

# ── 2. screen_game.h: add frame_ready declaration ────────────────────────────
sh = BASE + "/demos/pic64_smp_hello/src/screen_game.h"
with open(sh) as f:
    h = f.read()

if "screen_game_frame_ready" not in h:
    h = h.replace(
        "bool screen_game_is_done(void);",
        "bool screen_game_is_done(void);\nbool screen_game_frame_ready(void);",
    )
    with open(sh, "w") as f:
        f.write(h)
    print("screen_game.h updated")
else:
    print("screen_game.h already has frame_ready")

# ── 3. demo_manager.c: flip only when frame is ready ─────────────────────────
dm = BASE + "/demos/pic64_smp_hello/src/demo_manager.c"
with open(dm) as f:
    src = f.read()

# Add screen_game.h include if not present
if "screen_game_frame_ready" not in src:
    # Replace the always-flip with conditional flip
    src = src.replace(
        "\t\tlv_timer_handler();\n\t\tvdma_disp_flip(DEVICE_DT_GET(DT_NODELABEL(vdma_disp)));\n\t\trender_ticks++;",
        "\t\tlv_timer_handler();\n\t\t/* Only flip when game_tick_cb rendered a complete frame. */\n\t\tif (screen_game_frame_ready()) {\n\t\t\tvdma_disp_flip(DEVICE_DT_GET(DT_NODELABEL(vdma_disp)));\n\t\t}\n\t\trender_ticks++;",
    )
    with open(dm, "w") as f:
        f.write(src)
    print("demo_manager.c: conditional flip written")
else:
    print("demo_manager.c already has frame_ready check")

print("All patches done.")
