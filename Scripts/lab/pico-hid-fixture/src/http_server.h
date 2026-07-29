#ifndef KEYPATH_FIXTURE_HTTP_SERVER_H
#define KEYPATH_FIXTURE_HTTP_SERVER_H

#include <stdbool.h>
#include <stdint.h>

#include "fixture_core.h"

bool fixture_http_server_init(fixture_t *fixture, const char *bearer_token, uint16_t port);
void fixture_http_set_network(bool connected, const char *address);

#endif
