#!/usr/bin/env python3
import os

BASE = "/home/m77107/zephyr_git/pic64gx-zephyr/demos/pic64_smp_hello"

# ── 1. CMakeLists.txt: remove the four unused screen source files ─────────────
cmake_path = BASE + "/CMakeLists.txt"
with open(cmake_path) as f:
    cmake = f.read()

for line in [
    "    src/screen_hud.c\n",
    "    src/screen_dashboard.c\n",
    "    src/screen_charts.c\n",
    "    src/screen_widgets.c\n",
]:
    cmake = cmake.replace(line, "")

with open(cmake_path, "w") as f:
    f.write(cmake)
print("CMakeLists.txt: removed 4 screen files")

# ── 2. screen_game.c: double scroll speed, update hint texts ─────────────────
game_path = BASE + "/src/screen_game.c"
with open(game_path) as f:
    game = f.read()

game = game.replace("#define SCROLL_SPD  5.50f", "#define SCROLL_SPD 11.00f")
game = game.replace('"SW1+SW2: exit"', '"SW1+SW2: restart"')
# Also fix the sub_lbl hint in the no-new-best branch
game = game.replace(
    '"Best: %d  SW1+SW2: restart"', '"Best: %d  SW1+SW2: restart"'
)  # already correct name

with open(game_path, "w") as f:
    f.write(game)
print("screen_game.c: SCROLL_SPD=11.0, hints updated")

# ── 3. demo_manager.c: rewrite to game-only (no workers, no screen cycling) ──
dm_path = BASE + "/src/demo_manager.c"

new_dm = """\
/* SPDX-License-Identifier: Apache-2.0
 *
 * Demo manager — game-only build.
 * Starts Flappy Bird directly on boot; restarts the game when it ends
 * (SW1+SW2 in screen_game triggers the restart via screen_game_is_done()).
 *
 * Runs on core 2.
 */

#include "demo_manager.h"
#include "screen_game.h"

#include <zephyr/kernel.h>
#include <zephyr/sys/printk.h>
#include "vdma_disp.h"

/* ── Colour / timing ──────────────────────────────────────────────────────── */
#define C_GREEN   0x3FB950u
#define C_MC_RED  0xC0392Bu
#define RENDER_MS      33   /* lv_timer_handler period ms (~30 fps) */
#define FADE_MS       400

/* ── FPS state ────────────────────────────────────────────────────────────── */
static uint32_t g_render_fps;
static uint32_t g_output_fps;

uint32_t demo_get_render_fps(void) { return g_render_fps; }
uint32_t demo_get_output_fps(void) { return g_output_fps; }
int      demo_get_screen_idx(void) { return 0; }

/* ── Persistent overlay (FPS badge only) ─────────────────────────────────── */
static lv_obj_t *fps_badge;

static void overlay_create(void)
{
\tlv_obj_t *top = lv_layer_top();

\tfps_badge = lv_label_create(top);
\tlv_label_set_text(fps_badge, "R:-- D:--fps");
\tlv_obj_set_style_text_font(fps_badge, &lv_font_montserrat_14, LV_PART_MAIN);
\tlv_obj_set_style_text_color(fps_badge, lv_color_hex(C_GREEN), LV_PART_MAIN);
\tlv_obj_align(fps_badge, LV_ALIGN_TOP_RIGHT, -12, 6);
}

static void overlay_fps_update(uint32_t render_fps, uint32_t output_fps)
{
\tchar buf[32];

\tsnprintk(buf, sizeof(buf), "R:%u D:%ufps", render_fps, output_fps);
\tlv_label_set_text(fps_badge, buf);
}

/* ── Game screen loader ───────────────────────────────────────────────────── */
static void load_game(void)
{
\tlv_obj_t *scr = screen_game_create();

\tlv_screen_load_anim(scr, LV_SCR_LOAD_ANIM_FADE_ON, FADE_MS, 0, true);
\tprintk("[demo] game (re)started\\n");
}

/* ── Main thread ──────────────────────────────────────────────────────────── */
#define DM_STACK  16384
#define DM_PRIO   6
#define DM_CORE   2

static K_THREAD_STACK_DEFINE(dm_stack, DM_STACK);
static struct k_thread dm_thread;

static void demo_thread_fn(void *p1, void *p2, void *p3)
{
\tARG_UNUSED(p1); ARG_UNUSED(p2); ARG_UNUSED(p3);

\tprintk("[demo] starting on core %d\\n", arch_curr_cpu()->id);

\toverlay_create();
\tload_game();

\tint64_t  next_stat   = k_uptime_get() + 1000;
\tuint32_t render_ticks = 0;

\twhile (true) {
\t\tint64_t now = k_uptime_get();

\t\t/* SW1+SW2 held in game → restart */
\t\tif (screen_game_is_done()) {
\t\t\tload_game();
\t\t}

\t\t/* 1 Hz: update FPS overlay */
\t\tif (now >= next_stat) {
\t\t\tg_render_fps = render_ticks;
\t\t\tg_output_fps = vdma_disp_get_frame_count(
\t\t\t\tDEVICE_DT_GET(DT_NODELABEL(vdma_disp)));
\t\t\toverlay_fps_update(g_render_fps, g_output_fps);
\t\t\trender_ticks = 0;
\t\t\tnext_stat = now + 1000;
\t\t}

\t\tlv_timer_handler();
\t\trender_ticks++;
\t\tk_sleep(K_MSEC(RENDER_MS));
\t}
}

void demo_manager_start(void)
{
\tk_tid_t tid = k_thread_create(&dm_thread, dm_stack, DM_STACK,
\t\t\t\t      demo_thread_fn, NULL, NULL, NULL,
\t\t\t\t      DM_PRIO, 0, K_FOREVER);
#ifdef CONFIG_SCHED_CPU_MASK
\tk_thread_cpu_mask_clear(tid);
\tk_thread_cpu_mask_enable(tid, DM_CORE);
#endif
\tk_thread_name_set(tid, "demo_mgr");
\tk_thread_start(tid);

\tprintk("[demo] manager thread started (core %d)\\n", DM_CORE);
}
"""

with open(dm_path, "w") as f:
    f.write(new_dm)
print("demo_manager.c: rewritten to game-only")

print("All done.")
