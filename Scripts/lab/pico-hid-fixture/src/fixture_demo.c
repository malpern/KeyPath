#include "fixture_demo.h"

#include <ctype.h>

#define DEMO_SHIFT 0x02u
#define DEMO_INTERVAL_US 60000u
#define DEMO_HOLD_US 20000u
#define DEMO_SHIFT_LEAD_US 5000u
#define DEMO_SHIFT_RELEASE_LAG_US 5000u
#define DEMO_REPEAT_COUNT 14u
#define DEMO_CYCLE_GAP_US 469000u

static bool demo_usage(char character, uint8_t *usage, bool *shifted) {
    if (character >= 'a' && character <= 'z') {
        *usage = (uint8_t)(0x04u + (uint8_t)(character - 'a'));
        *shifted = false;
        return true;
    }
    if (character >= 'A' && character <= 'Z') {
        *usage = (uint8_t)(0x04u + (uint8_t)(tolower((unsigned char)character) - 'a'));
        *shifted = true;
        return true;
    }
    if (character == ' ') {
        *usage = 0x2cu;
        *shifted = false;
        return true;
    }
    if (character == '\n') {
        *usage = 0x28u;
        *shifted = false;
        return true;
    }
    return false;
}

bool fixture_demo_load(fixture_t *fixture, char *error, size_t error_capacity) {
    fixture_event_t events[sizeof(FIXTURE_DEMO_TEXT) * 4u] = {0};
    uint32_t event_count = 0u;
    uint32_t character_index = 0u;
    for (const char *cursor = FIXTURE_DEMO_TEXT; *cursor; ++cursor, ++character_index) {
        uint8_t usage = 0u;
        bool shifted = false;
        if (!demo_usage(*cursor, &usage, &shifted)) return false;
        uint32_t base_us = character_index * DEMO_INTERVAL_US;
        if (shifted) {
            events[event_count++] = (fixture_event_t){.at_us = base_us, .modifiers = DEMO_SHIFT};
            events[event_count++] = (fixture_event_t){
                .at_us = base_us + DEMO_SHIFT_LEAD_US,
                .modifiers = DEMO_SHIFT,
                .keys = {usage},
            };
            events[event_count++] = (fixture_event_t){
                .at_us = base_us + DEMO_SHIFT_LEAD_US + DEMO_HOLD_US,
                .modifiers = DEMO_SHIFT,
            };
            events[event_count++] = (fixture_event_t){
                .at_us = base_us + DEMO_SHIFT_LEAD_US + DEMO_HOLD_US + DEMO_SHIFT_RELEASE_LAG_US,
            };
        } else {
            events[event_count++] = (fixture_event_t){.at_us = base_us, .keys = {usage}};
            events[event_count++] = (fixture_event_t){.at_us = base_us + DEMO_HOLD_US};
        }
    }
    uint32_t cycle_us = character_index * DEMO_INTERVAL_US + DEMO_CYCLE_GAP_US;
    return fixture_load_events(fixture, FIXTURE_DEMO_RUN_ID, events, event_count,
                               DEMO_REPEAT_COUNT, cycle_us,
                               error, error_capacity);
}
