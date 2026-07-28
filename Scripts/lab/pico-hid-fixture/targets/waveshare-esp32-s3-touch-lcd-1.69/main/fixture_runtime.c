#include "fixture_runtime.h"

#include <stdio.h>
#include <string.h>

#include "class/hid/hid_device.h"
#include "esp_mac.h"
#include "esp_rom_sys.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#include "tinyusb.h"
#include "tinyusb_default_config.h"

#define REPORT_ID_KEYBOARD 1u
#define HID_ENDPOINT 0x81u
#define CONFIGURATION_LENGTH (TUD_CONFIG_DESC_LEN + TUD_HID_DESC_LEN)

static fixture_t fixture;
static StaticSemaphore_t fixture_mutex_storage;
static SemaphoreHandle_t fixture_mutex;
static bool network_connected;
static char network_address[48] = "unassigned";
static char network_name[33] = "unassigned";
static fixture_presentation_t presentation;
static bool firmware_update_in_progress;

static void runtime_lock(void) {
    configASSERT(xSemaphoreTake(fixture_mutex, portMAX_DELAY) == pdTRUE);
}

static void runtime_unlock(void) {
    configASSERT(xSemaphoreGive(fixture_mutex) == pdTRUE);
}

static const tusb_desc_device_t device_descriptor = {
    .bLength = sizeof(tusb_desc_device_t),
    .bDescriptorType = TUSB_DESC_DEVICE,
    .bcdUSB = 0x0200,
    .bDeviceClass = 0,
    .bDeviceSubClass = 0,
    .bDeviceProtocol = 0,
    .bMaxPacketSize0 = CFG_TUD_ENDPOINT0_SIZE,
    .idVendor = 0xcafe,
    .idProduct = 0x4010,
    .bcdDevice = 0x0200,
    .iManufacturer = 1,
    .iProduct = 2,
    .iSerialNumber = 3,
    .bNumConfigurations = 1,
};

static const uint8_t hid_report_descriptor[] = {
    TUD_HID_REPORT_DESC_KEYBOARD(HID_REPORT_ID(REPORT_ID_KEYBOARD)),
};

static const uint8_t configuration_descriptor[] = {
    TUD_CONFIG_DESCRIPTOR(1, 1, 0, CONFIGURATION_LENGTH,
                          TUSB_DESC_CONFIG_ATT_REMOTE_WAKEUP, 100),
    TUD_HID_DESCRIPTOR(0, 4, HID_ITF_PROTOCOL_KEYBOARD,
                       sizeof(hid_report_descriptor), HID_ENDPOINT, 16, 1),
};

static char serial_number[13];
static const char *string_descriptors[] = {
    (const char[]){0x09, 0x04},
    "KeyPath Lab",
    "KeyPath Physical HID Fixture",
    serial_number,
    "Keyboard oracle",
};

uint8_t const *tud_hid_descriptor_report_cb(uint8_t instance) {
    (void)instance;
    return hid_report_descriptor;
}

uint16_t tud_hid_get_report_cb(uint8_t instance, uint8_t report_id,
                               hid_report_type_t report_type, uint8_t *buffer,
                               uint16_t requested_length) {
    (void)instance;
    (void)report_id;
    (void)report_type;
    (void)buffer;
    (void)requested_length;
    return 0u;
}

void tud_hid_set_report_cb(uint8_t instance, uint8_t report_id,
                           hid_report_type_t report_type, uint8_t const *buffer,
                           uint16_t buffer_size) {
    (void)instance;
    (void)report_id;
    (void)report_type;
    (void)buffer;
    (void)buffer_size;
}

void tud_hid_report_complete_cb(uint8_t instance, uint8_t const *report, uint16_t length) {
    (void)instance;
    (void)report;
    (void)length;
    runtime_lock();
    fixture_note_transfer_complete(&fixture);
    runtime_unlock();
}

static bool send_keyboard_report(uint8_t modifiers, const uint8_t keys[6], void *context) {
    (void)context;
    return tud_hid_ready() && tud_hid_keyboard_report(REPORT_ID_KEYBOARD, modifiers, keys);
}

static void executor_task(void *context) {
    (void)context;
    while (true) {
        bool running;
        uint32_t wait_us;
        runtime_lock();
        uint64_t now_us = (uint64_t)esp_timer_get_time();
        fixture_poll(&fixture, now_us, tud_mounted(), tud_hid_ready(),
                     send_keyboard_report, NULL);
        running = fixture.state == FIXTURE_RUNNING;
        wait_us = fixture_time_until_next_action_us(&fixture, now_us);
        runtime_unlock();

        if (!running) {
            /* USB mount and safety-release state do not need a 1 kHz idle poll. */
            vTaskDelay(pdMS_TO_TICKS(5));
        } else if (wait_us > 1500u) {
            /*
             * Leave at least 1 ms for the precision spin, but yield frequently enough
             * that touch, HTTP abort, and status snapshots can acquire the state lock.
             */
            uint32_t sleep_ms = (wait_us - 1000u) / 1000u;
            if (sleep_ms > 10u) sleep_ms = 10u;
            vTaskDelay(pdMS_TO_TICKS(sleep_ms));
        } else {
            esp_rom_delay_us(25u);
        }
    }
}

void fixture_runtime_init(void) {
    fixture_mutex = xSemaphoreCreateMutexStatic(&fixture_mutex_storage);
    configASSERT(fixture_mutex);
    fixture_init(&fixture);
    fixture_presentation_init(&presentation);
}

esp_err_t fixture_runtime_start_usb(void) {
    uint8_t mac[6];
    esp_err_t result = esp_read_mac(mac, ESP_MAC_WIFI_STA);
    if (result != ESP_OK) return result;
    snprintf(serial_number, sizeof(serial_number), "%02X%02X%02X%02X%02X%02X",
             mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);

    tinyusb_config_t config = TINYUSB_DEFAULT_CONFIG();
    /* Keep USB service off the dedicated, busy-waiting HID scheduler core. */
    config.task = TINYUSB_TASK_CUSTOM(4096, 18, 0);
    config.descriptor.device = &device_descriptor;
    config.descriptor.full_speed_config = configuration_descriptor;
#if (TUD_OPT_HIGH_SPEED)
    config.descriptor.high_speed_config = configuration_descriptor;
#endif
    config.descriptor.string = string_descriptors;
    config.descriptor.string_count = sizeof(string_descriptors) / sizeof(string_descriptors[0]);
    return tinyusb_driver_install(&config);
}

void fixture_runtime_start_executor(void) {
    configASSERT(xTaskCreatePinnedToCore(executor_task, "fixture_hid", 4096, NULL, 20, NULL, 1) == pdPASS);
}

void fixture_runtime_set_network(bool connected, const char *address) {
    runtime_lock();
    if (network_connected && !connected) {
        fixture_abort_if_active(&fixture, "Wi-Fi disconnected during active run");
    }
    network_connected = connected;
    snprintf(network_address, sizeof(network_address), "%s", address ? address : "unassigned");
    runtime_unlock();
}

void fixture_runtime_set_network_name(const char *name) {
    runtime_lock();
    snprintf(network_name, sizeof(network_name), "%s", name ? name : "unassigned");
    runtime_unlock();
}

void fixture_runtime_snapshot(fixture_runtime_snapshot_t *snapshot) {
    memset(snapshot, 0, sizeof(*snapshot));
    runtime_lock();
    snapshot->ui.state = fixture.state;
    snapshot->ui.wifi_connected = network_connected;
    snapshot->ui.usb_mounted = fixture.usb_mounted;
    snapshot->ui.event_count = fixture.event_count;
    snapshot->ui.repeat_count = fixture.repeat_count;
    snapshot->ui.current_repeat = fixture.current_repeat;
    snapshot->ui.reports_submitted = fixture.reports_submitted;
    snapshot->ui.late_reports = fixture.late_reports;
    snapshot->ui.maximum_lateness_us = fixture.maximum_lateness_us;
    snprintf(snapshot->run_id, sizeof(snapshot->run_id), "%s", fixture.run_id);
    snprintf(snapshot->error, sizeof(snapshot->error), "%s", fixture.error);
    snprintf(snapshot->network_address, sizeof(snapshot->network_address), "%s", network_address);
    snprintf(snapshot->network_name, sizeof(snapshot->network_name), "%s", network_name);
    snapshot->script_crc32 = fixture.script_crc32;
    snapshot->next_event = fixture.next_event;
    snapshot->transfers_completed = fixture.transfers_completed;
    snapshot->submitted_crc32 = fixture.submitted_crc32;
    snapshot->pending_release = fixture.pending_release;
    snapshot->firmware_update_in_progress = firmware_update_in_progress;
    snapshot->presentation = presentation;
    runtime_unlock();
}

bool fixture_runtime_load(const char *body, size_t length, char *error, size_t capacity) {
    runtime_lock();
    bool ok = false;
    if (firmware_update_in_progress) {
        snprintf(error, capacity, "firmware update in progress");
    } else {
        ok = fixture_load_script(&fixture, body, length, error, capacity);
    }
    runtime_unlock();
    return ok;
}

bool fixture_runtime_arm(const char *run_id, char *error, size_t capacity) {
    runtime_lock();
    bool ok = false;
    if (firmware_update_in_progress) {
        snprintf(error, capacity, "firmware update in progress");
    } else {
        ok = fixture_arm(&fixture, run_id, error, capacity);
    }
    runtime_unlock();
    return ok;
}

bool fixture_runtime_start(const char *run_id, uint32_t delay_ms, char *error, size_t capacity) {
    runtime_lock();
    bool ok = false;
    if (firmware_update_in_progress) {
        snprintf(error, capacity, "firmware update in progress");
    } else {
        ok = fixture_start(&fixture, run_id, delay_ms, (uint64_t)esp_timer_get_time(), error, capacity);
    }
    runtime_unlock();
    return ok;
}

void fixture_runtime_abort(const char *reason) {
    runtime_lock();
    fixture_abort(&fixture, reason);
    runtime_unlock();
}

void fixture_runtime_set_presentation(const fixture_presentation_t *value) {
    runtime_lock();
    presentation = *value;
    runtime_unlock();
}

bool fixture_runtime_begin_firmware_update(char *error, size_t capacity) {
    runtime_lock();
    bool terminal = fixture.state == FIXTURE_IDLE || fixture.state == FIXTURE_COMPLETE ||
                    fixture.state == FIXTURE_ABORTED || fixture.state == FIXTURE_ERROR;
    bool safe = terminal && !fixture.pending_release && !firmware_update_in_progress;
    if (!safe) {
        if (firmware_update_in_progress) {
            snprintf(error, capacity, "firmware update already in progress");
        } else if (fixture.pending_release) {
            snprintf(error, capacity, "waiting for the all-keys-released safety report");
        } else {
            snprintf(error, capacity, "fixture must be idle or in a terminal state before updating");
        }
    } else {
        firmware_update_in_progress = true;
        fixture_presentation_init(&presentation);
        presentation.branded_firmware_update = true;
        presentation.phase = FIXTURE_PRESENT_PREPARING;
        snprintf(presentation.title, sizeof(presentation.title), "FIRMWARE UPDATE");
        snprintf(presentation.detail, sizeof(presentation.detail), "AUTHENTICATING IMAGE");
        snprintf(presentation.next, sizeof(presentation.next), "KEEP POWER CONNECTED");
    }
    runtime_unlock();
    return safe;
}

void fixture_runtime_set_firmware_update_progress(uint16_t progress_per_mille, const char *detail) {
    runtime_lock();
    if (firmware_update_in_progress) {
        presentation.phase = FIXTURE_PRESENT_PREPARING;
        presentation.progress_per_mille = progress_per_mille > 1000u ? 1000u : progress_per_mille;
        snprintf(presentation.detail, sizeof(presentation.detail), "%s", detail ? detail : "UPDATING");
    }
    runtime_unlock();
}

void fixture_runtime_end_firmware_update(bool success, const char *detail) {
    runtime_lock();
    if (firmware_update_in_progress) {
        presentation.phase = FIXTURE_PRESENT_RESULT;
        presentation.result = success ? FIXTURE_RESULT_PASS : FIXTURE_RESULT_FAIL;
        presentation.progress_per_mille = success ? 1000u : presentation.progress_per_mille;
        snprintf(presentation.title, sizeof(presentation.title), "%s",
                 success ? "UPDATE VERIFIED" : "UPDATE REJECTED");
        snprintf(presentation.detail, sizeof(presentation.detail), "%s",
                 detail ? detail : (success ? "RESTARTING" : "IMAGE NOT INSTALLED"));
        snprintf(presentation.next, sizeof(presentation.next), "%s",
                 success ? "RESTARTING SAFELY" : "CURRENT FIRMWARE SAFE");
        firmware_update_in_progress = false;
    }
    runtime_unlock();
}

uint32_t fixture_runtime_trace_count(void) {
    runtime_lock();
    uint32_t count = fixture_trace_count(&fixture);
    runtime_unlock();
    return count;
}

bool fixture_runtime_trace_at(uint32_t index, fixture_trace_t *trace) {
    bool found = false;
    runtime_lock();
    const fixture_trace_t *source = fixture_trace_at(&fixture, index);
    if (source) {
        *trace = *source;
        found = true;
    }
    runtime_unlock();
    return found;
}
