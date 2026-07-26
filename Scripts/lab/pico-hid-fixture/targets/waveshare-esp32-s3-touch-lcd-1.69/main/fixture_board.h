#ifndef KEYPATH_ESP32_FIXTURE_BOARD_H
#define KEYPATH_ESP32_FIXTURE_BOARD_H

#include <stdbool.h>

void fixture_board_init(void);
void fixture_board_tone(unsigned int frequency_hz, unsigned int duration_ms);
void fixture_board_update(bool armed_or_running);

#endif
