#!/bin/bash
find ~/zephyr/modules/lib/gui/lvgl -name "*.h" | xargs grep -l "LV_COLOR_FORMAT_ARGB8888" 2>/dev/null | head -3
find ~/zephyr/modules/lib/gui/lvgl -name "*.h" | xargs grep "LV_COLOR_FORMAT_ARGB8888\s*=" 2>/dev/null | head -5
