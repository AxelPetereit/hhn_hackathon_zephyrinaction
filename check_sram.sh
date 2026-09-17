#!/bin/bash
echo "=== Current SRAM size config ==="
grep "SRAM_SIZE\|SRAM_BASE\|RAM_SIZE" \
  ~/zephyr/zephyr/boards/microchip/pic64gx_curiosity_kit/pic64gx_curiosity_kit_pic64gx1000_u54_smp_defconfig \
  ~/zephyr/zephyr/boards/microchip/pic64gx_curiosity_kit/pic64gx_curiosity_kit_defconfig 2>/dev/null

echo ""
echo "=== DRAM node in DTS ==="
grep -A3 "dram:" \
  ~/zephyr/zephyr/boards/microchip/pic64gx_curiosity_kit/pic64gx_curiosity_kit_common.dtsi

echo ""
echo "=== What Zephyr sram node is used ==="
grep -r "zephyr,sram" \
  ~/zephyr/zephyr/boards/microchip/pic64gx_curiosity_kit/ 2>/dev/null
