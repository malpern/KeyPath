#include "fixture_button_feedback.h"
#include "fixture_core.h"
#include "fixture_demo.h"
#include "fixture_presentation.h"
#include "fixture_splash_model.h"
#include "fixture_ui_model.h"
#include "fixture_visual_model.h"
#include "fixture_wifi_model.h"

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

static void test_loads_compiled_in_events_with_the_same_safety_checks(void) {
    fixture_t fixture;
    fixture_init(&fixture);
    char error[128];
    const fixture_event_t events[] = {
        {.at_us = 0u, .modifiers = 2u, .keys = {14u}},
        {.at_us = 2000u, .modifiers = 2u},
        {.at_us = 4000u},
    };
    assert(fixture_load_events(&fixture, "offline-demo", events, 3u, 1u, 12000u,
                               error, sizeof(error)));
    assert(fixture.state == FIXTURE_LOADED);
    assert(fixture.event_count == 3u);
    assert(fixture.events[0].keys[0] == 14u);
    assert(fixture.script_crc32 != 0u);

    fixture_event_t unsafe[] = {{.at_us = 0u, .keys = {4u}}};
    assert(!fixture_load_events(&fixture, "unsafe", unsafe, 1u, 1u, 12000u,
                                error, sizeof(error)));
    assert(strstr(error, "all-keys-released"));
    assert(fixture.state == FIXTURE_IDLE);
}

static void test_offline_demo_is_precompiled_with_safe_shift_timing(void) {
    fixture_t fixture;
    fixture_init(&fixture);
    char error[128];
    assert(fixture_demo_load(&fixture, error, sizeof(error)));
    assert(strcmp(fixture.run_id, FIXTURE_DEMO_RUN_ID) == 0);
    assert(fixture.repeat_count == 1u);
    assert(fixture.event_count > strlen(FIXTURE_DEMO_TEXT) * 2u);
    assert(fixture.events[0].modifiers == 2u);
    assert(fixture.events[0].keys[0] == 0u);
    assert(fixture.events[1].at_us == 5000u);
    assert(fixture.events[1].keys[0] == 14u); /* K */
    const fixture_event_t *release = &fixture.events[fixture.event_count - 1u];
    assert(release->modifiers == 0u);
    assert(release->keys[0] == 0u);
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

static void test_control_plane_disconnect_aborts_only_active_runs(void) {
    fixture_t fixture;
    fixture_init(&fixture);
    assert(!fixture_abort_if_active(&fixture, "Wi-Fi disconnected"));
    assert(fixture.state == FIXTURE_IDLE);

    const char *events = "0 0 4 0 0 0 0 0\n50000 0 0 0 0 0 0 0\n";
    char script[512], error[128];
    make_script(script, sizeof(script), "network", 1u, events, 2u, 100000u);
    assert(fixture_load_script(&fixture, script, strlen(script), error, sizeof(error)));
    assert(!fixture_abort_if_active(&fixture, "Wi-Fi disconnected"));
    assert(fixture_arm(&fixture, "network", error, sizeof(error)));
    assert(fixture_abort_if_active(&fixture, "Wi-Fi disconnected"));
    assert(fixture.state == FIXTURE_ABORTED);
    assert(fixture.pending_release);
    assert(strstr(fixture.error, "Wi-Fi"));
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

static void test_next_action_deadline_supports_cooperative_waiting(void) {
    fixture_t fixture;
    reports_t reports = {0};
    fixture_init(&fixture);
    assert(fixture_time_until_next_action_us(&fixture, 0u) == 0u);
    drain_initial_release(&fixture, &reports);
    assert(fixture_time_until_next_action_us(&fixture, 0u) == UINT32_MAX);

    const char *events = "0 0 4 0 0 0 0 0\n50000 0 0 0 0 0 0 0\n";
    char script[512], error[128];
    make_script(script, sizeof(script), "cooperative", 1u, events, 2u, 100000u);
    assert(fixture_load_script(&fixture, script, strlen(script), error, sizeof(error)));
    assert(fixture_arm(&fixture, "cooperative", error, sizeof(error)));
    assert(fixture_time_until_next_action_us(&fixture, 0u) == 0u);
    fixture_poll(&fixture, 1u, true, true, capture_report, &reports);

    assert(fixture_start(&fixture, "cooperative", 100u, 1000000u, error, sizeof(error)));
    assert(fixture_time_until_next_action_us(&fixture, 1000000u) == 100000u);
    assert(fixture_time_until_next_action_us(&fixture, 1099000u) == 1000u);
    assert(fixture_time_until_next_action_us(&fixture, 1100000u) == 0u);
    fixture_poll(&fixture, 1100000u, true, true, capture_report, &reports);
    assert(fixture_time_until_next_action_us(&fixture, 1100000u) == 50000u);
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

static void test_visual_model_resolves_automatic_and_campaign_states(void) {
    fixture_ui_output_t ui = {
        .scene = FIXTURE_UI_IDLE,
        .quality = FIXTURE_UI_SHOWCASE,
        .progress_per_mille = 125u,
    };
    fixture_presentation_t presentation;
    fixture_presentation_init(&presentation);
    fixture_visual_output_t visual;
    fixture_visual_resolve(&ui, &presentation, &visual);
    assert(visual.icon == FIXTURE_ICON_KEYBOARD);
    assert(visual.accent_rgb == 0x56ddb3u);
    assert(visual.progress_per_mille == 125u);
    assert(visual.angular_speed_milliradians == 1550u);
    assert(strcmp(visual.title, "READY") == 0);

    presentation.phase = FIXTURE_PRESENT_TESTING;
    presentation.progress_per_mille = 640u;
    snprintf(presentation.title, sizeof(presentation.title), "Swift stress");
    fixture_visual_resolve(&ui, &presentation, &visual);
    assert(visual.icon == FIXTURE_ICON_KEYBOARD);
    assert(visual.accent_rgb == 0x55c7ffu);
    assert(visual.progress_per_mille == 640u);
    assert(visual.angular_speed_milliradians == 4800u);
    assert(strcmp(visual.title, "Swift stress") == 0);

    fixture_presentation_init(&presentation);
    presentation.phase = FIXTURE_PRESENT_PREPARING;
    presentation.branded_firmware_update = true;
    presentation.progress_per_mille = 420u;
    snprintf(presentation.title, sizeof(presentation.title), "FIRMWARE UPDATE");
    fixture_visual_resolve(&ui, &presentation, &visual);
    assert(visual.variant == FIXTURE_VISUAL_KEYPATH_UPDATE);
    assert(visual.icon == FIXTURE_ICON_DOWNLOAD);
    assert(visual.accent_rgb == 0xf3a128u);
    assert(visual.progress_per_mille == 420u);
    assert(visual.angular_speed_milliradians == 2500u);
    assert(strcmp(visual.title, "FIRMWARE UPDATE") == 0);

    presentation.result = FIXTURE_RESULT_FAIL;
    fixture_visual_resolve(&ui, &presentation, &visual);
    assert(visual.icon == FIXTURE_ICON_CLOSE);
    assert(visual.accent_rgb == 0xff5c72u);
    assert(strcmp(visual.title, "TEST FAILED") == 0);

    ui.quality = FIXTURE_UI_PROTECTED;
    fixture_visual_resolve(&ui, &presentation, &visual);
    assert(visual.angular_speed_milliradians == 480u);
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

static void test_wifi_profiles_retry_in_priority_order_and_wrap(void) {
    fixture_wifi_model_t model;
    fixture_wifi_model_init(&model);
    assert(model.profile_index == 0u); /* 529beach */

    assert(!fixture_wifi_model_note_disconnect(&model, 3u, 2u));
    assert(model.profile_index == 0u);
    assert(fixture_wifi_model_note_disconnect(&model, 3u, 2u));
    assert(model.profile_index == 1u); /* Alpern-Home */

    assert(!fixture_wifi_model_note_disconnect(&model, 3u, 2u));
    fixture_wifi_model_note_connected(&model);
    assert(model.failed_attempts == 0u);
    assert(!fixture_wifi_model_note_disconnect(&model, 3u, 2u));
    assert(fixture_wifi_model_note_disconnect(&model, 3u, 2u));
    assert(model.profile_index == 2u); /* iPhone */

    assert(!fixture_wifi_model_note_disconnect(&model, 3u, 2u));
    assert(fixture_wifi_model_note_disconnect(&model, 3u, 2u));
    assert(model.profile_index == 0u); /* wrap back to 529beach */
}

static void test_splash_reveals_holds_and_fades_without_blocking_boot(void) {
    fixture_splash_output_t splash = fixture_splash_step(0u);
    assert(splash.foreground_opacity == 0u);
    assert(splash.background_opacity == 255u);
    assert(splash.wordmark_opacity == 0u);
    assert(splash.logo_scale == 228u);
    assert(!splash.complete);

    splash = fixture_splash_step(FIXTURE_SPLASH_FADE_IN_MS);
    assert(splash.foreground_opacity == 255u);
    assert(splash.logo_scale == 256u);

    splash = fixture_splash_step(500u);
    assert(splash.foreground_opacity == 255u);
    assert(splash.wordmark_opacity == 255u);

    splash = fixture_splash_step(FIXTURE_SPLASH_HOLD_END_MS);
    assert(splash.foreground_opacity == 255u);
    assert(splash.background_opacity == 255u);

    splash = fixture_splash_step(1450u);
    assert(splash.foreground_opacity < 128u);
    assert(splash.background_opacity == splash.foreground_opacity);
    assert(splash.logo_scale > 256u);
    assert(!splash.complete);

    splash = fixture_splash_step(FIXTURE_SPLASH_TOTAL_MS);
    assert(splash.foreground_opacity == 0u);
    assert(splash.background_opacity == 0u);
    assert(splash.complete);
}

static void test_button_feedback_identifies_physical_positions_and_expires(void) {
    fixture_button_feedback_output_t feedback =
        fixture_button_feedback_resolve(FIXTURE_BUTTON_POWER, false, false, 0u);
    assert(feedback.active);
    assert(strcmp(feedback.title, "POWER BUTTON") == 0);
    assert(strcmp(feedback.detail, "TOP button detected") == 0);
    assert(feedback.accent_rgb == 0xffb454u);

    feedback = fixture_button_feedback_resolve(FIXTURE_BUTTON_BOOT, true, true, 180u);
    assert(feedback.active);
    assert(strcmp(feedback.title, "BOOT HELD") == 0);
    assert(strstr(feedback.detail, "TAP BOTTOM RESET"));
    assert(feedback.pulse_per_mille == 1000u);

    feedback = fixture_button_feedback_resolve(
        FIXTURE_BUTTON_BOOT, true, true, FIXTURE_BUTTON_FEEDBACK_DURATION_MS * 4u);
    assert(feedback.active);
    assert(strcmp(feedback.title, "BOOT HELD") == 0);

    feedback = fixture_button_feedback_resolve(FIXTURE_BUTTON_BOOT, false, true, 200u);
    assert(feedback.active);
    assert(strcmp(feedback.title, "BOOT RELEASED") == 0);
    assert(strstr(feedback.detail, "while tapping RESET"));

    feedback = fixture_button_feedback_resolve(FIXTURE_BUTTON_BOOT, true, false, 200u);
    assert(feedback.active);
    assert(strcmp(feedback.detail, "Test abort requested") == 0);

    feedback = fixture_button_feedback_resolve(FIXTURE_BUTTON_RESET, false, false, 600u);
    assert(feedback.active);
    assert(strcmp(feedback.title, "RESET / START") == 0);
    assert(strstr(feedback.detail, "BOTTOM RST"));

    feedback = fixture_button_feedback_resolve(
        FIXTURE_BUTTON_BOOT, false, true, FIXTURE_BUTTON_FEEDBACK_DURATION_MS);
    assert(!feedback.active);
    feedback = fixture_button_feedback_resolve(FIXTURE_BUTTON_NONE, false, false, 0u);
    assert(!feedback.active);
}

int main(void) {
    test_load_arm_run_and_repeat();
    test_rejects_corrupt_and_unsafe_scripts();
    test_loads_compiled_in_events_with_the_same_safety_checks();
    test_offline_demo_is_precompiled_with_safe_shift_timing();
    test_failed_replacement_invalidates_previous_script();
    test_abort_and_unmount_force_release();
    test_control_plane_disconnect_aborts_only_active_runs();
    test_lateness_metrics();
    test_next_action_deadline_supports_cooperative_waiting();
    test_ui_model_prioritizes_hid_and_tracks_progress();
    test_ui_model_connection_error_and_counter_reset();
    test_presentation_contract();
    test_visual_model_resolves_automatic_and_campaign_states();
    test_wifi_profiles_retry_in_priority_order_and_wrap();
    test_splash_reveals_holds_and_fades_without_blocking_boot();
    test_button_feedback_identifies_physical_positions_and_expires();
    puts("physical HID fixture core tests passed");
    return 0;
}
