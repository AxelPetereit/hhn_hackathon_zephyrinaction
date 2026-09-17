#!/bin/bash
source ~/.zephyrenv/bin/activate
cd ~/zephyr
west update --narrow --fetch-opt=--depth=1
echo "EXIT_CODE: $?" >> /tmp/west_update.log
