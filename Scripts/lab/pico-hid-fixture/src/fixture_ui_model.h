#ifndef KEYPATH_FIXTURE_UI_MODEL_H
#define KEYPATH_FIXTURE_UI_MODEL_H

#include <stdbool.h>
#include <stdint.h>

#include "fixture_core.h"

typedef enum {
    FIXTURE_UI_BOOT = 0,
    FIXTURE_UI_CONNECTING,
    FIXTURE_UI_IDLE,
    FIXTURE_UI_LOADED,
    FIXTURE_UI_ARMED,
    FIXTURE_UI_RUNNING,
    FIXTURE_UI_COMPLETE,
    FIXTURE_UI_ABORTED,
    FIXTURE_UI_ERROR,
} fixture_ui_scene_t;

typedef enum {
    FIXTURE_UI_SHOWCASE = 0,
    FIXTURE_UI_ACTIVE,
    FIXTURE_UI_PROTECTED,
} fixture_ui_quality_t;

typedef struct {
    fixture_state_t state;
    bool wifi_connected;
    bool usb_mounted;
    uint32_t event_count;
    uint32_t repeat_count;
    uint32_t current_repeat;
    uint64_t reports_submitted;
    uint64_t late_reports;
    int64_t maximum_lateness_us;
} fixture_ui_input_t;

typedef struct {
    fixture_ui_scene_t scene;
    fixture_ui_quality_t quality;
    uint16_t progress_per_mille;
    uint16_t energy_per_mille;
    uint16_t frame_interval_ms;
    bool completion_burst;
    bool pressure_warning;
} fixture_ui_output_t;

typedef struct {
    uint64_t previous_reports;
    uint64_t previous_late_reports;
    int64_t previous_maximum_lateness_us;
    uint64_t previous_update_ms;
    uint64_t protected_until_ms;
    fixture_state_t previous_state;
    uint16_t energy_per_mille;
    bool initialized;
} fixture_ui_model_t;

void fixture_ui_model_init(fixture_ui_model_t *model);
fixture_ui_output_t fixture_ui_model_step(fixture_ui_model_t *model,
                                          const fixture_ui_input_t *input,
                                          uint64_t now_ms);

#endif
