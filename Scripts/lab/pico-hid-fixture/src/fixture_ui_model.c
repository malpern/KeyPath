#include "fixture_ui_model.h"

#include <string.h>

static fixture_ui_scene_t scene_for(const fixture_ui_input_t *input) {
    if (!input->wifi_connected && input->state != FIXTURE_ERROR) return FIXTURE_UI_CONNECTING;
    switch (input->state) {
        case FIXTURE_BOOTING: return FIXTURE_UI_BOOT;
        case FIXTURE_IDLE: return FIXTURE_UI_IDLE;
        case FIXTURE_LOADED: return FIXTURE_UI_LOADED;
        case FIXTURE_ARMED: return FIXTURE_UI_ARMED;
        case FIXTURE_RUNNING: return FIXTURE_UI_RUNNING;
        case FIXTURE_COMPLETE: return FIXTURE_UI_COMPLETE;
        case FIXTURE_ABORTED: return FIXTURE_UI_ABORTED;
        case FIXTURE_ERROR: return FIXTURE_UI_ERROR;
    }
    return FIXTURE_UI_ERROR;
}

void fixture_ui_model_init(fixture_ui_model_t *model) {
    memset(model, 0, sizeof(*model));
    model->previous_state = FIXTURE_BOOTING;
}

fixture_ui_output_t fixture_ui_model_step(fixture_ui_model_t *model,
                                          const fixture_ui_input_t *input,
                                          uint64_t now_ms) {
    fixture_ui_output_t output = {0};
    output.scene = scene_for(input);

    uint64_t elapsed = model->initialized && now_ms > model->previous_update_ms
                           ? now_ms - model->previous_update_ms
                           : 0u;
    uint64_t report_delta = model->initialized && input->reports_submitted >= model->previous_reports
                                ? input->reports_submitted - model->previous_reports
                                : 0u;
    uint64_t late_delta = model->initialized && input->late_reports >= model->previous_late_reports
                              ? input->late_reports - model->previous_late_reports
                              : 0u;

    uint32_t decay = elapsed > 1000u ? 1000u : (uint32_t)elapsed;
    uint32_t energy = model->energy_per_mille > decay ? model->energy_per_mille - decay : 0u;
    uint64_t impulse = report_delta * 95u;
    if (impulse > 1000u) impulse = 1000u;
    energy += (uint32_t)impulse;
    if (energy > 1000u) energy = 1000u;
    model->energy_per_mille = (uint16_t)energy;

    bool new_lateness_peak = input->maximum_lateness_us > 1500 &&
                             input->maximum_lateness_us > model->previous_maximum_lateness_us;
    bool new_pressure = input->state == FIXTURE_RUNNING && (late_delta > 0u || new_lateness_peak);
    if (new_pressure) model->protected_until_ms = now_ms + 1500u;
    output.pressure_warning = new_pressure || now_ms < model->protected_until_ms;

    if (output.pressure_warning) {
        output.quality = FIXTURE_UI_PROTECTED;
        output.frame_interval_ms = 125u;
    } else if (input->state == FIXTURE_RUNNING) {
        output.quality = FIXTURE_UI_ACTIVE;
        output.frame_interval_ms = 50u;
    } else {
        output.quality = FIXTURE_UI_SHOWCASE;
        output.frame_interval_ms = 33u;
    }

    uint64_t total = (uint64_t)input->event_count * input->repeat_count;
    if (total > 0u) {
        uint64_t progress = input->reports_submitted * 1000u / total;
        output.progress_per_mille = (uint16_t)(progress > 1000u ? 1000u : progress);
    }
    output.energy_per_mille = model->energy_per_mille;
    output.completion_burst = model->initialized && model->previous_state != FIXTURE_COMPLETE &&
                              input->state == FIXTURE_COMPLETE;

    model->previous_reports = input->reports_submitted;
    model->previous_late_reports = input->late_reports;
    model->previous_maximum_lateness_us = input->maximum_lateness_us;
    model->previous_update_ms = now_ms;
    model->previous_state = input->state;
    model->initialized = true;
    return output;
}
