#include "fixture_splash_model.h"

static uint16_t smoothstep_per_mille(uint64_t elapsed, uint64_t duration) {
    if (elapsed >= duration) return 1000u;
    uint64_t t = elapsed * 1000u / duration;
    return (uint16_t)(t * t * (3000u - 2u * t) / 1000000u);
}

fixture_splash_output_t fixture_splash_step(uint64_t elapsed_ms) {
    fixture_splash_output_t output = {
        .background_opacity = 255u,
        .logo_scale = 228u,
    };

    uint16_t reveal = smoothstep_per_mille(elapsed_ms, FIXTURE_SPLASH_FADE_IN_MS);
    output.foreground_opacity = (uint8_t)(255u * reveal / 1000u);
    output.logo_scale = (uint16_t)(228u + 28u * reveal / 1000u);

    uint64_t wordmark_elapsed = elapsed_ms > 120u ? elapsed_ms - 120u : 0u;
    uint16_t wordmark_reveal = smoothstep_per_mille(wordmark_elapsed, 300u);
    output.wordmark_opacity = (uint8_t)(255u * wordmark_reveal / 1000u);

    if (elapsed_ms >= FIXTURE_SPLASH_HOLD_END_MS) {
        uint64_t fade_elapsed = elapsed_ms - FIXTURE_SPLASH_HOLD_END_MS;
        uint16_t fade = smoothstep_per_mille(fade_elapsed,
                                              FIXTURE_SPLASH_TOTAL_MS - FIXTURE_SPLASH_HOLD_END_MS);
        uint16_t remaining = (uint16_t)(1000u - fade);
        output.foreground_opacity = (uint8_t)(255u * remaining / 1000u);
        output.background_opacity = output.foreground_opacity;
        output.wordmark_opacity = output.foreground_opacity;
        output.logo_scale = (uint16_t)(256u + 18u * fade / 1000u);
    }

    if (elapsed_ms >= FIXTURE_SPLASH_TOTAL_MS) {
        output.foreground_opacity = 0u;
        output.background_opacity = 0u;
        output.wordmark_opacity = 0u;
        output.logo_scale = 274u;
        output.complete = true;
    }
    return output;
}
