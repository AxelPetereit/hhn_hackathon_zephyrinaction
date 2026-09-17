#!/bin/bash

echo "=== VDB size calculation ==="
# VDB = 5% of 1280x720 pixels
python3 -c "
w,h = 1280, 720
vdb_pct = 5
pixels = (vdb_pct * w * h) // 100
rows   = pixels // w
chunks = h // rows
bytes  = pixels * 2
print(f'VDB pixels : {pixels:,}')
print(f'VDB bytes  : {bytes:,} ({bytes//1024} KB)')
print(f'Rows/chunk : {rows}')
print(f'Chunks/frame (full screen): {chunks}')
print()
print('With SCREEN_INFO_X_ALIGNMENT_WIDTH=ON (current):')
print(f'  Each flush: {w} x {rows} = {w*rows:,} pixels')
print(f'  Pixels/frame: {w*rows*chunks:,}')
print()
print('Pipe dirty region per frame (80px wide, moves 11px):')
pipe_dirty_w = 80 + 11 + 2  # old+new+margin
pipe_dirty_h = h
print(f'  Pipe dirty: {pipe_dirty_w} x {pipe_dirty_h} = {pipe_dirty_w*pipe_dirty_h:,} px per pipe')
print(f'  3 pipes: {3*pipe_dirty_w*pipe_dirty_h:,} px')
print(f'  Player (44x44 + 11px move): ~{55*55:,} px')
total_dirty = 3*pipe_dirty_w*pipe_dirty_h + 55*55
print(f'  Total dirty: ~{total_dirty:,} px')
print()
print('With SCREEN_INFO_X_ALIGNMENT_WIDTH=OFF + LV_Z_AREA_X_ALIGNMENT_WIDTH=2:')
print(f'  Only dirty regions flushed: ~{total_dirty:,} px vs {w*h:,} px full screen')
print(f'  Speedup factor: {w*h/total_dirty:.1f}x less pixels to convert+write')
print()
# Rough time estimate
cycles_per_pixel = 30
cpu_mhz = 600
flush_ms_full = (w*h * cycles_per_pixel) / (cpu_mhz * 1e6) * 1000
flush_ms_partial = (total_dirty * cycles_per_pixel) / (cpu_mhz * 1e6) * 1000
print(f'Estimated flush time (full):    {flush_ms_full:.1f} ms/frame')
print(f'Estimated flush time (partial): {flush_ms_partial:.1f} ms/frame')
fps_full    = 1000 / (flush_ms_full + 33)
fps_partial = 1000 / (flush_ms_partial + 20)
print(f'Estimated FPS (full+33ms sleep):    {fps_full:.1f} fps')
print(f'Estimated FPS (partial+20ms sleep): {fps_partial:.1f} fps')
print()
print(f'Speed at FPS full    (SCROLL=11): {11*fps_full:.0f} px/s')
print(f'Speed at FPS partial (SCROLL=11): {11*fps_partial:.0f} px/s')
"

echo ""
echo "=== How Zephyr LVGL uses SCREEN_INFO_X_ALIGNMENT_WIDTH ==="
grep -n "X_ALIGNMENT_WIDTH\|x_alignment\|SCREEN_INFO" \
  ~/zephyr/zephyr/modules/lvgl/lvgl.c \
  ~/zephyr/zephyr/modules/lvgl/Kconfig.memory 2>/dev/null | head -20
