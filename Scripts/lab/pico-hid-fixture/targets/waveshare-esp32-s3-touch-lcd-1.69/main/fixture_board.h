#ifndef KEYPATH_ESP32_FIXTURE_BOARD_H
#define KEYPATH_ESP32_FIXTURE_BOARD_H

#include <stdbool.h>
#include <stdint.h>

#include "fixture_button_feedback.h"

typedef struct {
    fixture_button_event_t event;
    uint32_t sequence;
    bool boot_held;
    bool download_hint;
} fixture_board_feedback_t;

void fixture_board_init(void);
void fixture_board_tone(unsigned int frequency_hz, unsigned int duration_ms);
void fixture_board_update(bool armed_or_running);
void fixture_board_feedback_snapshot(fixture_board_feedback_t *feedback);

#endif
