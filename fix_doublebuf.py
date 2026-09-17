#!/usr/bin/env python3
"""
Fix flickering pipes by switching to proper double-buffering:
  - screen_game.c : write to back buffer; draw_background() initialises both bufs
  - hdmi_fb.c     : LVGL flushes to back buffer
  - demo_manager.c: flip after lv_timer_handler()
"""

import re, os

BASE = "/home/m77107/zephyr_git/pic64gx-zephyr"

# ── 1. screen_game.c ─────────────────────────────────────────────────────────
sg = BASE + "/demos/pic64_smp_hello/src/screen_game.c"
with open(sg) as f:
    src = f.read()

# Replace single g_fb pointer with g_vdma device pointer
src = src.replace(
    "static uint8_t  *g_fb;         /* pointer to YUYV422 framebuffer             */",
    "static const struct device *g_vdma; /* vdma device for double-buffer access */",
)

# Replace yuyv_fill implementation: write to back_buf each call
old_fill = """\
static void yuyv_fill(int x, int y, int w, int h, uint32_t yuyv)
{
\tif (w <= 0 || h <= 0) {
\t\treturn;
\t}
\tx &= ~1;
\tw = (w + 1) & ~1;
\tif (x < 0)     { w += x; x = 0; }
\tif (y < 0)     { h += y; y = 0; }
\tif (x >= SCR_W || y >= SCR_H) {
\t\treturn;
\t}
\tif (x + w > SCR_W) { w = SCR_W - x; }
\tif (y + h > SCR_H) { h = SCR_H - y; }
\tif (w <= 0 || h <= 0) {
\t\treturn;
\t}

\tuint32_t *row = (uint32_t *)(g_fb + (size_t)y * (SCR_W * 2u) + (size_t)x * 2u);
\tconst int stride = SCR_W / 2;   /* uint32_t stride per row */
\tconst int fill_w = w / 2;       /* uint32_t words to write per row */

\tfor (int r = 0; r < h; r++, row += stride) {
\t\tfor (int c = 0; c < fill_w; c++) {
\t\t\trow[c] = yuyv;
\t\t}
\t}
}"""

new_fill = """\
/* Internal: fill into an explicit buffer pointer. */
static void _fill_buf(uint8_t *fb, int x, int y, int w, int h, uint32_t yuyv)
{
\tif (w <= 0 || h <= 0) {
\t\treturn;
\t}
\tx &= ~1;
\tw = (w + 1) & ~1;
\tif (x < 0)     { w += x; x = 0; }
\tif (y < 0)     { h += y; y = 0; }
\tif (x >= SCR_W || y >= SCR_H) {
\t\treturn;
\t}
\tif (x + w > SCR_W) { w = SCR_W - x; }
\tif (y + h > SCR_H) { h = SCR_H - y; }
\tif (w <= 0 || h <= 0) {
\t\treturn;
\t}
\tuint32_t *row = (uint32_t *)(fb + (size_t)y * (SCR_W * 2u) + (size_t)x * 2u);
\tconst int stride = SCR_W / 2;
\tconst int fill_w = w / 2;

\tfor (int r = 0; r < h; r++, row += stride) {
\t\tfor (int c = 0; c < fill_w; c++) {
\t\t\trow[c] = yuyv;
\t\t}
\t}
}

/* Always write to the back buffer — safe while VDMA reads the front. */
static void yuyv_fill(int x, int y, int w, int h, uint32_t yuyv)
{
\t_fill_buf(vdma_disp_back_buf(g_vdma), x, y, w, h, yuyv);
}"""

if old_fill in src:
    src = src.replace(old_fill, new_fill)
    print("yuyv_fill patched OK")
else:
    print("ERROR: yuyv_fill block not found")

# Replace draw_background to init BOTH buffers (so back-buffer starts correct)
old_bg = """\
/* Draw the static background (sky, ground, stars) once per game session. */
static void draw_background(void)
{
\tyuyv_fill(0, 0,        SCR_W, GROUND_Y, YUYV_SKY);
\tyuyv_fill(0, GROUND_Y, SCR_W, GROUND_H, YUYV_GROUND);
\tyuyv_fill(0, GROUND_Y, SCR_W, 4,        YUYV_GROUND_H);

\t/* Stars — same xorshift seed as original LVGL version */
\tuint32_t rng = 0xCAFEBABEu;

\tfor (int i = 0; i < N_STARS; i++) {
\t\trng ^= rng << 13;
\t\trng ^= rng >> 17;
\t\trng ^= rng << 5;
\t\tint sx = (int)(rng % (uint32_t)SCR_W);

\t\trng ^= rng << 13;
\t\trng ^= rng >> 17;
\t\trng ^= rng << 5;
\t\tint sy = (int)(rng % (uint32_t)(GROUND_Y - 20));
\t\tint sz = (i % 3 == 0) ? 4 : 2;

\t\tyuyv_fill(sx, sy, sz, sz, YUYV_STAR);
\t}
}"""

new_bg = """\
/* Draw static background (sky, ground, stars) into the given buffer. */
static void _draw_bg_to(uint8_t *fb)
{
\t_fill_buf(fb, 0, 0,        SCR_W, GROUND_Y, YUYV_SKY);
\t_fill_buf(fb, 0, GROUND_Y, SCR_W, GROUND_H, YUYV_GROUND);
\t_fill_buf(fb, 0, GROUND_Y, SCR_W, 4,        YUYV_GROUND_H);

\tuint32_t rng = 0xCAFEBABEu;

\tfor (int i = 0; i < N_STARS; i++) {
\t\trng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5;
\t\tint sx = (int)(rng % (uint32_t)SCR_W);
\t\trng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5;
\t\tint sy = (int)(rng % (uint32_t)(GROUND_Y - 20));
\t\tint sz = (i % 3 == 0) ? 4 : 2;
\t\t_fill_buf(fb, sx, sy, sz, sz, YUYV_STAR);
\t}
}

/*
 * Initialise BOTH framebuffers with the static background so that
 * double-buffering starts from a consistent state.
 */
static void draw_background(void)
{
\t_draw_bg_to(vdma_disp_front_buf(g_vdma));
\t_draw_bg_to(vdma_disp_back_buf(g_vdma));
}"""

if old_bg in src:
    src = src.replace(old_bg, new_bg)
    print("draw_background patched OK")
else:
    print("ERROR: draw_background block not found")

# Fix screen_game_create: g_fb → g_vdma
src = src.replace(
    "\tg_fb          = vdma_disp_front_buf(DEVICE_DT_GET(DT_NODELABEL(vdma_disp)));",
    "\tg_vdma        = DEVICE_DT_GET(DT_NODELABEL(vdma_disp));",
)

with open(sg, "w") as f:
    f.write(src)
print("screen_game.c written")

# ── 2. hdmi_fb.c: flush to back buffer ───────────────────────────────────────
hf = BASE + "/drivers/hdmi_fb/hdmi_fb.c"
with open(hf) as f:
    src = f.read()

src = src.replace(
    "\tuint8_t *dst_base = vdma_disp_front_buf(vdma_dev);",
    "\tuint8_t *dst_base = vdma_disp_back_buf(vdma_dev);  /* back buf — flip after render */",
)

src = src.replace(
    """\
\t/*
\t * Single-buffer mode: write directly to the front (displayed) buffer.
\t * The VDMA loops this buffer at 60 Hz; LVGL updates only dirty regions
\t * so changes appear on the next VDMA scan with no vsync wait required.
\t * Tearing on fast-moving content is possible but imperceptible for
\t * text that updates at ≤20 fps.
\t */""",
    """\
\t/*
\t * Double-buffer mode: always write to the back (non-displayed) buffer.
\t * demo_manager calls vdma_disp_flip() after lv_timer_handler() so
\t * the VDMA only ever sees a fully-rendered frame.
\t */""",
)

with open(hf, "w") as f:
    f.write(src)
print("hdmi_fb.c written")

# ── 3. demo_manager.c: flip after lv_timer_handler ───────────────────────────
dm = BASE + "/demos/pic64_smp_hello/src/demo_manager.c"
with open(dm) as f:
    src = f.read()

# Add vdma_disp device reference and flip call
src = src.replace(
    "\tlv_timer_handler();\n\t\trender_ticks++;\n\t\tk_sleep(K_MSEC(RENDER_MS));",
    "\tlv_timer_handler();\n\t\tvdma_disp_flip(DEVICE_DT_GET(DT_NODELABEL(vdma_disp)));\n\t\trender_ticks++;\n\t\tk_sleep(K_MSEC(RENDER_MS));",
)

with open(dm, "w") as f:
    f.write(src)
print("demo_manager.c written")

print("All patches applied.")
