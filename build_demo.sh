#!/bin/bash
set -e

source ~/.zephyrenv/bin/activate

export ZEPHYR_BASE=/home/m77107/zephyr/zephyr
export ZEPHYR_SDK_INSTALL_DIR=/home/m77107/zephyr-sdk-1.0.1
export PATH="$ZEPHYR_SDK_INSTALL_DIR/gnu/riscv64-zephyr-elf/bin:$PATH"

echo "=== Building pic64_smp_hello ==="
west build \
  -b pic64gx_curiosity_kit/pic64gx1000/u54/smp \
  -d ~/zephyr/build/pic64_smp_hello \
  -p always \
  ~/zephyr_git/pic64gx-zephyr/demos/pic64_smp_hello

echo "BUILD_OK"
