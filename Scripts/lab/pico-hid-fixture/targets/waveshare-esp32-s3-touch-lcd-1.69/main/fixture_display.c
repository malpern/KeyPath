#include "fixture_display.h"

#include <inttypes.h>
#include <math.h>
#include <stdio.h>

#include "bsp/esp32_s3_touch_lcd_1_69.h"
#include "esp_timer.h"
#include "fixture_board.h"
#include "fixture_runtime.h"
#include "fixture_splash_model.h"
#include "fixture_visual_model.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "lvgl.h"
#include "sdkconfig.h"

#define PARTICLE_COUNT 12u
#define KEY_COUNT 6u
#define DOJO_BAR_COUNT 4u
#define SPLASH_FRAME_INTERVAL_MS 33u
#define DISPLAY_HEARTBEAT_MAX_AGE_MS 2000u

typedef struct {
    lv_obj_t *screen;
    lv_obj_t *halo_outer;
    lv_obj_t *halo_inner;
    lv_obj_t *orbit;
    lv_obj_t *progress;
    lv_obj_t *core;
    lv_obj_t *brand_keycap;
    lv_obj_t *brand_light;
    lv_obj_t *brand_fill;
    lv_obj_t *brand_lid;
    lv_obj_t *brand_glint_horizontal;
    lv_obj_t *brand_glint_vertical;
    lv_obj_t *icon_front;
    lv_obj_t *icon_back;
    lv_obj_t *keys[KEY_COUNT];
    lv_obj_t *particles[PARTICLE_COUNT];
    lv_obj_t *eyebrow;
    lv_obj_t *state;
    lv_obj_t *detail;
    lv_obj_t *quality;
    fixture_ui_scene_t previous_scene;
    fixture_result_t previous_result;
    int visual_stage;
    float phase;
    uint64_t previous_render_ms;
    uint64_t icon_transition_started_ms;
    uint64_t completion_started_ms;
    uint64_t button_feedback_started_ms;
    uint32_t button_feedback_sequence;
    fixture_button_event_t button_feedback_event;
} display_ui_t;

typedef struct {
    lv_obj_t *root;
    lv_obj_t *glow;
    lv_obj_t *ring;
    lv_obj_t *logo;
    lv_obj_t *bars[DOJO_BAR_COUNT];
    lv_obj_t *wordmark;
    lv_obj_t *location;
} display_splash_t;

static display_ui_t ui;
static display_splash_t splash;
static portMUX_TYPE display_health_lock = portMUX_INITIALIZER_UNLOCKED;
static fixture_display_health_t display_health;

static void note_display_frame(uint64_t now_ms) {
    taskENTER_CRITICAL(&display_health_lock);
    display_health.frame_sequence++;
    display_health.last_frame_ms = now_ms;
    taskEXIT_CRITICAL(&display_health_lock);
}

static void note_display_initialized(bool splash_enabled, bool splash_complete) {
    taskENTER_CRITICAL(&display_health_lock);
    display_health.initialized = true;
    display_health.splash_enabled = splash_enabled;
    display_health.splash_complete = splash_complete;
    taskEXIT_CRITICAL(&display_health_lock);
}

static void note_splash_complete(void) {
    taskENTER_CRITICAL(&display_health_lock);
    display_health.splash_complete = true;
    taskEXIT_CRITICAL(&display_health_lock);
}

static const char *symbol_for(fixture_visual_icon_t icon) {
    switch (icon) {
        case FIXTURE_ICON_POWER: return LV_SYMBOL_POWER;
        case FIXTURE_ICON_WIFI: return LV_SYMBOL_WIFI;
        case FIXTURE_ICON_KEYBOARD: return LV_SYMBOL_KEYBOARD;
        case FIXTURE_ICON_DOWNLOAD: return LV_SYMBOL_DOWNLOAD;
        case FIXTURE_ICON_WARNING: return LV_SYMBOL_WARNING;
        case FIXTURE_ICON_PLAY: return LV_SYMBOL_PLAY;
        case FIXTURE_ICON_OK: return LV_SYMBOL_OK;
        case FIXTURE_ICON_STOP: return LV_SYMBOL_STOP;
        case FIXTURE_ICON_CLOSE: return LV_SYMBOL_CLOSE;
        case FIXTURE_ICON_REFRESH: return LV_SYMBOL_REFRESH;
        case FIXTURE_ICON_BELL: return LV_SYMBOL_BELL;
        case FIXTURE_ICON_EYE: return LV_SYMBOL_EYE_OPEN;
        case FIXTURE_ICON_SETTINGS: return LV_SYMBOL_SETTINGS;
        case FIXTURE_ICON_NEXT: return LV_SYMBOL_NEXT;
    }
    return LV_SYMBOL_WARNING;
}

static lv_obj_t *make_circle(lv_obj_t *parent, int size, lv_color_t color, lv_opa_t opacity) {
    lv_obj_t *object = lv_obj_create(parent);
    lv_obj_remove_style_all(object);
    lv_obj_set_size(object, size, size);
    lv_obj_set_style_radius(object, LV_RADIUS_CIRCLE, 0);
    lv_obj_set_style_bg_color(object, color, 0);
    lv_obj_set_style_bg_opa(object, opacity, 0);
    lv_obj_clear_flag(object, LV_OBJ_FLAG_CLICKABLE);
    return object;
}

static lv_obj_t *make_rect(lv_obj_t *parent, int x, int y, int width, int height,
                           lv_color_t color) {
    lv_obj_t *object = lv_obj_create(parent);
    lv_obj_remove_style_all(object);
    lv_obj_set_pos(object, x, y);
    lv_obj_set_size(object, width, height);
    lv_obj_set_style_radius(object, 2, 0);
    lv_obj_set_style_bg_color(object, color, 0);
    lv_obj_set_style_bg_opa(object, LV_OPA_COVER, 0);
    lv_obj_clear_flag(object, LV_OBJ_FLAG_CLICKABLE);
    return object;
}

static void set_hidden(lv_obj_t *object, bool hidden) {
    if (hidden) {
        lv_obj_add_flag(object, LV_OBJ_FLAG_HIDDEN);
    } else {
        lv_obj_clear_flag(object, LV_OBJ_FLAG_HIDDEN);
    }
}

static void touch_event(lv_event_t *event) {
    if (lv_event_get_code(event) != LV_EVENT_PRESSED) return;
    fixture_runtime_snapshot_t snapshot;
    fixture_runtime_snapshot(&snapshot);
    if (snapshot.ui.state == FIXTURE_ARMED) {
        char error[128];
        if (fixture_runtime_start_demo(error, sizeof(error))) {
            fixture_board_tone(980u, 70u);
            return;
        }
        lv_obj_set_style_bg_color(ui.screen, lv_color_hex(0x241323), 0);
        fixture_runtime_abort("touch abort");
        fixture_board_tone(220u, 90u);
    } else if (snapshot.ui.state == FIXTURE_RUNNING) {
        lv_obj_set_style_bg_color(ui.screen, lv_color_hex(0x241323), 0);
        fixture_runtime_abort("touch abort");
        fixture_board_tone(220u, 90u);
    }
}

static void build_ui(void) {
    ui.screen = lv_screen_active();
    lv_obj_remove_style_all(ui.screen);
    lv_obj_set_style_bg_color(ui.screen, lv_color_hex(0x071117), 0);
    lv_obj_set_style_bg_opa(ui.screen, LV_OPA_COVER, 0);
    lv_obj_add_flag(ui.screen, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_add_event_cb(ui.screen, touch_event, LV_EVENT_PRESSED, NULL);

    ui.eyebrow = lv_label_create(ui.screen);
    lv_label_set_text_static(ui.eyebrow, "KEYPATH  /  HID ORACLE");
    lv_obj_set_style_text_font(ui.eyebrow, &lv_font_montserrat_12, 0);
    lv_obj_set_style_text_color(ui.eyebrow, lv_color_hex(0x71909d), 0);
    lv_obj_set_style_text_letter_space(ui.eyebrow, 2, 0);
    lv_obj_align(ui.eyebrow, LV_ALIGN_TOP_MID, 0, 15);

    ui.halo_outer = make_circle(ui.screen, 154, lv_color_hex(0x173946), LV_OPA_20);
    lv_obj_align(ui.halo_outer, LV_ALIGN_CENTER, 0, -2);
    ui.halo_inner = make_circle(ui.screen, 124, lv_color_hex(0x153541), LV_OPA_30);
    lv_obj_align(ui.halo_inner, LV_ALIGN_CENTER, 0, -2);

    ui.orbit = lv_arc_create(ui.screen);
    lv_obj_set_size(ui.orbit, 142, 142);
    lv_obj_align(ui.orbit, LV_ALIGN_CENTER, 0, -2);
    lv_arc_set_bg_angles(ui.orbit, 0, 360);
    lv_arc_set_angles(ui.orbit, 20, 104);
    lv_obj_set_style_arc_width(ui.orbit, 2, LV_PART_MAIN);
    lv_obj_set_style_arc_color(ui.orbit, lv_color_hex(0x183943), LV_PART_MAIN);
    lv_obj_set_style_arc_width(ui.orbit, 4, LV_PART_INDICATOR);
    lv_obj_set_style_arc_rounded(ui.orbit, true, LV_PART_INDICATOR);
    lv_obj_set_style_bg_opa(ui.orbit, LV_OPA_TRANSP, LV_PART_KNOB);
    lv_obj_clear_flag(ui.orbit, LV_OBJ_FLAG_CLICKABLE);

    ui.progress = lv_arc_create(ui.screen);
    lv_obj_set_size(ui.progress, 112, 112);
    lv_obj_align(ui.progress, LV_ALIGN_CENTER, 0, -2);
    lv_arc_set_range(ui.progress, 0, 1000);
    lv_arc_set_bg_angles(ui.progress, 135, 45);
    lv_arc_set_value(ui.progress, 0);
    lv_obj_set_style_arc_width(ui.progress, 5, LV_PART_MAIN);
    lv_obj_set_style_arc_color(ui.progress, lv_color_hex(0x18343e), LV_PART_MAIN);
    lv_obj_set_style_arc_width(ui.progress, 5, LV_PART_INDICATOR);
    lv_obj_set_style_arc_rounded(ui.progress, true, LV_PART_INDICATOR);
    lv_obj_set_style_bg_opa(ui.progress, LV_OPA_TRANSP, LV_PART_KNOB);
    lv_obj_clear_flag(ui.progress, LV_OBJ_FLAG_CLICKABLE);

    ui.core = make_circle(ui.screen, 76, lv_color_hex(0x0d2028), LV_OPA_COVER);
    lv_obj_set_style_border_width(ui.core, 1, 0);
    lv_obj_set_style_border_color(ui.core, lv_color_hex(0x2f6970), 0);
    lv_obj_align(ui.core, LV_ALIGN_CENTER, 0, -2);

    ui.icon_back = lv_label_create(ui.screen);
    lv_label_set_text_static(ui.icon_back, LV_SYMBOL_POWER);
    lv_obj_set_style_text_font(ui.icon_back, &lv_font_montserrat_20, 0);
    lv_obj_set_style_text_opa(ui.icon_back, LV_OPA_TRANSP, 0);
    lv_obj_align(ui.icon_back, LV_ALIGN_CENTER, 0, -2);
    ui.icon_front = lv_label_create(ui.screen);
    lv_label_set_text_static(ui.icon_front, LV_SYMBOL_POWER);
    lv_obj_set_style_text_font(ui.icon_front, &lv_font_montserrat_20, 0);
    lv_obj_align(ui.icon_front, LV_ALIGN_CENTER, 0, -2);

    for (size_t index = 0; index < KEY_COUNT; ++index) {
        ui.keys[index] = lv_obj_create(ui.core);
        lv_obj_remove_style_all(ui.keys[index]);
        lv_obj_set_size(ui.keys[index], 17, 14);
        lv_obj_set_style_radius(ui.keys[index], 4, 0);
        lv_obj_set_style_bg_color(ui.keys[index], lv_color_hex(0x56ddb3), 0);
        lv_obj_set_style_bg_opa(ui.keys[index], LV_OPA_30, 0);
        int column = (int)(index % 3u);
        int row = (int)(index / 3u);
        lv_obj_set_pos(ui.keys[index], 8 + column * 21, 17 + row * 19);
    }

    /* Display-native reconstruction of KeyPath's opened, illuminated keycap. */
    ui.brand_keycap = lv_obj_create(ui.screen);
    lv_obj_remove_style_all(ui.brand_keycap);
    lv_obj_set_size(ui.brand_keycap, 78, 62);
    lv_obj_set_style_radius(ui.brand_keycap, 17, 0);
    lv_obj_set_style_bg_color(ui.brand_keycap, lv_color_hex(0xd95b18), 0);
    lv_obj_set_style_bg_opa(ui.brand_keycap, LV_OPA_COVER, 0);
    lv_obj_set_style_shadow_color(ui.brand_keycap, lv_color_hex(0xf3a128), 0);
    lv_obj_set_style_shadow_width(ui.brand_keycap, 18, 0);
    lv_obj_set_style_shadow_opa(ui.brand_keycap, LV_OPA_20, 0);
    lv_obj_align(ui.brand_keycap, LV_ALIGN_CENTER, 0, 5);
    lv_obj_clear_flag(ui.brand_keycap, LV_OBJ_FLAG_CLICKABLE);

    ui.brand_light = lv_obj_create(ui.screen);
    lv_obj_remove_style_all(ui.brand_light);
    lv_obj_set_size(ui.brand_light, 54, 38);
    lv_obj_set_style_radius(ui.brand_light, 12, 0);
    lv_obj_set_style_bg_color(ui.brand_light, lv_color_hex(0xfff2c9), 0);
    lv_obj_set_style_bg_opa(ui.brand_light, LV_OPA_COVER, 0);
    lv_obj_align(ui.brand_light, LV_ALIGN_CENTER, 0, 2);
    lv_obj_clear_flag(ui.brand_light, LV_OBJ_FLAG_CLICKABLE);

    ui.brand_fill = lv_obj_create(ui.brand_light);
    lv_obj_remove_style_all(ui.brand_fill);
    lv_obj_set_size(ui.brand_fill, 54, 1);
    lv_obj_set_style_radius(ui.brand_fill, 10, 0);
    lv_obj_set_style_bg_color(ui.brand_fill, lv_color_hex(0xf3a128), 0);
    lv_obj_set_style_bg_opa(ui.brand_fill, LV_OPA_60, 0);
    lv_obj_align(ui.brand_fill, LV_ALIGN_BOTTOM_MID, 0, 0);
    lv_obj_clear_flag(ui.brand_fill, LV_OBJ_FLAG_CLICKABLE);

    ui.brand_lid = lv_obj_create(ui.screen);
    lv_obj_remove_style_all(ui.brand_lid);
    lv_obj_set_size(ui.brand_lid, 68, 27);
    lv_obj_set_style_radius(ui.brand_lid, 10, 0);
    lv_obj_set_style_bg_color(ui.brand_lid, lv_color_hex(0xf3a128), 0);
    lv_obj_set_style_bg_opa(ui.brand_lid, LV_OPA_COVER, 0);
    lv_obj_set_style_shadow_color(ui.brand_lid, lv_color_hex(0xffd36a), 0);
    lv_obj_set_style_shadow_width(ui.brand_lid, 12, 0);
    lv_obj_set_style_shadow_opa(ui.brand_lid, LV_OPA_20, 0);
    lv_obj_align(ui.brand_lid, LV_ALIGN_CENTER, 0, -29);
    lv_obj_clear_flag(ui.brand_lid, LV_OBJ_FLAG_CLICKABLE);

    ui.brand_glint_horizontal = make_rect(
        ui.screen, 0, 0, 12, 2, lv_color_hex(0xfff7df));
    ui.brand_glint_vertical = make_rect(
        ui.screen, 0, 0, 2, 12, lv_color_hex(0xfff7df));
    lv_obj_set_style_radius(ui.brand_glint_horizontal, LV_RADIUS_CIRCLE, 0);
    lv_obj_set_style_radius(ui.brand_glint_vertical, LV_RADIUS_CIRCLE, 0);

    set_hidden(ui.brand_keycap, true);
    set_hidden(ui.brand_light, true);
    set_hidden(ui.brand_lid, true);
    set_hidden(ui.brand_glint_horizontal, true);
    set_hidden(ui.brand_glint_vertical, true);

    for (size_t index = 0; index < PARTICLE_COUNT; ++index) {
        ui.particles[index] = make_circle(ui.screen, index % 3u == 0u ? 6 : 4,
                                          lv_color_hex(0x56ddb3), LV_OPA_50);
    }

    ui.state = lv_label_create(ui.screen);
    lv_label_set_text_static(ui.state, "WAKING UP");
    lv_obj_set_style_text_font(ui.state, &lv_font_montserrat_24, 0);
    lv_obj_set_style_text_color(ui.state, lv_color_hex(0xe9f7f4), 0);
    lv_obj_set_width(ui.state, 220);
    lv_label_set_long_mode(ui.state, LV_LABEL_LONG_DOT);
    lv_obj_set_style_text_align(ui.state, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_align(ui.state, LV_ALIGN_BOTTOM_MID, 0, -40);

    ui.detail = lv_label_create(ui.screen);
    lv_label_set_text_static(ui.detail, "USB + Wi-Fi control");
    lv_obj_set_style_text_font(ui.detail, &lv_font_montserrat_14, 0);
    lv_obj_set_style_text_color(ui.detail, lv_color_hex(0x78909a), 0);
    lv_obj_set_width(ui.detail, 220);
    lv_label_set_long_mode(ui.detail, LV_LABEL_LONG_DOT);
    lv_obj_set_style_text_align(ui.detail, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_align(ui.detail, LV_ALIGN_BOTTOM_MID, 0, -20);

    ui.quality = lv_label_create(ui.screen);
    lv_label_set_text_static(ui.quality, "CINEMATIC");
    lv_obj_set_style_text_font(ui.quality, &lv_font_montserrat_12, 0);
    lv_obj_set_style_text_color(ui.quality, lv_color_hex(0x52727e), 0);
    lv_obj_set_style_text_letter_space(ui.quality, 1, 0);
    lv_obj_align(ui.quality, LV_ALIGN_TOP_RIGHT, -10, 38);
    ui.previous_scene = FIXTURE_UI_BOOT;
    ui.visual_stage = -1;
}

static void build_splash(void) {
    lv_color_t dojo_red = lv_color_hex(0xe13838);
    lv_color_t white = lv_color_hex(0xffffff);

    splash.root = lv_obj_create(ui.screen);
    lv_obj_remove_style_all(splash.root);
    lv_obj_set_size(splash.root, LV_PCT(100), LV_PCT(100));
    lv_obj_align(splash.root, LV_ALIGN_CENTER, 0, 0);
    lv_obj_set_style_bg_color(splash.root, lv_color_hex(0x080c10), 0);
    lv_obj_set_style_bg_opa(splash.root, LV_OPA_COVER, 0);
    lv_obj_clear_flag(splash.root, LV_OBJ_FLAG_SCROLLABLE | LV_OBJ_FLAG_CLICKABLE);

    /*
     * Keep the glow inside a bounded redraw region. Transforming the previous
     * 154 px object at 60 FPS invalidated most of the 240 x 280 display and
     * could starve the LVGL flush task on the physical SPI panel.
     */
    splash.glow = make_circle(splash.root, 132, dojo_red, LV_OPA_TRANSP);
    lv_obj_align(splash.glow, LV_ALIGN_CENTER, 0, -27);

    splash.ring = make_circle(splash.root, 118, dojo_red, LV_OPA_TRANSP);
    lv_obj_set_style_border_width(splash.ring, 2, 0);
    lv_obj_set_style_border_color(splash.ring, dojo_red, 0);
    lv_obj_set_style_border_opa(splash.ring, LV_OPA_TRANSP, 0);
    lv_obj_align(splash.ring, LV_ALIGN_CENTER, 0, -27);

    splash.logo = lv_obj_create(splash.root);
    lv_obj_remove_style_all(splash.logo);
    lv_obj_set_size(splash.logo, 92, 92);
    lv_obj_set_style_radius(splash.logo, 24, 0);
    lv_obj_set_style_bg_color(splash.logo, dojo_red, 0);
    lv_obj_set_style_bg_opa(splash.logo, LV_OPA_TRANSP, 0);
    lv_obj_align(splash.logo, LV_ALIGN_CENTER, 0, -27);

    /* Faithful, display-native reconstruction of hackerdojo.org/static/images/logo.png. */
    splash.bars[0] = make_rect(splash.logo, 20, 29, 52, 5, white);
    splash.bars[1] = make_rect(splash.logo, 16, 40, 60, 5, white);
    splash.bars[2] = make_rect(splash.logo, 31, 26, 5, 41, white);
    splash.bars[3] = make_rect(splash.logo, 56, 26, 5, 41, white);

    splash.wordmark = lv_label_create(splash.root);
    lv_label_set_text_static(splash.wordmark, "HACKER DOJO");
    lv_obj_set_style_text_font(splash.wordmark, &lv_font_montserrat_24, 0);
    lv_obj_set_style_text_color(splash.wordmark, white, 0);
    lv_obj_set_style_text_letter_space(splash.wordmark, 3, 0);
    lv_obj_set_style_text_opa(splash.wordmark, LV_OPA_TRANSP, 0);
    lv_obj_align(splash.wordmark, LV_ALIGN_CENTER, 0, 48);

    splash.location = lv_label_create(splash.root);
    lv_label_set_text_static(splash.location, "MOUNTAIN VIEW  /  SINCE 2009");
    lv_obj_set_style_text_font(splash.location, &lv_font_montserrat_12, 0);
    lv_obj_set_style_text_color(splash.location, lv_color_hex(0x9aa7ad), 0);
    lv_obj_set_style_text_letter_space(splash.location, 1, 0);
    lv_obj_set_style_text_opa(splash.location, LV_OPA_TRANSP, 0);
    lv_obj_align(splash.location, LV_ALIGN_CENTER, 0, 74);
}

static void render_splash(const fixture_splash_output_t *output, uint64_t elapsed_ms) {
    lv_opa_t foreground = (lv_opa_t)output->foreground_opacity;
    /*
     * Do not animate opacity on the full-screen root. The logo and wordmark
     * still fade out before the root is deleted, but every frame now redraws
     * only the splash artwork rather than the entire panel.
     */
    lv_obj_set_style_bg_opa(splash.root, LV_OPA_COVER, 0);
    lv_obj_set_style_bg_opa(splash.logo, foreground, 0);
    for (size_t index = 0; index < DOJO_BAR_COUNT; ++index) {
        lv_obj_set_style_bg_opa(splash.bars[index], foreground, 0);
    }

    lv_obj_set_style_text_opa(splash.wordmark, (lv_opa_t)output->wordmark_opacity, 0);
    lv_obj_set_style_text_opa(splash.location,
                              (lv_opa_t)(output->wordmark_opacity * 3u / 4u), 0);
    int wordmark_offset = 5 - (int)(output->wordmark_opacity * 5u / 255u);
    lv_obj_set_style_translate_y(splash.wordmark, wordmark_offset, 0);
    lv_obj_set_style_translate_y(splash.location, wordmark_offset, 0);

    uint16_t ring_phase = (uint16_t)(elapsed_ms % 800u);
    uint16_t ring_fade = (uint16_t)(255u - ring_phase * 255u / 800u);
    lv_obj_set_style_border_opa(
        splash.ring,
        (lv_opa_t)(output->foreground_opacity * ring_fade * 44u / (255u * 255u)), 0);

    int glow_pulse = (int)(sinf((float)elapsed_ms / 230.0f) * 4.0f);
    lv_obj_set_style_bg_opa(splash.glow,
                            (lv_opa_t)(output->foreground_opacity *
                                       (uint32_t)(22 + glow_pulse) / 255u), 0);
}

static void play_splash(void) {
    uint64_t started_ms = (uint64_t)(esp_timer_get_time() / 1000);
    while (true) {
        uint64_t now_ms = (uint64_t)(esp_timer_get_time() / 1000);
        uint64_t elapsed_ms = now_ms >= started_ms ? now_ms - started_ms : 0u;
        fixture_splash_output_t output = fixture_splash_step(elapsed_ms);
        bool finished = false;
        if (bsp_display_lock(20u)) {
            render_splash(&output, elapsed_ms);
            note_display_frame(now_ms);
            if (output.complete) {
                lv_obj_delete(splash.root);
                splash.root = NULL;
                note_splash_complete();
                finished = true;
            }
            bsp_display_unlock();
        }
        if (finished) return;
        vTaskDelay(pdMS_TO_TICKS(SPLASH_FRAME_INTERVAL_MS));
    }
}

static void announce_transition(const fixture_ui_output_t *output) {
    if (output->scene == ui.previous_scene) return;
    switch (output->scene) {
        case FIXTURE_UI_LOADED: fixture_board_tone(660u, 45u); break;
        case FIXTURE_UI_ARMED: fixture_board_tone(880u, 70u); break;
        case FIXTURE_UI_RUNNING: fixture_board_tone(1100u, 50u); break;
        case FIXTURE_UI_COMPLETE:
            fixture_board_tone(880u, 55u);
            fixture_board_tone(1320u, 90u);
            break;
        case FIXTURE_UI_ERROR: fixture_board_tone(180u, 180u); break;
        default: break;
    }
    ui.previous_scene = output->scene;
}

static void announce_result(fixture_result_t result) {
    if (result == ui.previous_result) return;
    if (result == FIXTURE_RESULT_PASS) {
        fixture_board_tone(880u, 55u);
        fixture_board_tone(1320u, 95u);
    } else if (result == FIXTURE_RESULT_FAIL) {
        fixture_board_tone(180u, 190u);
    } else if (result == FIXTURE_RESULT_INCONCLUSIVE) {
        fixture_board_tone(540u, 80u);
    }
    ui.previous_result = result;
}

static void render_button_feedback(uint64_t now_ms) {
    fixture_board_feedback_t feedback;
    fixture_board_feedback_snapshot(&feedback);
    if (feedback.sequence != ui.button_feedback_sequence) {
        ui.button_feedback_sequence = feedback.sequence;
        ui.button_feedback_event = feedback.event;
        ui.button_feedback_started_ms = now_ms;
    }

    uint64_t elapsed_ms = now_ms >= ui.button_feedback_started_ms
                              ? now_ms - ui.button_feedback_started_ms : 0u;
    fixture_button_feedback_output_t output =
        fixture_button_feedback_resolve(ui.button_feedback_event, feedback.boot_held,
                                        feedback.download_hint, elapsed_ms);
    if (!output.active) return;

    lv_color_t accent = lv_color_hex(output.accent_rgb);
    lv_label_set_text(ui.state, output.title);
    lv_label_set_text(ui.detail, output.detail);
    lv_label_set_text_static(ui.quality, "BUTTON INPUT");
    lv_obj_set_style_text_color(ui.state, accent, 0);
    lv_obj_set_style_text_color(ui.quality, accent, 0);
    lv_obj_set_style_arc_color(ui.orbit, accent, LV_PART_INDICATOR);
    lv_obj_set_style_arc_color(ui.progress, accent, LV_PART_INDICATOR);
    lv_obj_set_style_border_color(ui.core, accent, 0);
    lv_obj_set_style_bg_color(ui.halo_inner, accent, 0);
    lv_obj_set_style_bg_color(ui.halo_outer, accent, 0);
    lv_obj_set_style_bg_opa(ui.halo_inner,
                            (lv_opa_t)(24u + output.pulse_per_mille * 40u / 1000u), 0);
    lv_obj_set_style_bg_opa(ui.halo_outer,
                            (lv_opa_t)(12u + output.pulse_per_mille * 24u / 1000u), 0);
    lv_obj_set_style_transform_scale(ui.state,
                                     256 + (int)(output.pulse_per_mille * 10u / 1000u), 0);
}

static void render(const fixture_ui_output_t *output,
                   const fixture_presentation_t *presentation,
                   const char *automatic_detail, uint64_t now_ms) {
    fixture_visual_output_t visual;
    fixture_visual_resolve(output, presentation, &visual);
    lv_color_t accent = lv_color_hex(visual.accent_rgb);
    int energy = output->energy_per_mille;
    uint64_t elapsed_ms = ui.previous_render_ms && now_ms > ui.previous_render_ms
                              ? now_ms - ui.previous_render_ms : output->frame_interval_ms;
    if (elapsed_ms > 250u) elapsed_ms = 250u;
    float speed = (float)visual.angular_speed_milliradians / 1000.0f;
#if CONFIG_KEYPATH_FIXTURE_REDUCED_MOTION
    speed = 0.0f;
#endif
    ui.phase += speed * (float)elapsed_ms / 1000.0f;
    if (ui.phase > 6.2831853f) ui.phase -= 6.2831853f;
    ui.previous_render_ms = now_ms;

    float completion_wave = 0.0f;
#if !CONFIG_KEYPATH_FIXTURE_REDUCED_MOTION
    if (ui.completion_started_ms > 0u && now_ms >= ui.completion_started_ms) {
        uint64_t elapsed_ms = now_ms - ui.completion_started_ms;
        if (elapsed_ms < 700u) completion_wave = sinf((float)elapsed_ms / 700.0f * 3.1415927f);
    }
#endif

    lv_obj_set_style_bg_color(ui.screen, output->scene == FIXTURE_UI_ERROR
                                             ? lv_color_hex(0x190b13)
                                             : lv_color_hex(0x071117), 0);
    lv_obj_set_style_transform_scale(ui.state, 256, 0);
    lv_label_set_text(ui.state, visual.title);
    lv_obj_set_style_text_color(ui.state, accent, 0);
    lv_obj_set_style_arc_color(ui.orbit, accent, LV_PART_INDICATOR);
    lv_obj_set_style_arc_color(ui.progress, accent, LV_PART_INDICATOR);
    lv_obj_set_style_border_color(ui.core, accent, 0);
    lv_arc_set_value(ui.progress, visual.progress_per_mille);

    bool branded_update = visual.variant == FIXTURE_VISUAL_KEYPATH_UPDATE;
    lv_label_set_text_static(
        ui.eyebrow, branded_update ? "KEYPATH  /  SECURE UPDATE" : "KEYPATH  /  HID ORACLE");
    set_hidden(ui.core, branded_update);
    set_hidden(ui.icon_front, branded_update);
    set_hidden(ui.icon_back, branded_update);
    set_hidden(ui.brand_keycap, !branded_update);
    set_hidden(ui.brand_light, !branded_update);
    set_hidden(ui.brand_lid, !branded_update);
    set_hidden(ui.brand_glint_horizontal, !branded_update);
    set_hidden(ui.brand_glint_vertical, !branded_update);

    if (branded_update) {
        int fill_height = 2 + (int)(visual.progress_per_mille * 34u / 1000u);
        lv_obj_set_height(ui.brand_fill, fill_height);
        lv_obj_align(ui.brand_fill, LV_ALIGN_BOTTOM_MID, 0, 0);
        lv_obj_set_style_bg_color(ui.brand_fill, accent, 0);

        int key_light = (int)((sinf(ui.phase * 1.45f) + 1.0f) * 18.0f);
        int lid_lift = 2 + (int)((sinf(ui.phase * 1.45f) + 1.0f) * 2.0f);
#if CONFIG_KEYPATH_FIXTURE_REDUCED_MOTION
        key_light = 18;
        lid_lift = 3;
#endif
        lv_obj_set_style_bg_opa(ui.brand_light, (lv_opa_t)(205 + key_light), 0);
        lv_obj_set_style_shadow_opa(ui.brand_keycap, (lv_opa_t)(18 + key_light / 2), 0);
        lv_obj_set_style_translate_y(ui.brand_lid, -lid_lift, 0);

        float glint_angle = ui.phase;
#if CONFIG_KEYPATH_FIXTURE_REDUCED_MOTION
        glint_angle = (float)visual.progress_per_mille / 1000.0f * 6.2831853f;
#endif
        int glint_x = (int)(cosf(glint_angle) * 67.0f);
        int glint_y = (int)(sinf(glint_angle) * 67.0f) - 2;
        lv_obj_align(ui.brand_glint_horizontal, LV_ALIGN_CENTER, glint_x, glint_y);
        lv_obj_align(ui.brand_glint_vertical, LV_ALIGN_CENTER, glint_x, glint_y);
        lv_obj_set_style_bg_color(ui.brand_glint_horizontal, lv_color_hex(0xfff7df), 0);
        lv_obj_set_style_bg_color(ui.brand_glint_vertical, lv_color_hex(0xfff7df), 0);
        lv_obj_set_style_bg_opa(ui.brand_glint_horizontal, LV_OPA_80, 0);
        lv_obj_set_style_bg_opa(ui.brand_glint_vertical, LV_OPA_80, 0);
    }

    if ((int)visual.icon != ui.visual_stage) {
        fixture_visual_icon_t previous = ui.visual_stage < 0
                                             ? FIXTURE_ICON_POWER
                                             : (fixture_visual_icon_t)ui.visual_stage;
        lv_label_set_text(ui.icon_back, symbol_for(previous));
        lv_label_set_text(ui.icon_front, symbol_for(visual.icon));
        ui.visual_stage = (int)visual.icon;
        ui.icon_transition_started_ms = now_ms;
    }
    uint64_t transition_elapsed = now_ms - ui.icon_transition_started_ms;
    float transition = transition_elapsed >= 240u ? 1.0f : (float)transition_elapsed / 240.0f;
    float eased = 1.0f - powf(1.0f - transition, 3.0f);
    lv_obj_set_style_text_color(ui.icon_front, accent, 0);
    lv_obj_set_style_text_color(ui.icon_back, accent, 0);
    lv_obj_set_style_text_opa(ui.icon_front, (lv_opa_t)(255.0f * eased), 0);
    lv_obj_set_style_text_opa(ui.icon_back, (lv_opa_t)(255.0f * (1.0f - transition)), 0);
    int icon_pulse = (int)(sinf(ui.phase * 1.4f) * 7.0f);
    lv_obj_set_style_transform_scale(ui.icon_front, 232 + (int)(24.0f * eased) + icon_pulse, 0);
    lv_obj_set_style_translate_x(ui.icon_front, (int)(7.0f * (1.0f - eased)), 0);
    lv_obj_set_style_translate_x(ui.icon_back, (int)(-9.0f * transition), 0);

    int orbit_start = (int)(ui.phase * 57.29578f) % 360;
    int orbit_length = output->scene == FIXTURE_UI_RUNNING ? 55 + energy / 14 : 82;
    lv_arc_set_angles(ui.orbit, orbit_start, orbit_start + orbit_length);

    int pulse = (int)((sinf(ui.phase * 1.7f) + 1.0f) * 12.0f + completion_wave * 24.0f);
#if CONFIG_KEYPATH_FIXTURE_REDUCED_MOTION
    pulse = 0;
#endif
    int halo_size = 119 + pulse / 2 + energy / 90;
    lv_obj_set_style_transform_scale(ui.halo_inner, halo_size * 256 / 124, 0);
    lv_obj_set_style_bg_color(ui.halo_inner, accent, 0);
    lv_obj_set_style_bg_opa(ui.halo_inner, (lv_opa_t)(12 + energy / 28), 0);
    lv_obj_set_style_bg_color(ui.halo_outer, accent, 0);
    lv_obj_set_style_bg_opa(ui.halo_outer, (lv_opa_t)(6 + energy / 45), 0);

    for (size_t index = 0; index < KEY_COUNT; ++index) {
        float wave = sinf(ui.phase * 2.4f - (float)index * 0.7f);
        int opacity = 35 + (int)((wave + 1.0f) * 38.0f) + energy / 8;
        if (opacity > 255) opacity = 255;
        lv_obj_set_style_bg_color(ui.keys[index], accent, 0);
        lv_obj_set_style_bg_opa(ui.keys[index], (lv_opa_t)(opacity / 3), 0);
    }

    float radius = output->scene == FIXTURE_UI_COMPLETE ? 82.0f : 72.0f + energy / 80.0f;
    radius += completion_wave * 34.0f;
    for (size_t index = 0; index < PARTICLE_COUNT; ++index) {
        if (output->quality == FIXTURE_UI_PROTECTED && index >= 4u) {
            lv_obj_add_flag(ui.particles[index], LV_OBJ_FLAG_HIDDEN);
            continue;
        }
        lv_obj_clear_flag(ui.particles[index], LV_OBJ_FLAG_HIDDEN);
        float angle = ui.phase * (1.0f + (float)(index % 3u) * 0.13f) +
                      (float)index * 0.5235988f;
        float wobble = sinf(ui.phase * 1.9f + (float)index) * (3.0f + energy / 170.0f);
        int x = 120 + (int)(cosf(angle) * (radius + wobble));
        int y = 138 + (int)(sinf(angle) * (radius + wobble));
        lv_obj_set_pos(ui.particles[index], x, y);
        lv_obj_set_style_bg_color(ui.particles[index], accent, 0);
        lv_obj_set_style_bg_opa(ui.particles[index],
                                (lv_opa_t)(40 + ((index * 31u + (unsigned int)(ui.phase * 80)) % 150u)), 0);
    }

    if (presentation->detail[0]) {
        lv_label_set_text(ui.detail, presentation->detail);
    } else if (presentation->result != FIXTURE_RESULT_NONE &&
               (presentation->dropped || presentation->duplicated || presentation->repeated)) {
        char findings[64];
        snprintf(findings, sizeof(findings), "DROP %" PRIu32 "  DUP %" PRIu32 "  REPEAT %" PRIu32,
                 presentation->dropped, presentation->duplicated, presentation->repeated);
        lv_label_set_text(ui.detail, findings);
    } else if (presentation->phase == FIXTURE_PRESENT_NEXT && presentation->next[0]) {
        lv_label_set_text(ui.detail, presentation->next);
    } else {
        lv_label_set_text(ui.detail, automatic_detail);
    }

    if (presentation->result != FIXTURE_RESULT_NONE && presentation->reports_expected > 0u) {
        char metrics[64];
        snprintf(metrics, sizeof(metrics), "%" PRIu32 "/%" PRIu32 "  P95 %" PRIu32 "us%s",
                 presentation->reports_observed, presentation->reports_expected,
                 presentation->latency_p95_us, presentation->safe_release ? "  SAFE" : "");
        lv_label_set_text(ui.quality, metrics);
        lv_obj_set_style_text_color(ui.quality, accent, 0);
    } else

    if (branded_update) {
        lv_label_set_text_static(ui.quality, "SECURE OTA");
        lv_obj_set_style_text_color(ui.quality, accent, 0);
    } else if (output->quality == FIXTURE_UI_PROTECTED) {
        lv_label_set_text_static(ui.quality, "HID PRIORITY");
        lv_obj_set_style_text_color(ui.quality, lv_color_hex(0xffb454), 0);
    } else if (output->quality == FIXTURE_UI_ACTIVE) {
        lv_label_set_text_static(ui.quality, "LIVE 20 FPS");
        lv_obj_set_style_text_color(ui.quality, lv_color_hex(0x55c7ff), 0);
    } else {
        lv_label_set_text_static(ui.quality, "CINEMATIC");
        lv_obj_set_style_text_color(ui.quality, lv_color_hex(0x52727e), 0);
    }
    render_button_feedback(now_ms);
}

static void display_task(void *context) {
    (void)context;
    lv_display_t *display = bsp_display_start();
    configASSERT(display);
    ESP_ERROR_CHECK(bsp_display_brightness_set(CONFIG_KEYPATH_FIXTURE_BRIGHTNESS));
    configASSERT(bsp_display_lock(0u));
#if CONFIG_KEYPATH_FIXTURE_BOOT_SPLASH
    ui.screen = lv_screen_active();
    lv_obj_remove_style_all(ui.screen);
    lv_obj_set_style_bg_color(ui.screen, lv_color_hex(0x080c10), 0);
    lv_obj_set_style_bg_opa(ui.screen, LV_OPA_COVER, 0);
    build_splash();
#else
    build_ui();
#endif
    bsp_display_unlock();
#if CONFIG_KEYPATH_FIXTURE_BOOT_SPLASH
    note_display_initialized(true, false);
    play_splash();
    configASSERT(bsp_display_lock(100u));
    build_ui();
    bsp_display_unlock();
#else
    note_display_initialized(false, true);
#endif

    fixture_ui_model_t model;
    fixture_ui_model_init(&model);
    while (true) {
        fixture_runtime_snapshot_t snapshot;
        fixture_runtime_snapshot(&snapshot);
        uint64_t now_ms = (uint64_t)(esp_timer_get_time() / 1000);
        fixture_ui_output_t output = fixture_ui_model_step(&model, &snapshot.ui, now_ms);
        char automatic_detail[64];
        if (snapshot.ui.state == FIXTURE_ERROR && snapshot.error[0]) {
            snprintf(automatic_detail, sizeof(automatic_detail), "%.63s", snapshot.error);
        } else if (!snapshot.ui.wifi_connected) {
            snprintf(automatic_detail, sizeof(automatic_detail), "Trying %.32s", snapshot.network_name);
        } else {
            snprintf(automatic_detail, sizeof(automatic_detail), "%s  USB %s",
                     snapshot.network_address,
                     snapshot.ui.usb_mounted ? "READY" : "WAIT");
        }
        if (output.completion_burst) ui.completion_started_ms = now_ms;
        announce_transition(&output);
        announce_result(snapshot.presentation.result);
        fixture_board_update(snapshot.ui.state == FIXTURE_ARMED || snapshot.ui.state == FIXTURE_RUNNING);
        if (bsp_display_lock(20u)) {
            render(&output, &snapshot.presentation, automatic_detail, now_ms);
            note_display_frame(now_ms);
            bsp_display_unlock();
        }
        vTaskDelay(pdMS_TO_TICKS(output.frame_interval_ms));
    }
}

void fixture_display_start(void) {
    configASSERT(xTaskCreatePinnedToCore(display_task, "fixture_display", 8192, NULL, 6, NULL, 0) == pdPASS);
}

void fixture_display_health_snapshot(fixture_display_health_t *health) {
    if (!health) return;
    taskENTER_CRITICAL(&display_health_lock);
    *health = display_health;
    taskEXIT_CRITICAL(&display_health_lock);
}

bool fixture_display_is_healthy(void) {
    fixture_display_health_t health;
    fixture_display_health_snapshot(&health);
    uint64_t now_ms = (uint64_t)(esp_timer_get_time() / 1000);
    uint64_t age_ms = now_ms >= health.last_frame_ms ? now_ms - health.last_frame_ms : UINT64_MAX;
    return health.initialized && health.splash_complete && health.frame_sequence > 0u &&
           age_ms <= DISPLAY_HEARTBEAT_MAX_AGE_MS;
}
