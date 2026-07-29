#include "fixture_button_feedback.h"

fixture_button_feedback_output_t fixture_button_feedback_resolve(
    fixture_button_event_t event, bool boot_held, bool download_hint,
    uint64_t elapsed_ms) {
    fixture_button_feedback_output_t output = {0};
    bool sustained_boot_feedback = event == FIXTURE_BUTTON_BOOT && boot_held;
    if (event == FIXTURE_BUTTON_NONE ||
        (!sustained_boot_feedback && elapsed_ms >= FIXTURE_BUTTON_FEEDBACK_DURATION_MS)) {
        return output;
    }

    output.active = true;
    switch (event) {
        case FIXTURE_BUTTON_POWER:
            output.title = "POWER BUTTON";
            output.detail = "TOP button detected";
            output.accent_rgb = 0xffb454u;
            break;
        case FIXTURE_BUTTON_BOOT:
            if (boot_held && download_hint) {
                output.title = "BOOT HELD";
                output.detail = "KEEP HOLDING + TAP BOTTOM RESET";
            } else if (download_hint) {
                output.title = "BOOT RELEASED";
                output.detail = "Hold it while tapping RESET";
            } else {
                output.title = "BOOT BUTTON";
                output.detail = "Test abort requested";
            }
            output.accent_rgb = 0x55c7ffu;
            break;
        case FIXTURE_BUTTON_RESET:
            output.title = "RESET / START";
            output.detail = "BOTTOM RST or power cycle";
            output.accent_rgb = 0xff6b6bu;
            break;
        case FIXTURE_BUTTON_NONE:
            return output;
    }

    uint64_t phase_ms = elapsed_ms % 360u;
    uint64_t triangle_ms = phase_ms <= 180u ? phase_ms : 360u - phase_ms;
    output.pulse_per_mille = (uint16_t)(triangle_ms * 1000u / 180u);
    return output;
}
