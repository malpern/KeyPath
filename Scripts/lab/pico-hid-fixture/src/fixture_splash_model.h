#ifndef KEYPATH_FIXTURE_SPLASH_MODEL_H
#define KEYPATH_FIXTURE_SPLASH_MODEL_H

#include <stdbool.h>
#include <stdint.h>

#define FIXTURE_SPLASH_FADE_IN_MS 260u
#define FIXTURE_SPLASH_HOLD_END_MS 1200u
#define FIXTURE_SPLASH_TOTAL_MS 1650u

typedef struct {
    uint8_t foreground_opacity;
    uint8_t background_opacity;
    uint8_t wordmark_opacity;
    uint16_t logo_scale;
    bool complete;
} fixture_splash_output_t;

fixture_splash_output_t fixture_splash_step(uint64_t elapsed_ms);

#endif
