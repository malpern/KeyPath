#ifndef KEYPATH_ESP32_FIXTURE_RUNTIME_H
#define KEYPATH_ESP32_FIXTURE_RUNTIME_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "esp_err.h"
#include "fixture_core.h"
#include "fixture_presentation.h"
#include "fixture_ui_model.h"

typedef struct {
    fixture_ui_input_t ui;
    char run_id[FIXTURE_MAX_RUN_ID + 1u];
    char error[128];
    uint32_t script_crc32;
    uint32_t next_event;
    uint64_t transfers_completed;
    uint32_t submitted_crc32;
    fixture_presentation_t presentation;
} fixture_runtime_snapshot_t;

void fixture_runtime_init(void);
esp_err_t fixture_runtime_start_usb(void);
void fixture_runtime_start_executor(void);
void fixture_runtime_set_network(bool connected, const char *address);
void fixture_runtime_snapshot(fixture_runtime_snapshot_t *snapshot);
void fixture_runtime_network_snapshot(bool *connected, char *address, size_t capacity);
bool fixture_runtime_load(const char *body, size_t length, char *error, size_t capacity);
bool fixture_runtime_arm(const char *run_id, char *error, size_t capacity);
bool fixture_runtime_start(const char *run_id, uint32_t delay_ms, char *error, size_t capacity);
void fixture_runtime_abort(const char *reason);
void fixture_runtime_set_presentation(const fixture_presentation_t *presentation);
uint32_t fixture_runtime_trace_count(void);
bool fixture_runtime_trace_at(uint32_t index, fixture_trace_t *trace);

#endif
