#ifndef KEYPATH_ESP32_FIXTURE_HTTP_H
#define KEYPATH_ESP32_FIXTURE_HTTP_H

#include <stdbool.h>

#include "esp_err.h"

esp_err_t fixture_network_start(void);
bool fixture_network_control_ready(void);

#endif
