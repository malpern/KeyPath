#include "esp_log.h"

#include "fixture_board.h"
#include "fixture_display.h"
#include "fixture_http.h"
#include "fixture_qemu_smoke.h"
#include "fixture_runtime.h"

static const char *TAG = "keypath_fixture";

void app_main(void) {
#ifdef KEYPATH_QEMU_SMOKE
    fixture_qemu_smoke_run();
    return;
#endif
    fixture_runtime_init();
    fixture_board_init();
    ESP_ERROR_CHECK(fixture_runtime_start_usb());
    fixture_runtime_start_executor();
    fixture_display_start();
    ESP_ERROR_CHECK(fixture_network_start());
    ESP_LOGI(TAG, "KeyPath ESP32-S3 physical HID fixture ready");
}
