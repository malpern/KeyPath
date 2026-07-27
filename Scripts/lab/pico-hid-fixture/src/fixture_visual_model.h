#ifndef KEYPATH_FIXTURE_VISUAL_MODEL_H
#define KEYPATH_FIXTURE_VISUAL_MODEL_H

#include <stdint.h>

#include "fixture_presentation.h"
#include "fixture_ui_model.h"

typedef enum {
    FIXTURE_ICON_POWER = 0,
    FIXTURE_ICON_WIFI,
    FIXTURE_ICON_KEYBOARD,
    FIXTURE_ICON_DOWNLOAD,
    FIXTURE_ICON_WARNING,
    FIXTURE_ICON_PLAY,
    FIXTURE_ICON_OK,
    FIXTURE_ICON_STOP,
    FIXTURE_ICON_CLOSE,
    FIXTURE_ICON_REFRESH,
    FIXTURE_ICON_BELL,
    FIXTURE_ICON_EYE,
    FIXTURE_ICON_SETTINGS,
    FIXTURE_ICON_NEXT,
} fixture_visual_icon_t;

typedef struct {
    fixture_visual_icon_t icon;
    uint32_t accent_rgb;
    uint16_t progress_per_mille;
    uint16_t angular_speed_milliradians;
    char title[33];
} fixture_visual_output_t;

void fixture_visual_resolve(const fixture_ui_output_t *ui,
                            const fixture_presentation_t *presentation,
                            fixture_visual_output_t *visual);

#endif
