#!/usr/bin/env python3
"""Rewrite screen_game.c with direct YUYV rendering for pipes/background.
LVGL is kept only for: player sprite, score label, status panel.
"""

PATH = "/home/m77107/zephyr_git/pic64gx-zephyr/demos/pic64_smp_hello/src/screen_game.c"

SRC = r"""/* SPDX-License-Identifier: Apache-2.0
 *
 * Flappy Bird mini-game for PIC64GX Curiosity Kit.
 *
 * Rendering strategy (optimised for 1280x720):
 *   - Background, ground, stars, pipes  → direct YUYV422 writes to framebuffer
 *   - Player sprite, score, status panel → LVGL (small, infrequent dirty regions)
 *
 * Eliminating LVGL from pipe rendering removes the RGB565→YUYV422 conversion
 * loop for ~200 K pixels/frame, cutting lv_timer_handler() time by ~8x.
 *
 * Controls
 *   SW2 (sw2 node, gpio2 pin 6) — flap / start / restart
 *   SW1+SW2 held 2 ticks         — restart game (handled by demo_manager)
 */

#include "screen_game.h"

#include <zephyr/kernel.h>
#include <zephyr/drivers/gpio.h>
#include <zephyr/sys/printk.h>
#include <lvgl.h>

#include "vdma_disp.h"

/* ── GPIO buttons ─────────────────────────────────────────────────────────── */
static const struct gpio_dt_spec btn_flap =
	GPIO_DT_SPEC_GET(DT_NODELABEL(sw2), gpios);
static const struct gpio_dt_spec btn_enter =
	GPIO_DT_SPEC_GET(DT_ALIAS(sw0), gpios);

/* ── Colours (RGB888 hex) ─────────────────────────────────────────────────── */
#define C_SKY      0x0D1117u
#define C_GROUND   0x3D2B1Fu
#define C_GROUND_H 0x6B4423u
#define C_PIPE     0x3FB950u
#define C_PIPE_CAP 0x2D8A3Au
#define C_MC_RED   0xC0392Bu
#define C_WHITE    0xE6EDF3u
#define C_YELLOW   0xD29922u
#define C_SUBTLE   0x8B949Eu
#define C_OVERLAY  0x161B22u
#define C_STAR     0x9999AAu   /* dim star colour (~60% white) */

/* ── Physics constants ────────────────────────────────────────────────────── */
#define GRAVITY     0.50f
#define FLAP_VEL  -11.00f
#define VEL_MAX    14.00f
#define SCROLL_SPD 11.00f

/* ── Layout constants ─────────────────────────────────────────────────────── */
#define SCR_W        1280
#define SCR_H         720
#define PLAYER_X      160
#define PLAYER_SZ      44
#define PIPE_W         80
#define PIPE_CAP_H     18
#define GAP_H         180
#define PIPE_SPACING  430
#define N_PIPES         3
#define GROUND_Y      672
#define GROUND_H       48
#define GAP_MIN       (GAP_H / 2 + 50)
#define GAP_MAX       (GROUND_Y - GAP_H / 2 - 50)
#define N_STARS        20

/* ── Game state ───────────────────────────────────────────────────────────── */
typedef enum { GAME_WAIT, GAME_PLAY, GAME_OVER } game_state_t;

static game_state_t state;
static float        py;
static float        vy;
static float        pipe_x[N_PIPES];
static int          gap_cy[N_PIPES];
static int          score;
static int          best_score;
static bool         scored[N_PIPES];
static bool         game_done;
static int          both_hold_count;

/* ── Direct YUYV framebuffer rendering ───────────────────────────────────── */
static uint8_t  *g_fb;         /* pointer to YUYV422 framebuffer             */
static uint32_t  YUYV_SKY;
static uint32_t  YUYV_GROUND;
static uint32_t  YUYV_GROUND_H;
static uint32_t  YUYV_PIPE;
static uint32_t  YUYV_PIPE_CAP;
static uint32_t  YUYV_STAR;

/* Convert RGB888 to packed YUYV422 uint32_t (same colour for both pixels). */
static uint32_t rgb_to_yuyv(uint32_t rgb)
{
	int r = (rgb >> 16) & 0xFF;
	int g = (rgb >>  8) & 0xFF;
	int b =  rgb        & 0xFF;
	int y = ((66 * r + 129 * g +  25 * b + 128) >> 8) + 16;
	int u = ((-38 * r -  74 * g + 112 * b + 128) >> 8) + 128;
	int v = ((112 * r -  94 * g -  18 * b + 128) >> 8) + 128;
	/* YUYV bytes: [Y0, U, Y1, V] → little-endian uint32 */
	return (uint32_t)(y | (u << 8) | (y << 16) | (v << 24));
}

/*
 * Fill a rectangle directly in the YUYV framebuffer.
 * x must be even; w is rounded up to the next even value.
 */
static void yuyv_fill(int x, int y, int w, int h, uint32_t yuyv)
{
	if (w <= 0 || h <= 0) {
		return;
	}
	x &= ~1;
	w = (w + 1) & ~1;
	if (x < 0)     { w += x; x = 0; }
	if (y < 0)     { h += y; y = 0; }
	if (x >= SCR_W || y >= SCR_H) {
		return;
	}
	if (x + w > SCR_W) { w = SCR_W - x; }
	if (y + h > SCR_H) { h = SCR_H - y; }
	if (w <= 0 || h <= 0) {
		return;
	}

	uint32_t *row = (uint32_t *)(g_fb + (size_t)y * (SCR_W * 2u) + (size_t)x * 2u);
	const int stride = SCR_W / 2;   /* uint32_t stride per row */
	const int fill_w = w / 2;       /* uint32_t words to write per row */

	for (int r = 0; r < h; r++, row += stride) {
		for (int c = 0; c < fill_w; c++) {
			row[c] = yuyv;
		}
	}
}

/* Draw the static background (sky, ground, stars) once per game session. */
static void draw_background(void)
{
	yuyv_fill(0, 0,        SCR_W, GROUND_Y, YUYV_SKY);
	yuyv_fill(0, GROUND_Y, SCR_W, GROUND_H, YUYV_GROUND);
	yuyv_fill(0, GROUND_Y, SCR_W, 4,        YUYV_GROUND_H);

	/* Stars — same xorshift seed as original LVGL version */
	uint32_t rng = 0xCAFEBABEu;

	for (int i = 0; i < N_STARS; i++) {
		rng ^= rng << 13;
		rng ^= rng >> 17;
		rng ^= rng << 5;
		int sx = (int)(rng % (uint32_t)SCR_W);

		rng ^= rng << 13;
		rng ^= rng >> 17;
		rng ^= rng << 5;
		int sy = (int)(rng % (uint32_t)(GROUND_Y - 20));
		int sz = (i % 3 == 0) ? 4 : 2;

		yuyv_fill(sx, sy, sz, sz, YUYV_STAR);
	}
}

/* Erase a pipe (replace its column with sky). */
static void pipe_erase(int i)
{
	int x = (int)pipe_x[i];

	if (x + PIPE_W + 6 <= 0 || x - 6 >= SCR_W) {
		return;
	}
	yuyv_fill(x - 6, 0, PIPE_W + 12, GROUND_Y, YUYV_SKY);
}

/* Draw a pipe at its current position. */
static void pipe_draw(int i)
{
	int x     = (int)pipe_x[i];
	int top_h = gap_cy[i] - GAP_H / 2;
	int bot_y = gap_cy[i] + GAP_H / 2;
	int bot_h = GROUND_Y - bot_y;

	if (x + PIPE_W + 6 <= 0 || x - 6 >= SCR_W) {
		return;
	}
	if (top_h < 0) { top_h = 0; }
	if (bot_h < 0) { bot_h = 0; }

	/* Top body */
	if (top_h > PIPE_CAP_H) {
		yuyv_fill(x, 0, PIPE_W, top_h - PIPE_CAP_H, YUYV_PIPE);
	}
	/* Top cap */
	if (top_h > 0) {
		yuyv_fill(x - 5, top_h - PIPE_CAP_H, PIPE_W + 10, PIPE_CAP_H, YUYV_PIPE_CAP);
	}
	/* Bottom cap */
	if (bot_h > 0) {
		yuyv_fill(x - 5, bot_y, PIPE_W + 10, PIPE_CAP_H, YUYV_PIPE_CAP);
	}
	/* Bottom body */
	if (bot_h > PIPE_CAP_H) {
		yuyv_fill(x, bot_y + PIPE_CAP_H, PIPE_W, bot_h - PIPE_CAP_H, YUYV_PIPE);
	}
}

/* ── Button edge detection ────────────────────────────────────────────────── */
static int  prev_flap_state;
static int  prev_enter_state;
static bool btn_inited;

static void btn_init_once(void)
{
	if (btn_inited) {
		return;
	}
	if (gpio_is_ready_dt(&btn_flap)) {
		gpio_pin_configure_dt(&btn_flap, GPIO_INPUT);
	}
	if (gpio_is_ready_dt(&btn_enter)) {
		gpio_pin_configure_dt(&btn_enter, GPIO_INPUT);
	}
	prev_flap_state  = gpio_pin_get_dt(&btn_flap);
	prev_enter_state = gpio_pin_get_dt(&btn_enter);
	btn_inited = true;
}

static bool flap_edge(void)
{
	int cur  = gpio_pin_get_dt(&btn_flap);
	bool edge = (cur == 1) && (prev_flap_state == 0);

	prev_flap_state = cur;
	return edge;
}

/* ── LVGL widget handles (minimal set) ───────────────────────────────────── */
static lv_obj_t  *player_obj;
static lv_obj_t  *score_lbl;
static lv_obj_t  *status_panel;
static lv_obj_t  *status_lbl;
static lv_obj_t  *sub_lbl;
static lv_timer_t *game_timer;

/* ── Random number (xorshift) ─────────────────────────────────────────────── */
static uint32_t rng_state = 0xDEADBEEFu;

static int rand_gap_cy(void)
{
	rng_state ^= rng_state << 13;
	rng_state ^= rng_state >> 17;
	rng_state ^= rng_state << 5;
	return GAP_MIN + (int)(rng_state % (uint32_t)(GAP_MAX - GAP_MIN));
}

/* ── Pipe helpers ─────────────────────────────────────────────────────────── */
static void pipe_reset(int i, float x)
{
	pipe_x[i]  = x;
	gap_cy[i]  = rand_gap_cy();
	scored[i]  = false;
}

static float pipes_rightmost_x(void)
{
	float mx = pipe_x[0];

	for (int i = 1; i < N_PIPES; i++) {
		if (pipe_x[i] > mx) {
			mx = pipe_x[i];
		}
	}
	return mx;
}

/* ── Collision (AABB) ─────────────────────────────────────────────────────── */
static bool rects_overlap(int ax1, int ay1, int ax2, int ay2,
			   int bx1, int by1, int bx2, int by2)
{
	return ax1 < bx2 && ax2 > bx1 && ay1 < by2 && ay2 > by1;
}

static bool check_collision(void)
{
	int px1 = PLAYER_X + 4;
	int py1 = (int)py + 4;
	int px2 = PLAYER_X + PLAYER_SZ - 4;
	int py2 = (int)py + PLAYER_SZ - 4;

	if (py2 >= GROUND_Y || py1 <= 0) {
		return true;
	}
	for (int i = 0; i < N_PIPES; i++) {
		int ix    = (int)pipe_x[i];
		int top_h = gap_cy[i] - GAP_H / 2;
		int bot_y = gap_cy[i] + GAP_H / 2;

		if (rects_overlap(px1, py1, px2, py2, ix, 0, ix + PIPE_W, top_h)) {
			return true;
		}
		if (rects_overlap(px1, py1, px2, py2, ix, bot_y, ix + PIPE_W, GROUND_Y)) {
			return true;
		}
	}
	return false;
}

/* ── Score label ─────────────────────────────────────────────────────────── */
static void score_update(void)
{
	char buf[16];

	snprintk(buf, sizeof(buf), "%d", score);
	lv_label_set_text(score_lbl, buf);
}

/* ── Status overlay ──────────────────────────────────────────────────────── */
static void status_show(const char *main_text, const char *sub_text)
{
	lv_obj_clear_flag(status_panel, LV_OBJ_FLAG_HIDDEN);
	lv_label_set_text(status_lbl, main_text);
	lv_label_set_text(sub_lbl, sub_text ? sub_text : "");
}

static void status_hide(void)
{
	lv_obj_add_flag(status_panel, LV_OBJ_FLAG_HIDDEN);
}

/* ── Game state transitions ───────────────────────────────────────────────── */
static void game_reset(void)
{
	py    = 300.0f;
	vy    = 0.0f;
	score = 0;

	for (int i = 0; i < N_PIPES; i++) {
		pipe_erase(i);
		pipe_reset(i, (float)(SCR_W + i * PIPE_SPACING));
	}

	score_update();
	lv_obj_set_pos(player_obj, PLAYER_X, (int)py);
}

static void enter_wait(void)
{
	state = GAME_WAIT;
	game_reset();
	status_show("FLAPPY MICROCHIP", "Press JUMP (SW2) to start");
	lv_obj_set_style_text_color(status_lbl, lv_color_hex(C_MC_RED), LV_PART_MAIN);
}

static void enter_play(void)
{
	state = GAME_PLAY;
	status_hide();
}

static void enter_over(void)
{
	char buf[64];

	state = GAME_OVER;

	if (score > best_score) {
		best_score = score;
	}

	snprintk(buf, sizeof(buf), "GAME OVER    %d pts", score);

	if (score > 0 && score == best_score) {
		lv_label_set_text(sub_lbl, "New best!  SW1+SW2: restart");
		lv_obj_set_style_text_color(sub_lbl, lv_color_hex(C_YELLOW), LV_PART_MAIN);
	} else {
		char sub[40];

		snprintk(sub, sizeof(sub), "Best: %d  SW1+SW2: restart", best_score);
		lv_label_set_text(sub_lbl, sub);
		lv_obj_set_style_text_color(sub_lbl, lv_color_hex(C_SUBTLE), LV_PART_MAIN);
	}
	lv_obj_clear_flag(status_panel, LV_OBJ_FLAG_HIDDEN);
	lv_label_set_text(status_lbl, buf);
	lv_obj_set_style_text_color(status_lbl, lv_color_hex(C_WHITE), LV_PART_MAIN);
}

/* ── 20 ms physics tick ───────────────────────────────────────────────────── */
static void game_tick_cb(lv_timer_t *t)
{
	ARG_UNUSED(t);

	btn_init_once();

	/* Both SW1+SW2 held 2 ticks → signal restart to demo_manager */
	if (gpio_pin_get_dt(&btn_flap) == 1 &&
	    gpio_pin_get_dt(&btn_enter) == 1) {
		if (++both_hold_count >= 2) {
			both_hold_count = 0;
			game_done = true;
			return;
		}
	} else {
		both_hold_count = 0;
	}

	bool flap = flap_edge();

	switch (state) {
	case GAME_WAIT:
		if (flap) {
			enter_play();
		}
		/* Gentle hover */
		vy += 0.1f;
		py += vy;
		if (py > 320.0f || py < 280.0f) {
			vy = -vy * 0.8f;
			py = CLAMP(py, 280.0f, 320.0f);
		}
		lv_obj_set_pos(player_obj, PLAYER_X, (int)py);
		break;

	case GAME_PLAY:
		/* Player physics */
		vy += GRAVITY;
		if (vy > VEL_MAX) {
			vy = VEL_MAX;
		}
		if (flap) {
			vy = FLAP_VEL;
		}
		py += vy;
		lv_obj_set_pos(player_obj, PLAYER_X, (int)py);

		/* Erase old pipe positions */
		for (int i = 0; i < N_PIPES; i++) {
			pipe_erase(i);
		}

		/* Move pipes */
		for (int i = 0; i < N_PIPES; i++) {
			pipe_x[i] -= SCROLL_SPD;

			int centre = (int)pipe_x[i] + PIPE_W / 2;

			if (!scored[i] && centre < PLAYER_X) {
				scored[i] = true;
				score++;
				score_update();
			}

			if (pipe_x[i] + PIPE_W < 0) {
				pipe_reset(i, pipes_rightmost_x() + PIPE_SPACING);
			}
		}

		/* Draw pipes at new positions */
		for (int i = 0; i < N_PIPES; i++) {
			pipe_draw(i);
		}

		/* Restore ground highlight (pipes may have overwritten edge row) */
		yuyv_fill(0, GROUND_Y, SCR_W, 4, YUYV_GROUND_H);

		if (check_collision()) {
			enter_over();
		}
		break;

	case GAME_OVER:
		/* SW2 = restart */
		if (flap) {
			enter_wait();
		}
		break;
	}
}

/* ── Screen delete cleanup ────────────────────────────────────────────────── */
static void game_screen_delete_cb(lv_event_t *e)
{
	ARG_UNUSED(e);

	if (game_timer) {
		lv_timer_delete(game_timer);
		game_timer = NULL;
	}
	player_obj   = NULL;
	score_lbl    = NULL;
	status_panel = NULL;
	status_lbl   = NULL;
	sub_lbl      = NULL;
}

/* ── Screen construction ─────────────────────────────────────────────────── */
lv_obj_t *screen_game_create(void)
{
	game_done       = false;
	btn_inited      = false;
	both_hold_count = 0;

	/* ── Initialise YUYV colours and paint background ─────────────────── */
	g_fb          = vdma_disp_front_buf(DEVICE_DT_GET(DT_NODELABEL(vdma_disp)));
	YUYV_SKY      = rgb_to_yuyv(C_SKY);
	YUYV_GROUND   = rgb_to_yuyv(C_GROUND);
	YUYV_GROUND_H = rgb_to_yuyv(C_GROUND_H);
	YUYV_PIPE     = rgb_to_yuyv(C_PIPE);
	YUYV_PIPE_CAP = rgb_to_yuyv(C_PIPE_CAP);
	YUYV_STAR     = rgb_to_yuyv(C_STAR);
	draw_background();

	/* ── LVGL screen (transparent bg — we own the framebuffer) ────────── */
	lv_obj_t *scr = lv_obj_create(NULL);

	lv_obj_set_style_bg_color(scr, lv_color_hex(C_SKY), LV_PART_MAIN);
	lv_obj_set_style_bg_opa(scr, LV_OPA_COVER, LV_PART_MAIN);
	lv_obj_set_scrollbar_mode(scr, LV_SCROLLBAR_MODE_OFF);

	/* ── Player: Microchip logo (red rounded rect + white M) ─────────── */
	player_obj = lv_obj_create(scr);
	lv_obj_set_size(player_obj, PLAYER_SZ, PLAYER_SZ);
	lv_obj_set_style_bg_color(player_obj, lv_color_hex(C_MC_RED), LV_PART_MAIN);
	lv_obj_set_style_bg_opa(player_obj, LV_OPA_COVER, LV_PART_MAIN);
	lv_obj_set_style_border_width(player_obj, 0, LV_PART_MAIN);
	lv_obj_set_style_radius(player_obj, 8, LV_PART_MAIN);
	lv_obj_set_style_pad_all(player_obj, 0, LV_PART_MAIN);
	lv_obj_set_scrollbar_mode(player_obj, LV_SCROLLBAR_MODE_OFF);

	lv_obj_t *m_lbl = lv_label_create(player_obj);

	lv_label_set_text(m_lbl, "M");
	lv_obj_set_style_text_font(m_lbl, &lv_font_montserrat_32, LV_PART_MAIN);
	lv_obj_set_style_text_color(m_lbl, lv_color_white(), LV_PART_MAIN);
	lv_obj_align(m_lbl, LV_ALIGN_CENTER, 0, 0);

	/* ── Score label ─────────────────────────────────────────────────── */
	score_lbl = lv_label_create(scr);
	lv_label_set_text(score_lbl, "0");
	lv_obj_set_style_text_font(score_lbl, &lv_font_montserrat_48, LV_PART_MAIN);
	lv_obj_set_style_text_color(score_lbl, lv_color_white(), LV_PART_MAIN);
	lv_obj_align(score_lbl, LV_ALIGN_TOP_MID, 0, 12);

	/* ── Status overlay ──────────────────────────────────────────────── */
	status_panel = lv_obj_create(scr);
	lv_obj_set_size(status_panel, 700, 150);
	lv_obj_align(status_panel, LV_ALIGN_CENTER, 0, 0);
	lv_obj_set_style_bg_color(status_panel, lv_color_hex(C_OVERLAY), LV_PART_MAIN);
	lv_obj_set_style_bg_opa(status_panel, LV_OPA_80, LV_PART_MAIN);
	lv_obj_set_style_border_color(status_panel, lv_color_hex(C_MC_RED), LV_PART_MAIN);
	lv_obj_set_style_border_width(status_panel, 2, LV_PART_MAIN);
	lv_obj_set_style_radius(status_panel, 10, LV_PART_MAIN);
	lv_obj_set_scrollbar_mode(status_panel, LV_SCROLLBAR_MODE_OFF);

	status_lbl = lv_label_create(status_panel);
	lv_label_set_text(status_lbl, "");
	lv_obj_set_style_text_font(status_lbl, &lv_font_montserrat_32, LV_PART_MAIN);
	lv_obj_set_style_text_color(status_lbl, lv_color_white(), LV_PART_MAIN);
	lv_obj_align(status_lbl, LV_ALIGN_CENTER, 0, -22);

	sub_lbl = lv_label_create(status_panel);
	lv_label_set_text(sub_lbl, "");
	lv_obj_set_style_text_font(sub_lbl, &lv_font_montserrat_20, LV_PART_MAIN);
	lv_obj_set_style_text_color(sub_lbl, lv_color_hex(C_SUBTLE), LV_PART_MAIN);
	lv_obj_align(sub_lbl, LV_ALIGN_CENTER, 0, 20);

	/* ── Initialise to WAIT state ────────────────────────────────────── */
	enter_wait();

	/* ── Game timer: 20 ms physics loop ─────────────────────────────── */
	game_timer = lv_timer_create(game_tick_cb, 20, NULL);

	lv_obj_add_event_cb(scr, game_screen_delete_cb, LV_EVENT_DELETE, NULL);

	return scr;
}

void screen_game_update(void)
{
	/* Physics driven by game_timer; nothing to do at 1 Hz. */
}

bool screen_game_is_done(void)
{
	if (game_done) {
		game_done = false;
		return true;
	}
	return false;
}
"""

with open(PATH, "w") as f:
    f.write(SRC)
print(f"Written {len(SRC.splitlines())} lines to {PATH}")
