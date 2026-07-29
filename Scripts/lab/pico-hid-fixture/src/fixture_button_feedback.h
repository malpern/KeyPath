#ifndef KEYPATH_FIXTURE_BUTTON_FEEDBACK_H
#define KEYPATH_FIXTURE_BUTTON_FEEDBACK_H

#include <stdbool.h>
#include <stdint.h>

#define FIXTURE_BUTTON_FEEDBACK_DURATION_MS 1200u

typedef enum {
    FIXTURE_BUTTON_NONE = 0,
    FIXTURE_BUTTON_POWER,
    FIXTURE_BUTTON_BOOT,
    FIXTURE_BUTTON_RESET,
} fixture_button_event_t;

typedef struct {
    bool active;
    const char *title;
    const char *detail;
    uint32_t accent_rgb;
    uint16_t pulse_per_mille;
} fixture_button_feedback_output_t;

fixture_button_feedback_output_t fixture_button_feedback_resolve(
    fixture_button_event_t event, bool boot_held, bool download_hint,
    uint64_t elapsed_ms);

#endif
