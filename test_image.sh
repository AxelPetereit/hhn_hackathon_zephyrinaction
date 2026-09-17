#!/bin/bash
BASE=~/zephyr_git/pic64gx-zephyr/demos/pic64_smp_hello

source ~/.zephyrenv/bin/activate
export ZEPHYR_BASE=/home/m77107/zephyr/zephyr
export ZEPHYR_SDK_INSTALL_DIR=/home/m77107/zephyr-sdk-1.0.1

echo "=== TEST B: RGB565 logo (no alpha) — avoids ARGB8888 decoder overhead ==="
# Generate RGB565 logo
python3 - <<'PYEOF'
from PIL import Image, ImageDraw
import os

img = Image.open('/mnt/c/developers/Zephyr_HelloFPGA/microchip_logo.png').convert('RGB')
img = img.resize((44, 44), Image.LANCZOS)

# Apply rounded corners by replacing corner pixels with white (match LVGL bg)
mask = Image.new('L', (44, 44), 0)
draw = ImageDraw.Draw(mask)
draw.rounded_rectangle([0, 0, 43, 43], radius=8, fill=255)

# Convert to RGB565 bytes
pix = img.load()
data = bytearray()
for y in range(44):
    for x in range(44):
        r, g, b = pix[x, y]
        m = mask.getpixel((x, y))
        if m == 0:  # corner: use white (sky bg replacement)
            r, g, b = 13, 17, 23  # C_SKY color = 0x0D1117
        rgb565 = ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3)
        data += bytes([rgb565 & 0xFF, rgb565 >> 8])  # little-endian

OUT = '/home/m77107/zephyr_git/pic64gx-zephyr/demos/pic64_smp_hello/src'
hex_lines = ['    ' + ', '.join(f'0x{b:02X}' for b in data[i:i+16]) + ',' for i in range(0, len(data), 16)]

c = f"""/* Auto-generated LVGL v9 RGB565 image, 44x44 */
#include "microchip_logo_img.h"
static const uint8_t logo_data[{len(data)}] = {{
{chr(10).join(hex_lines)}
}};
const lv_image_dsc_t microchip_logo_img = {{
    .header = {{ .magic=LV_IMAGE_HEADER_MAGIC, .cf=LV_COLOR_FORMAT_RGB565,
                .flags=0, .w=44, .h=44, .stride=88u, .reserved_2=0 }},
    .data_size={len(data)}u, .data=logo_data, .reserved=NULL, .reserved_2=NULL,
}};
"""
h = """#ifndef MICROCHIP_LOGO_IMG_H
#define MICROCHIP_LOGO_IMG_H
#include <lvgl.h>
extern const lv_image_dsc_t microchip_logo_img;
#endif
"""
with open(OUT+'/microchip_logo_img.c','w') as f: f.write(c)
with open(OUT+'/microchip_logo_img.h','w') as f: f.write(h)
print(f"RGB565 logo written: {len(data)} bytes")
PYEOF

sed -i 's|    src/screen_game.c|    src/microchip_logo_img.c\n    src/screen_game.c|' $BASE/CMakeLists.txt
python3 /mnt/c/developers/Zephyr_HelloFPGA/patch_logo.py

west build -b pic64gx_curiosity_kit/pic64gx1000/u54/smp \
  -d ~/zephyr/build/pic64_smp_hello -p always \
  $BASE > /tmp/build_imgtest.log 2>&1
echo "EXIT:$?"
grep "RAM:\|overflow" /tmp/build_imgtest.log | tail -3
