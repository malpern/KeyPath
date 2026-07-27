#include "fixture_core.h"
#include "fixture_presentation.h"
#include "fixture_ui_model.h"

#include <assert.h>
#include <stdio.h>
#include <string.h>

typedef struct {
    uint32_t count;
    uint8_t modifiers[32];
    uint8_t keys[32][6];
} reports_t;

static bool capture_report(uint8_t modifiers, const uint8_t keys[6], void *context) {
    reports_t *reports = context;
    assert(reports->count < 32u);
    reports->modifiers[reports->count] = modifiers;
    memcpy(reports->keys[reports->count], keys, 6u);
    reports->count++;
    return true;
}

static void make_script(char *output, size_t capacity, const char *run_id,
                        uint32_t repeats, const char *events, uint32_t event_count, uint32_t cycle_us) {
    uint32_t crc = fixture_crc32(events, strlen(events));
    snprintf(output, capacity, "KPHID1 %s %u %u %u %08x\n%s",
             run_id, event_count, repeats, cycle_us, crc, events);
}

static void drain_initial_release(fixture_t *fixture, reports_t *reports) {
    fixture_poll(fixture, 0u, true, true, capture_report, reports);
    assert(reports->count == 1u);
}

static void test_load_arm_run_and_repeat(void) {
    fixture_t fixture;
    reports_t reports = {0};
    fixture_init(&fixture);
    drain_initial_release(&fixture, &reports);

    const char *events = "0 0 4 0 0 0 0 0\n50000 0 0 0 0 0 0 0\n";
    char script[512], error[128];
    make_script(script, sizeof(script), "run-42", 2u, events, 2u, 100000u);
    assert(fixture_load_script(&fixture, script, strlen(script), error, sizeof(error)));
    assert(fixture.state == FIXTURE_LOADED);
    assert(fixture_arm(&fixture, "run-42", error, sizeof(error)));
    fixture_poll(&fixture, 10u, true, true, capture_report, &reports);
    assert(reports.count == 2u); /* pre-arm safety release */
    assert(fixture_start(&fixture, "run-42", 100u, 1000000u, error, sizeof(error)));

    fixture_poll(&fixture, 1099999u, true, true, capture_report, &reports);
    assert(reports.count == 2u);
    fixture_poll(&fixture, 1100000u, true, true, capture_report, &reports);
    fixture_poll(&fixture, 1150000u, true, true, capture_report, &reports);
    fixture_poll(&fixture, 1200000u, true, true, capture_report, &reports);
    fixture_poll(&fixture, 1250000u, true, true, capture_report, &reports);
    assert(fixture.state == FIXTURE_COMPLETE);
    assert(fixture.reports_submitted == 4u);
    assert(reports.count == 6u);
    assert(reports.keys[2][0] == 4u);
    assert(reports.keys[3][0] == 0u);
    assert(fixture_trace_count(&fixture) == 4u);
    assert(fixture_trace_at(&fixture, 0u)->sequence == 1u);
}

static void test_rejects_corrupt_and_unsafe_scripts(void) {
    fixture_t fixture;
    fixture_init(&fixture);
    char error[128];

    const char *events = "0 0 4 0 0 0 0 0\n50000 0 0 0 0 0 0 0\n";
    char script[512];
    make_script(script, sizeof(script), "safe", 1u, events, 2u, 100000u);
    script[strlen(script) - 2u] = '1';
    assert(!fixture_load_script(&fixture, script, strlen(script), error, sizeof(error)));
    assert(strstr(error, "CRC32"));

    const char *held = "0 0 4 0 0 0 0 0\n";
    make_script(script, sizeof(script), "unsafe", 1u, held, 1u, 100000u);
    assert(!fixture_load_script(&fixture, script, strlen(script), error, sizeof(error)));
    assert(strstr(error, "all-keys-released"));

    const char *duplicate = "0 0 4 4 0 0 0 0\n50000 0 0 0 0 0 0 0\n";
    make_script(script, sizeof(script), "duplicate", 1u, duplicate, 2u, 100000u);
    assert(!fixture_load_script(&fixture, script, strlen(script), error, sizeof(error)));
    assert(strstr(error, "duplicate"));
}

static void test_failed_replacement_invalidates_previous_script(void) {
    fixture_t fixture;
    fixture_init(&fixture);
    char script[512], error[128];

    const char *safe = "0 0 4 0 0 0 0 0\n50000 0 0 0 0 0 0 0\n";
    make_script(script, sizeof(script), "previous", 1u, safe, 2u, 100000u);
    assert(fixture_load_script(&fixture, script, strlen(script), error, sizeof(error)));

    const char *unsafe = "0 0 5 0 0 0 0 0\n";
    make_script(script, sizeof(script), "replacement", 1u, unsafe, 1u, 100000u);
    assert(!fixture_load_script(&fixture, script, strlen(script), error, sizeof(error)));
    assert(fixture.state == FIXTURE_IDLE);
    assert(fixture.event_count == 0u);
    assert(fixture.run_id[0] == '\0');
    assert(!fixture_arm(&fixture, "previous", error, sizeof(error)));
}

static void test_abort_and_unmount_force_release(void) {
    fixture_t fixture;
    reports_t reports = {0};
    fixture_init(&fixture);
    drain_initial_release(&fixture, &reports);
    const char *events = "0 0 4 0 0 0 0 0\n50000 0 0 0 0 0 0 0\n";
    char script[512], error[128];
    make_script(script, sizeof(script), "safety", 1u, events, 2u, 100000u);
    assert(fixture_load_script(&fixture, script, strlen(script), error, sizeof(error)));
    assert(fixture_arm(&fixture, "safety", error, sizeof(error)));
    fixture_poll(&fixture, 1u, true, true, capture_report, &reports);
    assert(fixture_start(&fixture, "safety", 100u, 1000u, error, sizeof(error)));
    fixture_poll(&fixture, 101000u, true, true, capture_report, &reports);
    fixture_poll(&fixture, 101001u, false, false, capture_report, &reports);
    assert(fixture.state == FIXTURE_ERROR);
    assert(fixture.pending_release);
    fixture_poll(&fixture, 101002u, true, true, capture_report, &reports);
    assert(!fixture.pending_release);
    assert(reports.keys[reports.count - 1u][0] == 0u);

    fixture_abort(&fixture, "operator abort");
    assert(fixture.state == FIXTURE_ABORTED);
    fixture_poll(&fixture, 101003u, true, true, capture_report, &reports);
    assert(reports.keys[reports.count - 1u][0] == 0u);
}

static void test_lateness_metrics(void) {
    fixture_t fixture;
    reports_t reports = {0};
    fixture_init(&fixture);
    drain_initial_release(&fixture, &reports);
    const char *events = "0 0 4 0 0 0 0 0\n50000 0 0 0 0 0 0 0\n";
    char script[512], error[128];
    make_script(script, sizeof(script), "late", 1u, events, 2u, 100000u);
    assert(fixture_load_script(&fixture, script, strlen(script), error, sizeof(error)));
    assert(fixture_arm(&fixture, "late", error, sizeof(error)));
    fixture_poll(&fixture, 1u, true, true, capture_report, &reports);
    assert(fixture_start(&fixture, "late", 100u, 0u, error, sizeof(error)));
    fixture_poll(&fixture, 103000u, true, true, capture_report, &reports);
    assert(fixture.late_reports == 1u);
    assert(fixture.maximum_lateness_us == 3000);
}

static void test_ui_model_prioritizes_hid_and_tracks_progress(void) {
    fixture_ui_model_t model;
    fixture_ui_model_init(&model);
    fixture_ui_input_t input = {
        .state = FIXTURE_RUNNING,
        .wifi_connected = true,
        .usb_mounted = true,
        .event_count = 10u,
        .repeat_count = 10u,
    };
    fixture_ui_output_t output = fixture_ui_model_step(&model, &input, 1000u);
    assert(output.scene == FIXTURE_UI_RUNNING);
    assert(output.quality == FIXTURE_UI_ACTIVE);
    assert(output.frame_interval_ms == 50u);

    input.reports_submitted = 25u;
    output = fixture_ui_model_step(&model, &input, 1010u);
    assert(output.progress_per_mille == 250u);
    assert(output.energy_per_mille > 900u);

    input.late_reports = 1u;
    input.maximum_lateness_us = 2000;
    output = fixture_ui_model_step(&model, &input, 1020u);
    assert(output.quality == FIXTURE_UI_PROTECTED);
    assert(output.frame_interval_ms == 125u);
    assert(output.pressure_warning);

    output = fixture_ui_model_step(&model, &input, 2400u);
    assert(output.quality == FIXTURE_UI_PROTECTED);
    output = fixture_ui_model_step(&model, &input, 2600u);
    assert(output.quality == FIXTURE_UI_ACTIVE);

    input.state = FIXTURE_COMPLETE;
    input.reports_submitted = 100u;
    output = fixture_ui_model_step(&model, &input, 2610u);
    assert(output.scene == FIXTURE_UI_COMPLETE);
    assert(output.progress_per_mille == 1000u);
    assert(output.completion_burst);
    output = fixture_ui_model_step(&model, &input, 2620u);
    assert(!output.completion_burst);
}

static void test_presentation_contract(void) {
    fixture_presentation_t presentation;
    fixture_presentation_init(&presentation);
    assert(presentation.phase == FIXTURE_PRESENT_AUTO);
    assert(fixture_presentation_parse_phase("observing", &presentation.phase));
    assert(presentation.phase == FIXTURE_PRESENT_OBSERVING);
    assert(fixture_presentation_parse_result("inconclusive", &presentation.result));
    assert(presentation.result == FIXTURE_RESULT_INCONCLUSIVE);
    assert(fixture_presentation_text_valid("Swift stress / pass 2", 32u));
    assert(!fixture_presentation_text_valid("unsafe \"label\"", 32u));
    assert(!fixture_presentation_parse_phase("dancing", &presentation.phase));
}

static void test_ui_model_connection_error_and_counter_reset(void) {
    fixture_ui_model_t model;
    fixture_ui_model_init(&model);
    fixture_ui_input_t input = {.state = FIXTURE_BOOTING};
    fixture_ui_output_t output = fixture_ui_model_step(&model, &input, 0u);
    assert(output.scene == FIXTURE_UI_CONNECTING);

    input.state = FIXTURE_ERROR;
    output = fixture_ui_model_step(&model, &input, 10u);
    assert(output.scene == FIXTURE_UI_ERROR);

    input.state = FIXTURE_RUNNING;
    input.wifi_connected = true;
    input.event_count = 2u;
    input.repeat_count = 2u;
    input.reports_submitted = 10u;
    output = fixture_ui_model_step(&model, &input, 20u);
    assert(output.progress_per_mille == 1000u);

    input.reports_submitted = 0u;
    output = fixture_ui_model_step(&model, &input, 30u);
    assert(output.progress_per_mille == 0u);
    assert(output.energy_per_mille <= 1000u);
}

int main(void) {
    test_load_arm_run_and_repeat();
    test_rejects_corrupt_and_unsafe_scripts();
    test_failed_replacement_invalidates_previous_script();
    test_abort_and_unmount_force_release();
    test_lateness_metrics();
    test_ui_model_prioritizes_hid_and_tracks_progress();
    test_ui_model_connection_error_and_counter_reset();
    test_presentation_contract();
    puts("physical HID fixture core tests passed");
    return 0;
}
