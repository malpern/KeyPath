#include "fixture_core.h"

#include <ctype.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void set_error(char *target, size_t capacity, const char *message) {
    if (target && capacity) {
        snprintf(target, capacity, "%s", message ? message : "unknown error");
    }
}

static bool valid_run_id(const char *value) {
    size_t length = value ? strlen(value) : 0u;
    if (length == 0u || length > FIXTURE_MAX_RUN_ID) return false;
    for (size_t index = 0; index < length; ++index) {
        unsigned char character = (unsigned char)value[index];
        if (!(isalnum(character) || character == '-' || character == '_' || character == '.')) return false;
    }
    return true;
}

static bool report_is_empty(const fixture_event_t *event) {
    if (event->modifiers != 0u) return false;
    for (size_t index = 0; index < 6u; ++index) {
        if (event->keys[index] != 0u) return false;
    }
    return true;
}

static bool report_has_unique_keys(const fixture_event_t *event) {
    for (size_t left = 0; left < 6u; ++left) {
        if (event->keys[left] == 0u) continue;
        for (size_t right = left + 1u; right < 6u; ++right) {
            if (event->keys[left] == event->keys[right]) return false;
        }
    }
    return true;
}

void fixture_init(fixture_t *fixture) {
    memset(fixture, 0, sizeof(*fixture));
    fixture->state = FIXTURE_IDLE;
    fixture->pending_release = true;
}

const char *fixture_state_name(fixture_state_t state) {
    switch (state) {
        case FIXTURE_BOOTING: return "booting";
        case FIXTURE_IDLE: return "idle";
        case FIXTURE_LOADED: return "loaded";
        case FIXTURE_ARMED: return "armed";
        case FIXTURE_RUNNING: return "running";
        case FIXTURE_COMPLETE: return "complete";
        case FIXTURE_ABORTED: return "aborted";
        case FIXTURE_ERROR: return "error";
    }
    return "unknown";
}

uint32_t fixture_crc32(const void *bytes, size_t length) {
    const uint8_t *cursor = bytes;
    uint32_t crc = 0xffffffffu;
    for (size_t index = 0; index < length; ++index) {
        crc ^= cursor[index];
        for (uint8_t bit = 0; bit < 8u; ++bit) {
            crc = (crc >> 1u) ^ (0xedb88320u & (uint32_t)-(int32_t)(crc & 1u));
        }
    }
    return ~crc;
}

bool fixture_load_script(fixture_t *fixture, const char *body, size_t length,
                         char *error, size_t error_capacity) {
    if (!fixture || !body || length == 0u) {
        set_error(error, error_capacity, "script body is empty");
        return false;
    }
    if (fixture->state == FIXTURE_RUNNING || fixture->state == FIXTURE_ARMED) {
        set_error(error, error_capacity, "fixture is armed or running");
        return false;
    }

    // Invalidate the previous script before parsing into the fixture's bounded
    // event storage. A malformed replacement must never leave a partly
    // overwritten script available to arm.
    fixture->state = FIXTURE_IDLE;
    fixture->event_count = 0u;
    fixture->run_id[0] = '\0';

    const char *newline = memchr(body, '\n', length);
    if (!newline) {
        set_error(error, error_capacity, "script header is incomplete");
        return false;
    }
    size_t header_length = (size_t)(newline - body);
    if (header_length >= 160u) {
        set_error(error, error_capacity, "script header is too long");
        return false;
    }
    char header[160];
    memcpy(header, body, header_length);
    header[header_length] = '\0';

    char run_id[FIXTURE_MAX_RUN_ID + 1u] = {0};
    uint32_t event_count = 0u, repeat_count = 0u, cycle_us = 0u, declared_crc = 0u;
    char extra = '\0';
    int fields = sscanf(header, "KPHID1 %48s %" SCNu32 " %" SCNu32 " %" SCNu32 " %" SCNx32 " %c",
                        run_id, &event_count, &repeat_count, &cycle_us, &declared_crc, &extra);
    if (fields != 5) {
        set_error(error, error_capacity, "script header must be KPHID1 run events repeats cycle_us crc32");
        return false;
    }
    if (!valid_run_id(run_id)) {
        set_error(error, error_capacity, "run id contains unsupported characters");
        return false;
    }
    if (event_count == 0u || event_count > FIXTURE_MAX_EVENTS) {
        set_error(error, error_capacity, "event count is outside fixture limits");
        return false;
    }
    if (repeat_count == 0u || repeat_count > FIXTURE_MAX_REPEATS ||
        (uint64_t)event_count * repeat_count > FIXTURE_MAX_TOTAL_REPORTS) {
        set_error(error, error_capacity, "repeat count is outside fixture limits");
        return false;
    }
    if (cycle_us == 0u) {
        set_error(error, error_capacity, "cycle duration must be positive");
        return false;
    }

    const char *events_body = newline + 1;
    size_t events_length = length - (size_t)(events_body - body);
    if (fixture_crc32(events_body, events_length) != declared_crc) {
        set_error(error, error_capacity, "script CRC32 does not match payload");
        return false;
    }

    const char *cursor = events_body;
    const char *end = body + length;
    uint32_t previous_at = 0u;
    for (uint32_t index = 0u; index < event_count; ++index) {
        const char *line_end = memchr(cursor, '\n', (size_t)(end - cursor));
        if (!line_end) line_end = end;
        size_t line_length = (size_t)(line_end - cursor);
        if (line_length == 0u || line_length >= 128u) {
            set_error(error, error_capacity, "event line is empty or too long");
            return false;
        }
        char line[128];
        memcpy(line, cursor, line_length);
        line[line_length] = '\0';
        fixture_event_t event = {0};
        unsigned int values[7] = {0};
        fields = sscanf(line, "%" SCNu32 " %u %u %u %u %u %u %u %c", &event.at_us,
                        &values[0], &values[1], &values[2], &values[3], &values[4], &values[5], &values[6], &extra);
        if (fields != 8) {
            set_error(error, error_capacity, "event must contain time, modifiers, and six key usages");
            return false;
        }
        if ((index > 0u && event.at_us <= previous_at) || event.at_us >= cycle_us) {
            set_error(error, error_capacity, "event times must increase and remain inside the cycle");
            return false;
        }
        for (size_t value_index = 0u; value_index < 7u; ++value_index) {
            if (values[value_index] > 255u) {
                set_error(error, error_capacity, "HID report values must fit in one byte");
                return false;
            }
        }
        event.modifiers = (uint8_t)values[0];
        for (size_t key = 0u; key < 6u; ++key) event.keys[key] = (uint8_t)values[key + 1u];
        if (!report_has_unique_keys(&event)) {
            set_error(error, error_capacity, "a report contains duplicate nonzero key usages");
            return false;
        }
        fixture->events[index] = event;
        previous_at = event.at_us;
        cursor = line_end < end ? line_end + 1 : end;
    }
    while (cursor < end && isspace((unsigned char)*cursor)) ++cursor;
    if (cursor != end) {
        set_error(error, error_capacity, "script contains more event lines than declared");
        return false;
    }
    if (!report_is_empty(&fixture->events[event_count - 1u])) {
        set_error(error, error_capacity, "each cycle must end with an all-keys-released report");
        return false;
    }

    snprintf(fixture->run_id, sizeof(fixture->run_id), "%s", run_id);
    fixture->script_crc32 = declared_crc;
    fixture->event_count = event_count;
    fixture->repeat_count = repeat_count;
    fixture->cycle_us = cycle_us;
    fixture->state = FIXTURE_LOADED;
    fixture->next_event = 0u;
    fixture->current_repeat = 0u;
    fixture->reports_submitted = 0u;
    fixture->transfers_completed = 0u;
    fixture->late_reports = 0u;
    fixture->maximum_lateness_us = 0;
    fixture->submitted_crc32 = 0u;
    fixture->trace_head = 0u;
    fixture->trace_count = 0u;
    fixture->error[0] = '\0';
    set_error(error, error_capacity, "");
    return true;
}

bool fixture_arm(fixture_t *fixture, const char *run_id, char *error, size_t error_capacity) {
    if (fixture->state != FIXTURE_LOADED) {
        set_error(error, error_capacity, "a loaded script is required before arming");
        return false;
    }
    if (!run_id || strcmp(run_id, fixture->run_id) != 0) {
        set_error(error, error_capacity, "run id does not match loaded script");
        return false;
    }
    fixture->state = FIXTURE_ARMED;
    fixture->pending_release = true;
    return true;
}

bool fixture_start(fixture_t *fixture, const char *run_id, uint32_t delay_ms, uint64_t now_us,
                   char *error, size_t error_capacity) {
    if (fixture->state != FIXTURE_ARMED) {
        set_error(error, error_capacity, "fixture must be armed before starting");
        return false;
    }
    if (!run_id || strcmp(run_id, fixture->run_id) != 0) {
        set_error(error, error_capacity, "run id does not match armed script");
        return false;
    }
    if (delay_ms < 100u || delay_ms > 60000u) {
        set_error(error, error_capacity, "start delay must be between 100 and 60000 ms");
        return false;
    }
    fixture->start_at_us = now_us + (uint64_t)delay_ms * 1000u;
    fixture->next_event = 0u;
    fixture->current_repeat = 0u;
    fixture->state = FIXTURE_RUNNING;
    return true;
}

void fixture_abort(fixture_t *fixture, const char *reason) {
    if (!fixture) return;
    fixture->state = FIXTURE_ABORTED;
    fixture->pending_release = true;
    snprintf(fixture->error, sizeof(fixture->error), "%s", reason ? reason : "aborted");
}

void fixture_note_transfer_complete(fixture_t *fixture) {
    if (fixture) fixture->transfers_completed++;
}

static void trace_report(fixture_t *fixture, uint64_t scheduled, uint64_t submitted,
                         uint8_t modifiers, const uint8_t keys[6]) {
    uint32_t slot = fixture->trace_head;
    fixture_trace_t *trace = &fixture->trace[slot];
    trace->sequence = fixture->reports_submitted;
    trace->scheduled_us = scheduled;
    trace->submitted_us = submitted;
    trace->lateness_us = (int64_t)(submitted - scheduled);
    trace->modifiers = modifiers;
    memcpy(trace->keys, keys, 6u);
    fixture->trace_head = (slot + 1u) % FIXTURE_TRACE_CAPACITY;
    if (fixture->trace_count < FIXTURE_TRACE_CAPACITY) fixture->trace_count++;
}

static bool submit_report(fixture_t *fixture, uint64_t scheduled, uint64_t now_us,
                          uint8_t modifiers, const uint8_t keys[6],
                          fixture_send_report_fn send_report, void *send_context) {
    if (!send_report(modifiers, keys, send_context)) return false;
    int64_t lateness = (int64_t)(now_us - scheduled);
    fixture->reports_submitted++;
    if (lateness > 1000) fixture->late_reports++;
    if (lateness > fixture->maximum_lateness_us) fixture->maximum_lateness_us = lateness;
    uint8_t report[7] = {modifiers, keys[0], keys[1], keys[2], keys[3], keys[4], keys[5]};
    fixture->submitted_crc32 ^= fixture_crc32(report, sizeof(report)) + (uint32_t)fixture->reports_submitted;
    trace_report(fixture, scheduled, now_us, modifiers, keys);
    return true;
}

void fixture_poll(fixture_t *fixture, uint64_t now_us, bool usb_mounted, bool usb_ready,
                  fixture_send_report_fn send_report, void *send_context) {
    if (!fixture || !send_report) return;
    if (fixture->usb_mounted && !usb_mounted && fixture->state == FIXTURE_RUNNING) {
        fixture->state = FIXTURE_ERROR;
        fixture->pending_release = true;
        snprintf(fixture->error, sizeof(fixture->error), "USB unmounted during a running script");
    }
    fixture->usb_mounted = usb_mounted;
    if (!usb_mounted || !usb_ready) return;

    static const uint8_t empty_keys[6] = {0};
    if (fixture->pending_release) {
        if (send_report(0u, empty_keys, send_context)) fixture->pending_release = false;
        return;
    }
    if (fixture->state != FIXTURE_RUNNING || now_us < fixture->start_at_us) return;

    uint64_t scheduled = fixture->start_at_us + (uint64_t)fixture->current_repeat * fixture->cycle_us +
                         fixture->events[fixture->next_event].at_us;
    if (now_us < scheduled) return;
    fixture_event_t *event = &fixture->events[fixture->next_event];
    if (!submit_report(fixture, scheduled, now_us, event->modifiers, event->keys, send_report, send_context)) return;

    fixture->next_event++;
    if (fixture->next_event == fixture->event_count) {
        fixture->next_event = 0u;
        fixture->current_repeat++;
        if (fixture->current_repeat == fixture->repeat_count) fixture->state = FIXTURE_COMPLETE;
    }
}

uint32_t fixture_trace_count(const fixture_t *fixture) {
    return fixture ? fixture->trace_count : 0u;
}

const fixture_trace_t *fixture_trace_at(const fixture_t *fixture, uint32_t chronological_index) {
    if (!fixture || chronological_index >= fixture->trace_count) return NULL;
    uint32_t oldest = (fixture->trace_head + FIXTURE_TRACE_CAPACITY - fixture->trace_count) % FIXTURE_TRACE_CAPACITY;
    return &fixture->trace[(oldest + chronological_index) % FIXTURE_TRACE_CAPACITY];
}
