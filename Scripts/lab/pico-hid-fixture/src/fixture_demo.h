#ifndef KEYPATH_FIXTURE_DEMO_H
#define KEYPATH_FIXTURE_DEMO_H

#include <stdbool.h>
#include <stddef.h>

#include "fixture_core.h"

#define FIXTURE_DEMO_RUN_ID "offline-demo"
#define FIXTURE_DEMO_TEXT "KeyPath demo OK\n"

bool fixture_demo_load(fixture_t *fixture, char *error, size_t error_capacity);

#endif
