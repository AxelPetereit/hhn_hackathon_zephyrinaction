#!/bin/bash
set -e
cd ~/zephyr_git/pic64gx-zephyr
git checkout -- .
rm -f demos/pic64_smp_hello/src/microchip_logo_img.c
rm -f demos/pic64_smp_hello/src/microchip_logo_img.h
sed -i 's|/home/administrator/|/home/m77107/|g' demos/pic64_smp_hello/hss-payload.yaml

source ~/.zephyrenv/bin/activate
python3 /mnt/c/developers/Zephyr_HelloFPGA/apply_all.py

# Expand SRAM from 1MB to 2MB (image widget needs it)
sed -i 's/reg = <0x80000000 0x100000>/reg = <0x80000000 0x200000>/' \
  demos/pic64_smp_hello/app.overlay

export ZEPHYR_BASE=/home/m77107/zephyr/zephyr
export ZEPHYR_SDK_INSTALL_DIR=/home/m77107/zephyr-sdk-1.0.1
west build \
  -b pic64gx_curiosity_kit/pic64gx1000/u54/smp \
  -d ~/zephyr/build/pic64_smp_hello \
  -p always \
  ~/zephyr_git/pic64gx-zephyr/demos/pic64_smp_hello
echo "BUILD_OK"
