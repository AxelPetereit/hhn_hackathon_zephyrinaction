#!/bin/bash
cd ~/zephyr_git/pic64gx-zephyr
git stash
sed -i 's|/home/administrator/|/home/m77107/|g' demos/pic64_smp_hello/hss-payload.yaml

source ~/.zephyrenv/bin/activate
export ZEPHYR_BASE=/home/m77107/zephyr/zephyr
export ZEPHYR_SDK_INSTALL_DIR=/home/m77107/zephyr-sdk-1.0.1

west build \
  -b pic64gx_curiosity_kit/pic64gx1000/u54/smp \
  -d ~/zephyr/build/pic64_smp_hello \
  -p always \
  ~/zephyr_git/pic64gx-zephyr/demos/pic64_smp_hello > /tmp/build_orig.log 2>&1
echo "EXIT:$?"
tail -5 /tmp/build_orig.log

git stash pop
