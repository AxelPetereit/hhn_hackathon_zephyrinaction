#!/usr/bin/env python3
"""Make the game speed up slightly after each passed pipe."""

sg = "/home/m77107/zephyr_git/pic64gx-zephyr/demos/pic64_smp_hello/src/screen_game.c"
with open(sg) as f:
    src = f.read()

# 1. Add SPEED_STEP / SPEED_MAX next to SCROLL_SPD (which becomes the start speed)
src = src.replace(
    "#define SCROLL_SPD  4.00f",
    "#define SCROLL_SPD  4.00f   /* initial scroll speed */\n"
    "#define SPEED_STEP  0.35f   /* added per passed pipe */\n"
    "#define SPEED_MAX  12.00f   /* speed cap */",
)

# 2. Add runtime scroll speed variable after the score globals
src = src.replace(
    "static int          score;\nstatic int          best_score;",
    "static int          score;\n"
    "static int          best_score;\n"
    "static float        scroll_spd;   /* current scroll speed, ramps up per pipe */",
)

# 3. Reset scroll_spd in game_reset()
src = src.replace(
    "\tpy    = 300.0f;\n\tvy    = 0.0f;\n\tscore = 0;",
    "\tpy    = 300.0f;\n\tvy    = 0.0f;\n\tscore = 0;\n\tscroll_spd = SCROLL_SPD;",
)

# 4. Use scroll_spd for scrolling, and bump it on score
src = src.replace("\t\t\tpipe_x[i] -= SCROLL_SPD;", "\t\t\tpipe_x[i] -= scroll_spd;")
src = src.replace(
    "\t\t\tif (!scored[i] && centre < PLAYER_X) {\n"
    "\t\t\t\tscored[i] = true;\n"
    "\t\t\t\tscore++;\n"
    "\t\t\t\tscore_update();\n"
    "\t\t\t}",
    "\t\t\tif (!scored[i] && centre < PLAYER_X) {\n"
    "\t\t\t\tscored[i] = true;\n"
    "\t\t\t\tscore++;\n"
    "\t\t\t\tscore_update();\n"
    "\t\t\t\t/* Speed up a little after each pipe, up to the cap */\n"
    "\t\t\t\tscroll_spd += SPEED_STEP;\n"
    "\t\t\t\tif (scroll_spd > SPEED_MAX) {\n"
    "\t\t\t\t\tscroll_spd = SPEED_MAX;\n"
    "\t\t\t\t}\n"
    "\t\t\t}",
)

with open(sg, "w") as f:
    f.write(src)

# Verify
chk = open(sg).read()
ok = all(
    s in chk
    for s in [
        "SPEED_STEP",
        "scroll_spd = SCROLL_SPD",
        "pipe_x[i] -= scroll_spd",
        "scroll_spd += SPEED_STEP",
    ]
)
print("OK - all speedup edits applied" if ok else "ERROR - some edits missing")
