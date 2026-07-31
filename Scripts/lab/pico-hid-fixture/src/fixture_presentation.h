#ifndef KEYPATH_FIXTURE_PRESENTATION_H
#define KEYPATH_FIXTURE_PRESENTATION_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef enum {
    FIXTURE_PRESENT_AUTO = 0,
    FIXTURE_PRESENT_PREPARING,
    FIXTURE_PRESENT_COUNTDOWN,
    FIXTURE_PRESENT_TESTING,
    FIXTURE_PRESENT_OBSERVING,
    FIXTURE_PRESENT_RESOLVING,
    FIXTURE_PRESENT_RESULT,
    FIXTURE_PRESENT_NEXT,
} fixture_presentation_phase_t;

typedef enum {
    FIXTURE_RESULT_NONE = 0,
    FIXTURE_RESULT_PASS,
    FIXTURE_RESULT_FAIL,
    FIXTURE_RESULT_INCONCLUSIVE,
} fixture_result_t;

typedef enum {
    FIXTURE_BRAND_NONE = 0,
    FIXTURE_BRAND_KEYPATH,
    FIXTURE_BRAND_BEAR,
} fixture_presentation_brand_t;

typedef struct {
    fixture_presentation_phase_t phase;
    fixture_result_t result;
    fixture_presentation_brand_t brand;
    bool branded_firmware_update;
    uint16_t progress_per_mille;
    uint32_t reports_expected;
    uint32_t reports_observed;
    uint32_t dropped;
    uint32_t duplicated;
    uint32_t repeated;
    uint32_t latency_p95_us;
    bool safe_release;
    char title[33];
    char detail[49];
    char next[33];
} fixture_presentation_t;

void fixture_presentation_init(fixture_presentation_t *presentation);
const char *fixture_presentation_phase_name(fixture_presentation_phase_t phase);
const char *fixture_result_name(fixture_result_t result);
const char *fixture_presentation_brand_name(fixture_presentation_brand_t brand);
bool fixture_presentation_parse_phase(const char *value, fixture_presentation_phase_t *phase);
bool fixture_presentation_parse_result(const char *value, fixture_result_t *result);
bool fixture_presentation_parse_brand(const char *value, fixture_presentation_brand_t *brand);
bool fixture_presentation_text_valid(const char *value, size_t maximum_length);

#endif
