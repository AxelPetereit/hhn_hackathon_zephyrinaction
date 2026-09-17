#!/bin/bash
echo "=== LV_DRAW_LAYER_MAX_MEMORY and LV_DRAW_LAYER_SIMPLE_BUF_SIZE defaults ==="
sed -n '/LV_DRAW_LAYER_SIMPLE_BUF_SIZE/,/^$/p' \
  ~/zephyr/modules/lib/gui/lvgl/Kconfig | head -20
echo "---"
sed -n '/LV_DRAW_LAYER_MAX_MEMORY/,/^$/p' \
  ~/zephyr/modules/lib/gui/lvgl/Kconfig | head -20

echo ""
echo "=== What depends on LV_USE_IMAGE in Kconfig ==="
sed -n '/config LV_USE_IMAGE$/,/^[[:space:]]*config /p' \
  ~/zephyr/modules/lib/gui/lvgl/Kconfig | head -20

echo ""
echo "=== Does LV_USE_IMAGE select/imply LV_DRAW_LAYER? ==="
grep -A20 "config LV_USE_IMAGE$" ~/zephyr/modules/lib/gui/lvgl/Kconfig | head -20
