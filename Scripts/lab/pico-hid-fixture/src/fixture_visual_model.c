#include "fixture_visual_model.h"

#include <stdio.h>

static const char *scene_title(fixture_ui_scene_t scene) {
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

static fixture_visual_icon_t scene_icon(fixture_ui_scene_t scene) {
    switch (scene) {
        case FIXTURE_UI_BOOT: return FIXTURE_ICON_POWER;
        case FIXTURE_UI_CONNECTING: return FIXTURE_ICON_WIFI;
        case FIXTURE_UI_IDLE: return FIXTURE_ICON_KEYBOARD;
        case FIXTURE_UI_LOADED: return FIXTURE_ICON_DOWNLOAD;
        case FIXTURE_UI_ARMED: return FIXTURE_ICON_WARNING;
        case FIXTURE_UI_RUNNING: return FIXTURE_ICON_PLAY;
        case FIXTURE_UI_COMPLETE: return FIXTURE_ICON_OK;
        case FIXTURE_UI_ABORTED: return FIXTURE_ICON_STOP;
        case FIXTURE_UI_ERROR: return FIXTURE_ICON_CLOSE;
    }
    return FIXTURE_ICON_WARNING;
}

static uint32_t scene_accent(fixture_ui_scene_t scene) {
    switch (scene) {
        case FIXTURE_UI_RUNNING: return 0x55c7ffu;
        case FIXTURE_UI_COMPLETE: return 0x44d7a8u;
        case FIXTURE_UI_ARMED: return 0xffb454u;
        case FIXTURE_UI_ABORTED: return 0x9c7cffu;
        case FIXTURE_UI_ERROR: return 0xff5c72u;
        default: return 0x56ddb3u;
    }
}

static void apply_phase(const fixture_presentation_t *presentation,
                        fixture_visual_output_t *visual, const char **title) {
    switch (presentation->phase) {
        case FIXTURE_PRESENT_PREPARING:
            visual->icon = FIXTURE_ICON_REFRESH;
            visual->accent_rgb = 0x9c7cffu;
            *title = "PREPARING";
            break;
        case FIXTURE_PRESENT_COUNTDOWN:
            visual->icon = FIXTURE_ICON_BELL;
            visual->accent_rgb = 0xffb454u;
            visual->angular_speed_milliradians = 2600u;
            *title = "STAND BY";
            break;
        case FIXTURE_PRESENT_TESTING:
            visual->icon = FIXTURE_ICON_KEYBOARD;
            visual->accent_rgb = 0x55c7ffu;
            visual->angular_speed_milliradians = 4800u;
            *title = "SENDING KEYS";
            break;
        case FIXTURE_PRESENT_OBSERVING:
            visual->icon = FIXTURE_ICON_EYE;
            visual->accent_rgb = 0xb58cffu;
            visual->angular_speed_milliradians = 1100u;
            *title = "OBSERVING";
            break;
        case FIXTURE_PRESENT_RESOLVING:
            visual->icon = FIXTURE_ICON_SETTINGS;
            visual->accent_rgb = 0x36d8d0u;
            *title = "RESOLVING";
            break;
        case FIXTURE_PRESENT_RESULT:
            visual->icon = FIXTURE_ICON_OK;
            *title = "RESULT";
            break;
        case FIXTURE_PRESENT_NEXT:
            visual->icon = FIXTURE_ICON_NEXT;
            visual->accent_rgb = 0x55c7ffu;
            *title = "UP NEXT";
            break;
        case FIXTURE_PRESENT_AUTO:
            break;
    }
}

static void apply_result(fixture_result_t result, fixture_visual_output_t *visual,
                         const char **title) {
    switch (result) {
        case FIXTURE_RESULT_PASS:
            visual->icon = FIXTURE_ICON_OK;
            visual->accent_rgb = 0x44d7a8u;
            *title = "TEST PASSED";
            break;
        case FIXTURE_RESULT_FAIL:
            visual->icon = FIXTURE_ICON_CLOSE;
            visual->accent_rgb = 0xff5c72u;
            *title = "TEST FAILED";
            break;
        case FIXTURE_RESULT_INCONCLUSIVE:
            visual->icon = FIXTURE_ICON_WARNING;
            visual->accent_rgb = 0xffb454u;
            *title = "NEEDS REVIEW";
            break;
        case FIXTURE_RESULT_NONE:
            break;
    }
}

static void apply_bear_palette(fixture_result_t result,
                               fixture_visual_output_t *visual) {
    switch (result) {
        case FIXTURE_RESULT_PASS:
            visual->accent_rgb = 0x66c9a3u;
            break;
        case FIXTURE_RESULT_FAIL:
            visual->accent_rgb = 0x9b8afbu;
            break;
        case FIXTURE_RESULT_INCONCLUSIVE:
            visual->accent_rgb = 0xf2b84bu;
            break;
        case FIXTURE_RESULT_NONE:
            visual->accent_rgb = 0xe34c42u;
            break;
    }
}

void fixture_visual_resolve(const fixture_ui_output_t *ui,
                            const fixture_presentation_t *presentation,
                            fixture_visual_output_t *visual) {
    const char *title = scene_title(ui->scene);
    visual->icon = scene_icon(ui->scene);
    if (presentation->branded_firmware_update ||
        presentation->brand == FIXTURE_BRAND_KEYPATH) {
        visual->variant = FIXTURE_VISUAL_KEYPATH_UPDATE;
    } else if (presentation->brand == FIXTURE_BRAND_BEAR) {
        visual->variant = FIXTURE_VISUAL_BEAR_TEST;
    } else {
        visual->variant = FIXTURE_VISUAL_STANDARD;
    }
    visual->accent_rgb = scene_accent(ui->scene);
    visual->progress_per_mille = ui->progress_per_mille;
    visual->angular_speed_milliradians = ui->scene == FIXTURE_UI_RUNNING ? 4200u : 1550u;

    if (presentation->phase != FIXTURE_PRESENT_AUTO) {
        visual->progress_per_mille = presentation->progress_per_mille;
        apply_phase(presentation, visual, &title);
        if (presentation->title[0]) title = presentation->title;
    }
    if (presentation->branded_firmware_update && presentation->result == FIXTURE_RESULT_NONE) {
        visual->icon = FIXTURE_ICON_DOWNLOAD;
        visual->accent_rgb = 0xf3a128u;
        visual->angular_speed_milliradians = 2500u;
    }
    apply_result(presentation->result, visual, &title);
    if (presentation->brand == FIXTURE_BRAND_BEAR) {
        apply_bear_palette(presentation->result, visual);
    }
    if (ui->quality == FIXTURE_UI_PROTECTED) visual->angular_speed_milliradians = 480u;
    snprintf(visual->title, sizeof(visual->title), "%s", title);
}
