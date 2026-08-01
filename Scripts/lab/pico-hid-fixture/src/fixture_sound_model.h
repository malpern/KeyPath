#ifndef KEYPATH_FIXTURE_SOUND_MODEL_H
#define KEYPATH_FIXTURE_SOUND_MODEL_H

#include <stdbool.h>

typedef struct {
    bool silent;
} fixture_sound_model_t;

void fixture_sound_model_init(fixture_sound_model_t *model);
bool fixture_sound_model_toggle(fixture_sound_model_t *model);

#endif
