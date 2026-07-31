#include "fixture_presentation.h"

#include <ctype.h>
#include <string.h>

void fixture_presentation_init(fixture_presentation_t *presentation) {
    memset(presentation, 0, sizeof(*presentation));
    presentation->phase = FIXTURE_PRESENT_AUTO;
}

const char *fixture_presentation_phase_name(fixture_presentation_phase_t phase) {
    switch (phase) {
        case FIXTURE_PRESENT_AUTO: return "auto";
        case FIXTURE_PRESENT_PREPARING: return "preparing";
        case FIXTURE_PRESENT_COUNTDOWN: return "countdown";
        case FIXTURE_PRESENT_TESTING: return "testing";
        case FIXTURE_PRESENT_OBSERVING: return "observing";
        case FIXTURE_PRESENT_RESOLVING: return "resolving";
        case FIXTURE_PRESENT_RESULT: return "result";
        case FIXTURE_PRESENT_NEXT: return "next";
    }
    return "auto";
}

const char *fixture_result_name(fixture_result_t result) {
    switch (result) {
        case FIXTURE_RESULT_NONE: return "none";
        case FIXTURE_RESULT_PASS: return "pass";
        case FIXTURE_RESULT_FAIL: return "fail";
        case FIXTURE_RESULT_INCONCLUSIVE: return "inconclusive";
    }
    return "none";
}

const char *fixture_presentation_brand_name(fixture_presentation_brand_t brand) {
    switch (brand) {
        case FIXTURE_BRAND_NONE: return "none";
        case FIXTURE_BRAND_KEYPATH: return "keypath";
        case FIXTURE_BRAND_BEAR: return "bear";
    }
    return "none";
}

bool fixture_presentation_parse_phase(const char *value, fixture_presentation_phase_t *phase) {
    if (!value || !phase) return false;
    for (int candidate = FIXTURE_PRESENT_AUTO; candidate <= FIXTURE_PRESENT_NEXT; ++candidate) {
        if (strcmp(value, fixture_presentation_phase_name((fixture_presentation_phase_t)candidate)) == 0) {
            *phase = (fixture_presentation_phase_t)candidate;
            return true;
        }
    }
    return false;
}

bool fixture_presentation_parse_result(const char *value, fixture_result_t *result) {
    if (!value || !result) return false;
    for (int candidate = FIXTURE_RESULT_NONE; candidate <= FIXTURE_RESULT_INCONCLUSIVE; ++candidate) {
        if (strcmp(value, fixture_result_name((fixture_result_t)candidate)) == 0) {
            *result = (fixture_result_t)candidate;
            return true;
        }
    }
    return false;
}

bool fixture_presentation_parse_brand(const char *value, fixture_presentation_brand_t *brand) {
    if (!value || !brand) return false;
    for (int candidate = FIXTURE_BRAND_NONE; candidate <= FIXTURE_BRAND_BEAR; ++candidate) {
        if (strcmp(value, fixture_presentation_brand_name((fixture_presentation_brand_t)candidate)) == 0) {
            *brand = (fixture_presentation_brand_t)candidate;
            return true;
        }
    }
    return false;
}

bool fixture_presentation_text_valid(const char *value, size_t maximum_length) {
    if (!value || strlen(value) > maximum_length) return false;
    for (const unsigned char *cursor = (const unsigned char *)value; *cursor; ++cursor) {
        if (*cursor < 0x20u || *cursor > 0x7eu || *cursor == '"' || *cursor == '\\') return false;
    }
    return true;
}
