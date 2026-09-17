#!/bin/bash

echo "=== CONFIG_LV_Z_VDB_SIZE Kconfig definition ==="
find ~/zephyr/zephyr/modules/lvgl -name "Kconfig*" | xargs grep -A8 "LV_Z_VDB_SIZE" 2>/dev/null

echo ""
echo "=== How VDB size is calculated in code ==="
find ~/zephyr/zephyr/modules/lvgl -name "*.c" | xargs grep -n "VDB_SIZE\|vdb_size\|buf_size\|disp_draw_buf" 2>/dev/null | head -20

echo ""
echo "=== hdmi_fb flush callback (how long is each flush?) ==="
cat ~/zephyr_git/pic64gx-zephyr/drivers/hdmi_fb/hdmi_fb.c

echo ""
echo "=== vdma_disp front buf address (cached vs non-cached) ==="
grep -n "front_buf\|back_buf\|WCB\|0xC02" ~/zephyr_git/pic64gx-zephyr/drivers/vdma_disp/vdma_disp.h \
  ~/zephyr_git/pic64gx-zephyr/drivers/vdma_disp/vdma_disp.c 2>/dev/null | head -20
