#include "fixture_qemu_smoke.h"

#include <stdbool.h>
#include <inttypes.h>
#include <stdio.h>
#include <string.h>

#include "esp_rom_sys.h"
#include "fixture_core.h"
#include "fixture_ui_model.h"

typedef struct {
    uint32_t count;
    uint8_t first_key;
    uint8_t final_key;
} smoke_reports_t;

static bool capture_report(uint8_t modifiers, const uint8_t keys[6], void *context) {
    (void)modifiers;
    smoke_reports_t *reports = context;
    if (reports->count == 0u) reports->first_key = keys[0];
    reports->final_key = keys[0];
    reports->count++;
    return true;
}

static bool run_core_smoke(void) {
    static const char events[] =
        "0 0 4 0 0 0 0 0\n"
        "50000 0 0 0 0 0 0 0\n";
    static char script[256];
    static char error[128];
    static fixture_t fixture;
    static smoke_reports_t reports;

    fixture_init(&fixture);
    fixture_poll(&fixture, 0u, true, true, capture_report, &reports);
    int length = snprintf(script, sizeof(script), "KPHID1 qemu-smoke 2 2 100000 %08" PRIx32 "\n%s",
                          fixture_crc32(events, strlen(events)), events);
    if (length <= 0 || (size_t)length >= sizeof(script)) return false;
    if (!fixture_load_script(&fixture, script, (size_t)length, error, sizeof(error))) return false;
    if (!fixture_arm(&fixture, "qemu-smoke", error, sizeof(error))) return false;
    fixture_poll(&fixture, 1u, true, true, capture_report, &reports);
    if (!fixture_start(&fixture, "qemu-smoke", 100u, 0u, error, sizeof(error))) return false;
    fixture_poll(&fixture, 100000u, true, true, capture_report, &reports);
    fixture_poll(&fixture, 150000u, true, true, capture_report, &reports);
    fixture_poll(&fixture, 200000u, true, true, capture_report, &reports);
    fixture_poll(&fixture, 250000u, true, true, capture_report, &reports);

    static fixture_ui_model_t ui;
    fixture_ui_model_init(&ui);
    fixture_ui_input_t input = {
        .state = fixture.state,
        .wifi_connected = true,
        .usb_mounted = true,
        .event_count = fixture.event_count,
        .repeat_count = fixture.repeat_count,
        .reports_submitted = fixture.reports_submitted,
    };
    fixture_ui_output_t output = fixture_ui_model_step(&ui, &input, 250u);

    return fixture.state == FIXTURE_COMPLETE &&
           fixture.reports_submitted == 4u &&
           fixture_trace_count(&fixture) == 4u &&
           reports.count == 6u &&
           reports.final_key == 0u &&
           output.scene == FIXTURE_UI_COMPLETE &&
           output.progress_per_mille == 1000u;
}

void fixture_qemu_smoke_run(void) {
    if (run_core_smoke()) {
        esp_rom_printf("KEYPATH_QEMU_SMOKE_PASS\n");
    } else {
        esp_rom_printf("KEYPATH_QEMU_SMOKE_FAIL\n");
    }
}
