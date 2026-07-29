#ifndef KEYPATH_ESP32_FIXTURE_DISPLAY_H
#define KEYPATH_ESP32_FIXTURE_DISPLAY_H

#include <stdbool.h>
#include <stdint.h>

typedef struct {
    bool initialized;
    bool splash_enabled;
    bool splash_complete;
    uint64_t frame_sequence;
    uint64_t last_frame_ms;
} fixture_display_health_t;

void fixture_display_start(void);
void fixture_display_health_snapshot(fixture_display_health_t *health);
bool fixture_display_is_healthy(void);

#endif
