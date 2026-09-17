#!/bin/bash
python3 -c 'from PIL import Image; print("PIL OK")' 2>/dev/null || echo "PIL not available"
python3 -c 'import struct, os; print("struct OK")'

echo "=== LVGL image format ==="
find ~/zephyr -path "*/lvgl/src/draw/lv_image_dsc.h" -o -path "*/lvgl/src/misc/lv_color.h" 2>/dev/null | head -5

grep -rn "LV_IMAGE_HEADER_MAGIC\|LV_COLOR_FORMAT_ARGB8888" \
  ~/zephyr/zephyr/modules/lvgl/ \
  ~/.cache/zephyr/ 2>/dev/null | grep define | head -10

echo "=== LVGL version ==="
find ~/zephyr -name "lv_version.h" 2>/dev/null | head -3 | xargs grep "LVGL_VERSION" 2>/dev/null | head -5
