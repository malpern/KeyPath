#include "fixture_sound_model.h"

void fixture_sound_model_init(fixture_sound_model_t *model) {
    if (!model) return;
    model->silent = true;
}

bool fixture_sound_model_toggle(fixture_sound_model_t *model) {
    if (!model) return true;
    model->silent = !model->silent;
    return model->silent;
}
