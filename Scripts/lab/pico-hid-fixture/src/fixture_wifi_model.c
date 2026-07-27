#include "fixture_wifi_model.h"

void fixture_wifi_model_init(fixture_wifi_model_t *model) {
    model->profile_index = 0u;
    model->failed_attempts = 0u;
}

bool fixture_wifi_model_note_disconnect(fixture_wifi_model_t *model,
                                        size_t profile_count,
                                        unsigned int attempts_per_profile) {
    if (profile_count == 0u || attempts_per_profile == 0u) return false;
    model->failed_attempts++;
    if (model->failed_attempts < attempts_per_profile) return false;

    model->failed_attempts = 0u;
    model->profile_index = (model->profile_index + 1u) % profile_count;
    return true;
}

void fixture_wifi_model_note_connected(fixture_wifi_model_t *model) {
    model->failed_attempts = 0u;
}
