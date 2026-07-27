#include "fixture_display.h"

#include <inttypes.h>
#include <math.h>
#include <stdio.h>

#include "bsp/esp32_s3_touch_lcd_1_69.h"
#include "esp_timer.h"
#include "fixture_board.h"
#include "fixture_runtime.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "lvgl.h"
#include "sdkconfig.h"

#define PARTICLE_COUNT 12u
#define KEY_COUNT 6u

typedef struct {
    lv_obj_t *screen;
    lv_obj_t *halo_outer;
    lv_obj_t *halo_inner;
    lv_obj_t *orbit;
    lv_obj_t *progress;
    lv_obj_t *core;
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
} display_ui_t;

static display_ui_t ui;

static const char *scene_name(fixture_ui_scene_t scene) {
    switch (scene) {
        case FIXTURE_UI_BOOT: return "WAKING UP";
        case FIXTURE_UI_CONNECTING: return "JOINING LAB";
        case FIXTURE_UI_IDLE: return "READY";
        case FIXTURE_UI_LOADED: return "SCRIPT LOADED";
        case FIXTURE_UI_ARMED: return "ARMED";
        case FIXTURE_UI_RUNNING: return "TYPING";
        case FIXTURE_UI_COMPLETE: return "RUN COMPLETE";
        case FIXTURE_UI_ABORTED: return "RUN STOPPED";
        case FIXTURE_UI_ERROR: return "ATTENTION";
    }
    return "UNKNOWN";
}

static lv_color_t accent_for(fixture_ui_scene_t scene) {
    switch (scene) {
        case FIXTURE_UI_RUNNING: return lv_color_hex(0x55c7ff);
        case FIXTURE_UI_COMPLETE: return lv_color_hex(0x44d7a8);
        case FIXTURE_UI_ARMED: return lv_color_hex(0xffb454);
        case FIXTURE_UI_ABORTED: return lv_color_hex(0x9c7cff);
        case FIXTURE_UI_ERROR: return lv_color_hex(0xff5c72);
        default: return lv_color_hex(0x56ddb3);
    }
}

static lv_color_t presentation_accent(const fixture_presentation_t *presentation,
                                      fixture_ui_scene_t scene) {
    if (presentation->result == FIXTURE_RESULT_PASS) return lv_color_hex(0x44d7a8);
    if (presentation->result == FIXTURE_RESULT_FAIL) return lv_color_hex(0xff5c72);
    if (presentation->result == FIXTURE_RESULT_INCONCLUSIVE) return lv_color_hex(0xffb454);
    switch (presentation->phase) {
        case FIXTURE_PRESENT_PREPARING: return lv_color_hex(0x9c7cff);
        case FIXTURE_PRESENT_COUNTDOWN: return lv_color_hex(0xffb454);
        case FIXTURE_PRESENT_TESTING: return lv_color_hex(0x55c7ff);
        case FIXTURE_PRESENT_OBSERVING: return lv_color_hex(0xb58cff);
        case FIXTURE_PRESENT_RESOLVING: return lv_color_hex(0x36d8d0);
        case FIXTURE_PRESENT_NEXT: return lv_color_hex(0x55c7ff);
        default: return accent_for(scene);
    }
}

static int visual_stage(const fixture_presentation_t *presentation, fixture_ui_scene_t scene) {
    if (presentation->result != FIXTURE_RESULT_NONE) return 32 + (int)presentation->result;
    if (presentation->phase != FIXTURE_PRESENT_AUTO) return 16 + (int)presentation->phase;
    return (int)scene;
}

static const char *symbol_for(int stage) {
    if (stage == 33) return LV_SYMBOL_OK;
    if (stage == 34) return LV_SYMBOL_CLOSE;
    if (stage == 35) return LV_SYMBOL_WARNING;
    switch (stage) {
        case FIXTURE_UI_BOOT: return LV_SYMBOL_POWER;
        case FIXTURE_UI_CONNECTING: return LV_SYMBOL_WIFI;
        case FIXTURE_UI_IDLE: return LV_SYMBOL_KEYBOARD;
        case FIXTURE_UI_LOADED: return LV_SYMBOL_DOWNLOAD;
        case FIXTURE_UI_ARMED: return LV_SYMBOL_WARNING;
        case FIXTURE_UI_RUNNING: return LV_SYMBOL_PLAY;
        case FIXTURE_UI_COMPLETE: return LV_SYMBOL_OK;
        case FIXTURE_UI_ABORTED: return LV_SYMBOL_STOP;
        case FIXTURE_UI_ERROR: return LV_SYMBOL_CLOSE;
        case 17: return LV_SYMBOL_REFRESH;
        case 18: return LV_SYMBOL_BELL;
        case 19: return LV_SYMBOL_KEYBOARD;
        case 20: return LV_SYMBOL_EYE_OPEN;
        case 21: return LV_SYMBOL_SETTINGS;
        case 22: return LV_SYMBOL_OK;
        case 23: return LV_SYMBOL_NEXT;
        default: return LV_SYMBOL_POWER;
    }
}

static const char *presentation_title(const fixture_presentation_t *presentation,
                                      fixture_ui_scene_t scene) {
    if (presentation->result == FIXTURE_RESULT_PASS) return "TEST PASSED";
    if (presentation->result == FIXTURE_RESULT_FAIL) return "TEST FAILED";
    if (presentation->result == FIXTURE_RESULT_INCONCLUSIVE) return "NEEDS REVIEW";
    if (presentation->title[0]) return presentation->title;
    switch (presentation->phase) {
        case FIXTURE_PRESENT_PREPARING: return "PREPARING";
        case FIXTURE_PRESENT_COUNTDOWN: return "STAND BY";
        case FIXTURE_PRESENT_TESTING: return "SENDING KEYS";
        case FIXTURE_PRESENT_OBSERVING: return "OBSERVING";
        case FIXTURE_PRESENT_RESOLVING: return "RESOLVING";
        case FIXTURE_PRESENT_RESULT: return "RESULT";
        case FIXTURE_PRESENT_NEXT: return "UP NEXT";
        default: return scene_name(scene);
    }
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

static void touch_event(lv_event_t *event) {
    if (lv_event_get_code(event) != LV_EVENT_PRESSED) return;
    fixture_runtime_snapshot_t snapshot;
    fixture_runtime_snapshot(&snapshot);
    if (snapshot.ui.state == FIXTURE_ARMED || snapshot.ui.state == FIXTURE_RUNNING) {
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

    for (size_t index = 0; index < PARTICLE_COUNT; ++index) {
        ui.particles[index] = make_circle(ui.screen, index % 3u == 0u ? 6 : 4,
                                          lv_color_hex(0x56ddb3), LV_OPA_50);
    }

    ui.state = lv_label_create(ui.screen);
    lv_label_set_text_static(ui.state, "WAKING UP");
    lv_obj_set_style_text_font(ui.state, &lv_font_montserrat_20, 0);
    lv_obj_set_style_text_color(ui.state, lv_color_hex(0xe9f7f4), 0);
    lv_obj_set_width(ui.state, 220);
    lv_label_set_long_mode(ui.state, LV_LABEL_LONG_DOT);
    lv_obj_set_style_text_align(ui.state, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_align(ui.state, LV_ALIGN_BOTTOM_MID, 0, -40);

    ui.detail = lv_label_create(ui.screen);
    lv_label_set_text_static(ui.detail, "USB + Wi-Fi control");
    lv_obj_set_style_text_color(ui.detail, lv_color_hex(0x78909a), 0);
    lv_obj_set_width(ui.detail, 220);
    lv_label_set_long_mode(ui.detail, LV_LABEL_LONG_DOT);
    lv_obj_set_style_text_align(ui.detail, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_align(ui.detail, LV_ALIGN_BOTTOM_MID, 0, -20);

    ui.quality = lv_label_create(ui.screen);
    lv_label_set_text_static(ui.quality, "CINEMATIC");
    lv_obj_set_style_text_color(ui.quality, lv_color_hex(0x52727e), 0);
    lv_obj_set_style_text_letter_space(ui.quality, 1, 0);
    lv_obj_align(ui.quality, LV_ALIGN_TOP_RIGHT, -10, 38);
    ui.previous_scene = FIXTURE_UI_BOOT;
    ui.visual_stage = -1;
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

static void render(const fixture_ui_output_t *output,
                   const fixture_presentation_t *presentation, uint64_t now_ms) {
    lv_color_t accent = presentation_accent(presentation, output->scene);
    int energy = output->energy_per_mille;
    uint64_t elapsed_ms = ui.previous_render_ms && now_ms > ui.previous_render_ms
                              ? now_ms - ui.previous_render_ms : output->frame_interval_ms;
    if (elapsed_ms > 250u) elapsed_ms = 250u;
    float speed = output->scene == FIXTURE_UI_RUNNING ? 4.2f : 1.55f;
    if (presentation->phase == FIXTURE_PRESENT_COUNTDOWN) speed = 2.6f;
    if (presentation->phase == FIXTURE_PRESENT_TESTING) speed = 4.8f;
    if (presentation->phase == FIXTURE_PRESENT_OBSERVING) speed = 1.1f;
    if (output->quality == FIXTURE_UI_PROTECTED) speed = 0.48f;
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
    lv_label_set_text(ui.state, presentation_title(presentation, output->scene));
    lv_obj_set_style_text_color(ui.state, accent, 0);
    lv_obj_set_style_arc_color(ui.orbit, accent, LV_PART_INDICATOR);
    lv_obj_set_style_arc_color(ui.progress, accent, LV_PART_INDICATOR);
    lv_obj_set_style_border_color(ui.core, accent, 0);
    uint16_t progress = presentation->phase == FIXTURE_PRESENT_AUTO
                            ? output->progress_per_mille : presentation->progress_per_mille;
    lv_arc_set_value(ui.progress, progress);

    int stage = visual_stage(presentation, output->scene);
    if (stage != ui.visual_stage) {
        lv_label_set_text(ui.icon_back, symbol_for(ui.visual_stage));
        lv_label_set_text(ui.icon_front, symbol_for(stage));
        ui.visual_stage = stage;
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
        lv_label_set_text_static(ui.detail, "USB + Wi-Fi control");
    }

    if (presentation->result != FIXTURE_RESULT_NONE && presentation->reports_expected > 0u) {
        char metrics[64];
        snprintf(metrics, sizeof(metrics), "%" PRIu32 "/%" PRIu32 "  P95 %" PRIu32 "us%s",
                 presentation->reports_observed, presentation->reports_expected,
                 presentation->latency_p95_us, presentation->safe_release ? "  SAFE" : "");
        lv_label_set_text(ui.quality, metrics);
        lv_obj_set_style_text_color(ui.quality, accent, 0);
    } else

    if (output->quality == FIXTURE_UI_PROTECTED) {
        lv_label_set_text_static(ui.quality, "HID PRIORITY");
        lv_obj_set_style_text_color(ui.quality, lv_color_hex(0xffb454), 0);
    } else if (output->quality == FIXTURE_UI_ACTIVE) {
        lv_label_set_text_static(ui.quality, "LIVE 20 FPS");
        lv_obj_set_style_text_color(ui.quality, lv_color_hex(0x55c7ff), 0);
    } else {
        lv_label_set_text_static(ui.quality, "CINEMATIC");
        lv_obj_set_style_text_color(ui.quality, lv_color_hex(0x52727e), 0);
    }
}

static void display_task(void *context) {
    (void)context;
    lv_display_t *display = bsp_display_start();
    configASSERT(display);
    ESP_ERROR_CHECK(bsp_display_brightness_set(CONFIG_KEYPATH_FIXTURE_BRIGHTNESS));
    configASSERT(bsp_display_lock(0u));
    build_ui();
    bsp_display_unlock();

    fixture_ui_model_t model;
    fixture_ui_model_init(&model);
    while (true) {
        fixture_runtime_snapshot_t snapshot;
        fixture_runtime_snapshot(&snapshot);
        uint64_t now_ms = (uint64_t)(esp_timer_get_time() / 1000);
        fixture_ui_output_t output = fixture_ui_model_step(&model, &snapshot.ui, now_ms);
        if (output.completion_burst) ui.completion_started_ms = now_ms;
        announce_transition(&output);
        announce_result(snapshot.presentation.result);
        fixture_board_update(snapshot.ui.state == FIXTURE_ARMED || snapshot.ui.state == FIXTURE_RUNNING);
        if (bsp_display_lock(20u)) {
            render(&output, &snapshot.presentation, now_ms);
            bsp_display_unlock();
        }
        vTaskDelay(pdMS_TO_TICKS(output.frame_interval_ms));
    }
}

void fixture_display_start(void) {
    configASSERT(xTaskCreatePinnedToCore(display_task, "fixture_display", 8192, NULL, 6, NULL, 0) == pdPASS);
}
