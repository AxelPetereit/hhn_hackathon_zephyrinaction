#!/usr/bin/env python3
"""Convert microchip_logo.png to LVGL v9 ARGB8888 C array.
Full square image, only rounded corners applied.
"""

from PIL import Image, ImageDraw
import os

PNG_IN = "/mnt/c/developers/Zephyr_HelloFPGA/microchip_logo.png"
OUT_DIR = "/home/m77107/zephyr_git/pic64gx-zephyr/demos/pic64_smp_hello/src"
SIZE = 44
RADIUS = 8

# Load full image, resize to 44x44 - no cropping, no background removal
img = Image.open(PNG_IN).convert("RGBA")
print(f"Original: {img.size}")

img = img.resize((SIZE, SIZE), Image.LANCZOS)

# Apply rounded corner mask only
mask = Image.new("L", (SIZE, SIZE), 0)
draw = ImageDraw.Draw(mask)
draw.rounded_rectangle([0, 0, SIZE - 1, SIZE - 1], radius=RADIUS, fill=255)

r_ch, g_ch, b_ch, a_ch = img.split()
from PIL import ImageChops

a_new = ImageChops.multiply(a_ch, mask)
img = Image.merge("RGBA", (r_ch, g_ch, b_ch, a_new))

# Encode as BGRA (LVGL ARGB8888 memory order: blue, green, red, alpha)
pix = img.load()
data = bytearray()
for y in range(SIZE):
    for x in range(SIZE):
        r, g, b, a = pix[x, y]
        data += bytes([b, g, r, a])

print(f"Data: {len(data)} bytes ({SIZE}x{SIZE}x4)")

# C source
hex_lines = []
for i in range(0, len(data), 16):
    chunk = data[i : i + 16]
    hex_lines.append("    " + ", ".join(f"0x{b:02X}" for b in chunk) + ",")

c_src = f"""\
/* SPDX-License-Identifier: Apache-2.0
 * Auto-generated — do not edit.
 * LVGL v9 ARGB8888, {SIZE}x{SIZE} px, rounded corners r={RADIUS}.
 */

#include "microchip_logo_img.h"

static const uint8_t logo_data[{len(data)}] = {{
{chr(10).join(hex_lines)}
}};

const lv_image_dsc_t microchip_logo_img = {{
    .header = {{
        .magic       = LV_IMAGE_HEADER_MAGIC,
        .cf          = LV_COLOR_FORMAT_ARGB8888,
        .flags       = 0,
        .w           = {SIZE},
        .h           = {SIZE},
        .stride      = {SIZE * 4}u,
        .reserved_2  = 0,
    }},
    .data_size  = {len(data)}u,
    .data       = logo_data,
    .reserved   = NULL,
    .reserved_2 = NULL,
}};
"""

h_src = """\
/* SPDX-License-Identifier: Apache-2.0 — auto-generated */
#ifndef MICROCHIP_LOGO_IMG_H
#define MICROCHIP_LOGO_IMG_H
#include <lvgl.h>
extern const lv_image_dsc_t microchip_logo_img;
#endif
"""

with open(os.path.join(OUT_DIR, "microchip_logo_img.c"), "w") as f:
    f.write(c_src)
with open(os.path.join(OUT_DIR, "microchip_logo_img.h"), "w") as f:
    f.write(h_src)

preview = "/mnt/c/developers/Zephyr_HelloFPGA/logo_preview.png"
img.save(preview)
print(f"Preview saved: {preview}")
print("Done.")
