#!/usr/bin/env python3
sg = "/home/m77107/zephyr_git/pic64gx-zephyr/demos/pic64_smp_hello/src/screen_game.c"
with open(sg) as f:
    src = f.read()

# Original GAME_OVER: only SW1 (enter) or 3s timeout triggers game_done
# Add SW2 (flap) as restart trigger
src = src.replace(
    "\t\tif (elapsed >= 3000 || enter) {\n\t\t\t\tgame_done = true;\n\t\t\t}",
    "\t\tif (elapsed >= 3000 || enter || flap) {\n\t\t\t\tgame_done = true;\n\t\t\t}",
)

# Also try without extra tab indentation
src = src.replace(
    "\t\tif (elapsed >= 3000 || enter) {\n\t\t\tgame_done = true;\n\t\t}",
    "\t\tif (elapsed >= 3000 || enter || flap) {\n\t\t\tgame_done = true;\n\t\t}",
)

with open(sg, "w") as f:
    f.write(src)

# Verify
if "flap" in open(sg).read().split("GAME_OVER")[1].split("break")[0]:
    print("OK - SW2 (flap) added to GAME_OVER restart condition")
else:
    print("ERROR - check indentation manually")
    import re

    m = re.search(r"case GAME_OVER.*?break;", open(sg).read(), re.DOTALL)
    if m:
        print(repr(m.group()))
