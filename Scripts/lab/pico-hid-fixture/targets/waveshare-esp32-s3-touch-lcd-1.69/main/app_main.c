#include "esp_log.h"
#include "esp_ota_ops.h"
#include "esp_system.h"

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#include "fixture_board.h"
#include "fixture_display.h"
#include "fixture_http.h"
#include "fixture_qemu_smoke.h"
#include "fixture_runtime.h"

static const char *TAG = "keypath_fixture";

static void validate_ota_boot(void *context) {
    (void)context;
    const esp_partition_t *running = esp_ota_get_running_partition();
    esp_ota_img_states_t state;
    if (esp_ota_get_state_partition(running, &state) != ESP_OK ||
        state != ESP_OTA_IMG_PENDING_VERIFY) {
        vTaskDelete(NULL);
        return;
    }

    ESP_LOGI(TAG, "new OTA image pending validation; waiting for control-plane health");
    for (unsigned int attempt = 0u; attempt < 600u; ++attempt) {
        fixture_runtime_snapshot_t snapshot;
        fixture_runtime_snapshot(&snapshot);
        if (snapshot.ui.wifi_connected && fixture_network_control_ready() &&
            fixture_display_is_healthy()) {
            ESP_ERROR_CHECK(esp_ota_mark_app_valid_cancel_rollback());
            ESP_LOGI(TAG, "OTA image marked valid after Wi-Fi control plane became healthy");
            vTaskDelete(NULL);
            return;
        }
        vTaskDelay(pdMS_TO_TICKS(100));
    }

    ESP_LOGE(TAG, "new OTA image failed its 60-second control-plane health window; rolling back");
    ESP_ERROR_CHECK(esp_ota_mark_app_invalid_rollback_and_reboot());
    esp_restart();
}

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
    configASSERT(xTaskCreatePinnedToCore(validate_ota_boot, "fixture_ota_validate", 3072,
                                         NULL, 3, NULL, 0) == pdPASS);
    ESP_LOGI(TAG, "KeyPath ESP32-S3 physical HID fixture ready");
}
