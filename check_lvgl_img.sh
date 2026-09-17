#!/bin/bash
sed -n '/config LV_USE_IMAGE$/,/^$/p' ~/zephyr/modules/lib/gui/lvgl/Kconfig | head -10
