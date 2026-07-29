#ifndef KEYPATH_FIXTURE_WIFI_MODEL_H
#define KEYPATH_FIXTURE_WIFI_MODEL_H

#include <stdbool.h>
#include <stddef.h>

typedef struct {
    size_t profile_index;
    unsigned int failed_attempts;
} fixture_wifi_model_t;

void fixture_wifi_model_init(fixture_wifi_model_t *model);
bool fixture_wifi_model_note_disconnect(fixture_wifi_model_t *model,
                                        size_t profile_count,
                                        unsigned int attempts_per_profile);
void fixture_wifi_model_note_connected(fixture_wifi_model_t *model);

#endif
