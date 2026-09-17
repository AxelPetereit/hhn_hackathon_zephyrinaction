#!/bin/bash
# Build pure original to get .config, then compare with lv_image build

source ~/.zephyrenv/bin/activate
export ZEPHYR_BASE=/home/m77107/zephyr/zephyr
export ZEPHYR_SDK_INSTALL_DIR=/home/m77107/zephyr-sdk-1.0.1

echo "=== Build original to get .config ==="
west build -b pic64gx_curiosity_kit/pic64gx1000/u54/smp \
  -d /tmp/build_orig_cfg -p always \
  ~/zephyr_git/pic64gx-zephyr/demos/pic64_smp_hello > /dev/null 2>&1
cp /tmp/build_orig_cfg/zephyr/.config /tmp/config_orig.txt
echo "Original .config saved"

echo ""
echo "=== Kconfig diff: what does lv_image_create trigger? ==="
echo "Searching for image/draw-layer related configs in original .config..."
grep "LV_USE_IMAGE\|LV_DRAW_LAYER\|LV_USE_DRAW\|LV_BIN_DECODER\|LV_USE_LAYER" /tmp/config_orig.txt | head -20
