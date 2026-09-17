#!/usr/bin/env python3
sg = "/home/m77107/zephyr_git/pic64gx-zephyr/demos/pic64_smp_hello/src/screen_game.c"
with open(sg) as f:
    src = f.read()

old = "#define GAP_H         180"
new = "#define GAP_H         280   /* larger gap = easier for kids */"

if old in src:
    src = src.replace(old, new)
    with open(sg, "w") as f:
        f.write(src)
    print("OK - GAP_H set to 280")
else:
    print("ERROR - GAP_H 180 not found")
    import re

    for m in re.finditer(r"#define GAP_H\s+\d+", src):
        print("  found:", repr(m.group()))
