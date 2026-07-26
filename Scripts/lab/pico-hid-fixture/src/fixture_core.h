#ifndef KEYPATH_FIXTURE_CORE_H
#define KEYPATH_FIXTURE_CORE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define FIXTURE_MAX_EVENTS 2048u
#define FIXTURE_MAX_REPEATS 10000u
#define FIXTURE_MAX_TOTAL_REPORTS 1000000u
#define FIXTURE_MAX_RUN_ID 48u
#define FIXTURE_TRACE_CAPACITY 256u

typedef enum {
    FIXTURE_BOOTING = 0,
    FIXTURE_IDLE,
    FIXTURE_LOADED,
    FIXTURE_ARMED,
    FIXTURE_RUNNING,
    FIXTURE_COMPLETE,
    FIXTURE_ABORTED,
    FIXTURE_ERROR,
} fixture_state_t;

typedef struct {
    uint32_t at_us;
    uint8_t modifiers;
    uint8_t keys[6];
} fixture_event_t;

typedef struct {
    uint64_t sequence;
    uint64_t scheduled_us;
    uint64_t submitted_us;
    int64_t lateness_us;
    uint8_t modifiers;
    uint8_t keys[6];
} fixture_trace_t;

typedef struct {
    fixture_state_t state;
    char run_id[FIXTURE_MAX_RUN_ID + 1u];
    uint32_t script_crc32;
    uint32_t event_count;
    uint32_t repeat_count;
    uint32_t cycle_us;
    fixture_event_t events[FIXTURE_MAX_EVENTS];

    uint64_t start_at_us;
    uint32_t next_event;
    uint32_t current_repeat;
    uint64_t reports_submitted;
    uint64_t transfers_completed;
    uint64_t late_reports;
    int64_t maximum_lateness_us;
    uint32_t submitted_crc32;
    bool pending_release;
    bool usb_mounted;

    fixture_trace_t trace[FIXTURE_TRACE_CAPACITY];
    uint32_t trace_head;
    uint32_t trace_count;
    char error[128];
} fixture_t;

typedef bool (*fixture_send_report_fn)(uint8_t modifiers, const uint8_t keys[6], void *context);

void fixture_init(fixture_t *fixture);
const char *fixture_state_name(fixture_state_t state);
uint32_t fixture_crc32(const void *bytes, size_t length);

bool fixture_load_script(fixture_t *fixture, const char *body, size_t length,
                         char *error, size_t error_capacity);
bool fixture_arm(fixture_t *fixture, const char *run_id, char *error, size_t error_capacity);
bool fixture_start(fixture_t *fixture, const char *run_id, uint32_t delay_ms, uint64_t now_us,
                   char *error, size_t error_capacity);
void fixture_abort(fixture_t *fixture, const char *reason);
void fixture_note_transfer_complete(fixture_t *fixture);
void fixture_poll(fixture_t *fixture, uint64_t now_us, bool usb_mounted, bool usb_ready,
                  fixture_send_report_fn send_report, void *send_context);

uint32_t fixture_trace_count(const fixture_t *fixture);
const fixture_trace_t *fixture_trace_at(const fixture_t *fixture, uint32_t chronological_index);

#endif
