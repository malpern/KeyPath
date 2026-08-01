#include "fixture_http.h"

#include <inttypes.h>
#include <stdlib.h>
#include <string.h>

#include "cJSON.h"
#include "esp_event.h"
#include "esp_check.h"
#include "esp_eap_client.h"
#include "esp_heap_caps.h"
#include "esp_http_server.h"
#include "esp_log.h"
#include "esp_netif.h"
#include "esp_ota_ops.h"
#include "esp_system.h"
#include "esp_timer.h"
#include "esp_wifi.h"
#include "fixture_config.h"
#include "fixture_board.h"
#include "fixture_display.h"
#include "fixture_runtime.h"
#include "fixture_wifi_model.h"
#include "freertos/FreeRTOS.h"
#include "mdns.h"
#include "mbedtls/md.h"
#include "mbedtls/sha256.h"
#include "nvs_flash.h"
#include "sdkconfig.h"

#define SCRIPT_CAPACITY (96u * 1024u)
#define OTA_CHUNK_SIZE 4096u
#define SHA256_SIZE 32u
#define SHA256_HEX_SIZE 64u

static const char *TAG = "fixture_network";
static char *script_buffer;
static httpd_handle_t http_server;
static fixture_wifi_model_t wifi_model;
static volatile bool control_plane_ready;
static uint32_t wifi_disconnect_count;
static uint32_t wifi_connect_count;
static uint32_t last_wifi_disconnect_reason;
static uint32_t http_server_start_count;
static uint32_t status_request_count;
static uint32_t status_response_count;
static uint32_t status_failure_count;
static uint32_t last_status_latency_us;
static uint32_t maximum_status_latency_us;
static bool enterprise_wifi_enabled;

typedef enum {
    WIFI_PROFILE_PERSONAL,
    WIFI_PROFILE_ENTERPRISE,
} wifi_profile_authentication_t;

typedef struct {
    const char *ssid;
    const char *username;
    const char *password;
    wifi_profile_authentication_t authentication;
} wifi_profile_t;

static const wifi_profile_t wifi_profiles[] = {
    /* Expected location order: home, Hacker Dojo, beach, phone hotspot. */
    {KEYPATH_WIFI_SSID_1, NULL, KEYPATH_WIFI_PASSWORD_1, WIFI_PROFILE_PERSONAL},
    {KEYPATH_HACKER_DOJO_SSID, KEYPATH_HACKER_DOJO_USERNAME,
     KEYPATH_HACKER_DOJO_PASSWORD, WIFI_PROFILE_ENTERPRISE},
    {KEYPATH_WIFI_SSID_4, NULL, KEYPATH_WIFI_PASSWORD_4, WIFI_PROFILE_PERSONAL},
    {KEYPATH_WIFI_SSID_3, NULL, KEYPATH_WIFI_PASSWORD_3, WIFI_PROFILE_PERSONAL},
};

static bool authorized(httpd_req_t *request) {
    char value[192];
    if (httpd_req_get_hdr_value_str(request, "Authorization", value, sizeof(value)) != ESP_OK) return false;
    static const char prefix[] = "Bearer ";
    return strncmp(value, prefix, sizeof(prefix) - 1u) == 0 &&
           strcmp(value + sizeof(prefix) - 1u, KEYPATH_FIXTURE_TOKEN) == 0;
}

static esp_err_t send_json(httpd_req_t *request, const char *status, const char *body) {
    httpd_resp_set_status(request, status);
    httpd_resp_set_type(request, "application/json");
    httpd_resp_set_hdr(request, "Cache-Control", "no-store");
    httpd_resp_set_hdr(request, "Connection", "close");
    return httpd_resp_sendstr(request, body);
}

static esp_err_t require_auth(httpd_req_t *request) {
    if (authorized(request)) return ESP_OK;
    send_json(request, "401 Unauthorized", "{\"ok\":false,\"message\":\"bearer token required\"}\n");
    return ESP_FAIL;
}

static bool decode_hex(const char *hex, uint8_t *bytes, size_t byte_count) {
    if (!hex || strlen(hex) != byte_count * 2u) return false;
    for (size_t index = 0u; index < byte_count; ++index) {
        uint8_t value = 0u;
        for (size_t nibble = 0u; nibble < 2u; ++nibble) {
            char character = hex[index * 2u + nibble];
            uint8_t digit;
            if (character >= '0' && character <= '9') digit = (uint8_t)(character - '0');
            else if (character >= 'a' && character <= 'f') digit = (uint8_t)(character - 'a' + 10);
            else if (character >= 'A' && character <= 'F') digit = (uint8_t)(character - 'A' + 10);
            else return false;
            value = (uint8_t)((value << 4u) | digit);
        }
        bytes[index] = value;
    }
    return true;
}

static bool constant_time_equal(const uint8_t *left, const uint8_t *right, size_t length) {
    uint8_t difference = 0u;
    for (size_t index = 0u; index < length; ++index) difference |= left[index] ^ right[index];
    return difference == 0u;
}

static const char *ota_state_name(esp_ota_img_states_t state) {
    switch (state) {
        case ESP_OTA_IMG_NEW: return "new";
        case ESP_OTA_IMG_PENDING_VERIFY: return "pending-verify";
        case ESP_OTA_IMG_VALID: return "valid";
        case ESP_OTA_IMG_INVALID: return "invalid";
        case ESP_OTA_IMG_ABORTED: return "aborted";
        case ESP_OTA_IMG_UNDEFINED: return "undefined";
        default: return "unknown";
    }
}

static esp_err_t firmware_update_failure(httpd_req_t *request, const char *status,
                                         const char *message) {
    fixture_runtime_end_firmware_update(false, message);
    char body[224];
    snprintf(body, sizeof(body), "{\"ok\":false,\"message\":\"%s\"}\n", message);
    return send_json(request, status, body);
}

static esp_err_t firmware_handler(httpd_req_t *request) {
    if (require_auth(request) != ESP_OK) return ESP_OK;

    char error[128];
    if (!fixture_runtime_begin_firmware_update(error, sizeof(error))) {
        char body[192];
        snprintf(body, sizeof(body), "{\"ok\":false,\"message\":\"%s\"}\n", error);
        return send_json(request, "409 Conflict", body);
    }

    const esp_partition_t *partition = esp_ota_get_next_update_partition(NULL);
    if (!partition || request->content_len <= 0 || (size_t)request->content_len > partition->size) {
        return firmware_update_failure(request, "413 Payload Too Large",
                                       "image does not fit the inactive application slot");
    }

    char sha_hex[SHA256_HEX_SIZE + 1u];
    char hmac_hex[SHA256_HEX_SIZE + 1u];
    uint8_t expected_sha[SHA256_SIZE];
    uint8_t expected_hmac[SHA256_SIZE];
    if (httpd_req_get_hdr_value_str(request, "X-KeyPath-SHA256", sha_hex, sizeof(sha_hex)) != ESP_OK ||
        httpd_req_get_hdr_value_str(request, "X-KeyPath-HMAC-SHA256", hmac_hex, sizeof(hmac_hex)) != ESP_OK ||
        !decode_hex(sha_hex, expected_sha, sizeof(expected_sha)) ||
        !decode_hex(hmac_hex, expected_hmac, sizeof(expected_hmac))) {
        return firmware_update_failure(request, "400 Bad Request",
                                       "valid SHA-256 and HMAC-SHA256 headers are required");
    }

    uint8_t *chunk = heap_caps_malloc(OTA_CHUNK_SIZE, MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT);
    if (!chunk) return firmware_update_failure(request, "503 Service Unavailable",
                                                "not enough internal memory for update buffer");

    mbedtls_sha256_context sha;
    mbedtls_md_context_t hmac;
    mbedtls_sha256_init(&sha);
    mbedtls_md_init(&hmac);
    const mbedtls_md_info_t *sha256 = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
    esp_ota_handle_t ota_handle = 0u;
    bool ota_started = false;
    esp_err_t ota_result = ESP_OK;
    if (!sha256 || mbedtls_sha256_starts(&sha, 0) != 0 ||
        mbedtls_md_setup(&hmac, sha256, 1) != 0 ||
        mbedtls_md_hmac_starts(&hmac, (const unsigned char *)KEYPATH_FIXTURE_TOKEN,
                               strlen(KEYPATH_FIXTURE_TOKEN)) != 0) {
        ota_result = ESP_FAIL;
    } else {
        ota_result = esp_ota_begin(partition, (size_t)request->content_len, &ota_handle);
        ota_started = ota_result == ESP_OK;
    }

    size_t received = 0u;
    uint16_t last_progress = 0u;
    while (ota_result == ESP_OK && received < (size_t)request->content_len) {
        size_t remaining = (size_t)request->content_len - received;
        size_t wanted = remaining < OTA_CHUNK_SIZE ? remaining : OTA_CHUNK_SIZE;
        int count = httpd_req_recv(request, (char *)chunk, wanted);
        if (count == HTTPD_SOCK_ERR_TIMEOUT) continue;
        if (count <= 0) {
            ota_result = ESP_ERR_INVALID_RESPONSE;
            break;
        }
        if (mbedtls_sha256_update(&sha, chunk, (size_t)count) != 0 ||
            mbedtls_md_hmac_update(&hmac, chunk, (size_t)count) != 0) {
            ota_result = ESP_FAIL;
            break;
        }
        ota_result = esp_ota_write(ota_handle, chunk, (size_t)count);
        received += (size_t)count;
        uint16_t progress = (uint16_t)((received * 900u) / (size_t)request->content_len);
        if (progress >= last_progress + 10u || received == (size_t)request->content_len) {
            char detail[49];
            snprintf(detail, sizeof(detail), "RECEIVING IMAGE %u%%", progress / 10u);
            fixture_runtime_set_firmware_update_progress(progress, detail);
            last_progress = progress;
        }
    }

    uint8_t actual_sha[SHA256_SIZE] = {0};
    uint8_t actual_hmac[SHA256_SIZE] = {0};
    if (ota_result == ESP_OK &&
        (mbedtls_sha256_finish(&sha, actual_sha) != 0 ||
         mbedtls_md_hmac_finish(&hmac, actual_hmac) != 0)) {
        ota_result = ESP_FAIL;
    }
    mbedtls_sha256_free(&sha);
    mbedtls_md_free(&hmac);
    free(chunk);

    if (ota_result != ESP_OK || received != (size_t)request->content_len ||
        !constant_time_equal(actual_sha, expected_sha, sizeof(actual_sha)) ||
        !constant_time_equal(actual_hmac, expected_hmac, sizeof(actual_hmac))) {
        if (ota_started) esp_ota_abort(ota_handle);
        return firmware_update_failure(request, "400 Bad Request",
                                       "image transfer or cryptographic verification failed");
    }

    fixture_runtime_set_firmware_update_progress(950u, "VALIDATING APPLICATION");
    ota_result = esp_ota_end(ota_handle);
    ota_started = false;
    if (ota_result != ESP_OK) {
        return firmware_update_failure(request, "400 Bad Request",
                                       "ESP-IDF rejected the application image");
    }
    ota_result = esp_ota_set_boot_partition(partition);
    if (ota_result != ESP_OK) {
        return firmware_update_failure(request, "500 Internal Server Error",
                                       "could not select the verified application slot");
    }

    fixture_runtime_end_firmware_update(true, "RESTARTING");
    httpd_resp_set_hdr(request, "Connection", "close");
    char response_body[192];
    snprintf(response_body, sizeof(response_body),
             "{\"ok\":true,\"message\":\"image verified; restarting\","
             "\"rebooting\":true,\"targetSlot\":\"%s\"}\n", partition->label);
    esp_err_t response = send_json(request, "202 Accepted", response_body);
    vTaskDelay(pdMS_TO_TICKS(300));
    esp_restart();
    return response;
}

static esp_err_t status_handler(httpd_req_t *request) {
    uint64_t started_us = (uint64_t)esp_timer_get_time();
    ++status_request_count;
    if (require_auth(request) != ESP_OK) {
        ++status_failure_count;
        return ESP_OK;
    }
    fixture_runtime_snapshot_t snapshot;
    fixture_runtime_snapshot(&snapshot);
    fixture_display_health_t display_health;
    fixture_display_health_snapshot(&display_health);
    const esp_partition_t *running_partition = esp_ota_get_running_partition();
    esp_ota_img_states_t ota_state = ESP_OTA_IMG_UNDEFINED;
    const char *ota_state_value = esp_ota_get_state_partition(running_partition, &ota_state) == ESP_OK
                                      ? ota_state_name(ota_state) : "unavailable";
    bool update_ready = !snapshot.pending_release && !snapshot.firmware_update_in_progress &&
                        (snapshot.ui.state == FIXTURE_IDLE || snapshot.ui.state == FIXTURE_COMPLETE ||
                         snapshot.ui.state == FIXTURE_ABORTED || snapshot.ui.state == FIXTURE_ERROR);
    char body[3072];
    int body_length = snprintf(body, sizeof(body),
             "{\"ok\":true,\"firmware\":\"%s\",\"build\":\"%s\","
             "\"platform\":\"waveshare-esp32-s3-touch-lcd-1.69\","
             "\"state\":\"%s\",\"runId\":\"%s\",\"scriptCRC32\":\"%08" PRIx32 "\","
             "\"eventCount\":%" PRIu32 ",\"repeatCount\":%" PRIu32 ",\"currentRepeat\":%" PRIu32 ","
             "\"reportsSubmitted\":%" PRIu64 ",\"transfersCompleted\":%" PRIu64 ","
             "\"lateReports\":%" PRIu64 ",\"maximumLatenessUs\":%" PRId64 ","
             "\"submittedCRC32\":\"%08" PRIx32 "\",\"usbMounted\":%s,\"silent\":%s,"
             "\"displayHealthy\":%s,\"displayFrame\":%" PRIu64 ","
             "\"displayLastFrameMs\":%" PRIu64 ",\"splashEnabled\":%s,\"splashComplete\":%s,"
             "\"updateReady\":%s,\"updateInProgress\":%s,\"otaSlot\":\"%s\",\"otaState\":\"%s\","
             "\"wifiConnected\":%s,\"address\":\"%s\",\"network\":\"%s\",\"error\":\"%s\","
             "\"presentation\":{\"phase\":\"%s\",\"result\":\"%s\",\"brand\":\"%s\",\"progress\":%u,"
             "\"title\":\"%s\",\"detail\":\"%s\",\"next\":\"%s\","
             "\"reportsExpected\":%" PRIu32 ",\"reportsObserved\":%" PRIu32 ","
             "\"dropped\":%" PRIu32 ",\"duplicated\":%" PRIu32 ",\"repeated\":%" PRIu32 ","
             "\"latencyP95Us\":%" PRIu32 ",\"safeRelease\":%s},"
             "\"diagnostics\":{\"uptimeMs\":%" PRIu64 ",\"resetReason\":%d,"
             "\"freeHeapBytes\":%" PRIu32 ",\"minimumFreeHeapBytes\":%" PRIu32 ","
             "\"wifiConnects\":%" PRIu32 ",\"wifiDisconnects\":%" PRIu32 ","
             "\"lastWifiDisconnectReason\":%" PRIu32 ",\"httpServerStarts\":%" PRIu32 ","
             "\"statusRequests\":%" PRIu32 ",\"statusResponses\":%" PRIu32 ","
             "\"statusFailures\":%" PRIu32 ",\"lastStatusLatencyUs\":%" PRIu32 ","
             "\"maximumStatusLatencyUs\":%" PRIu32 "}}\n",
             KEYPATH_FIXTURE_FIRMWARE_VERSION, KEYPATH_FIXTURE_BUILD_ID,
             fixture_state_name(snapshot.ui.state), snapshot.run_id,
             snapshot.script_crc32, snapshot.ui.event_count, snapshot.ui.repeat_count,
             snapshot.ui.current_repeat, snapshot.ui.reports_submitted, snapshot.transfers_completed,
             snapshot.ui.late_reports, snapshot.ui.maximum_lateness_us, snapshot.submitted_crc32,
             snapshot.ui.usb_mounted ? "true" : "false",
             fixture_board_is_silent() ? "true" : "false",
             fixture_display_is_healthy() ? "true" : "false", display_health.frame_sequence,
             display_health.last_frame_ms, display_health.splash_enabled ? "true" : "false",
             display_health.splash_complete ? "true" : "false", update_ready ? "true" : "false",
             snapshot.firmware_update_in_progress ? "true" : "false", running_partition->label,
             ota_state_value, snapshot.ui.wifi_connected ? "true" : "false",
             snapshot.network_address, snapshot.network_name, snapshot.error,
             fixture_presentation_phase_name(snapshot.presentation.phase),
             fixture_result_name(snapshot.presentation.result),
             fixture_presentation_brand_name(snapshot.presentation.brand),
             snapshot.presentation.progress_per_mille,
             snapshot.presentation.title, snapshot.presentation.detail, snapshot.presentation.next,
             snapshot.presentation.reports_expected, snapshot.presentation.reports_observed,
             snapshot.presentation.dropped, snapshot.presentation.duplicated, snapshot.presentation.repeated,
             snapshot.presentation.latency_p95_us, snapshot.presentation.safe_release ? "true" : "false",
             (uint64_t)(esp_timer_get_time() / 1000), (int)esp_reset_reason(),
             (uint32_t)esp_get_free_heap_size(), (uint32_t)esp_get_minimum_free_heap_size(),
             wifi_connect_count, wifi_disconnect_count, last_wifi_disconnect_reason,
             http_server_start_count, status_request_count, status_response_count,
             status_failure_count, last_status_latency_us, maximum_status_latency_us);
    if (body_length < 0 || (size_t)body_length >= sizeof(body)) {
        ++status_failure_count;
        return send_json(request, "500 Internal Server Error",
                         "{\"ok\":false,\"error\":\"status response overflow\"}\n");
    }
    esp_err_t result = send_json(request, "200 OK", body);
    uint64_t elapsed_us = (uint64_t)esp_timer_get_time() - started_us;
    last_status_latency_us = elapsed_us > UINT32_MAX ? UINT32_MAX : (uint32_t)elapsed_us;
    if (last_status_latency_us > maximum_status_latency_us) {
        maximum_status_latency_us = last_status_latency_us;
    }
    if (result == ESP_OK) ++status_response_count;
    else ++status_failure_count;
    return result;
}

static esp_err_t receive_body(httpd_req_t *request, size_t maximum, size_t *length) {
    if (request->content_len <= 0 || (size_t)request->content_len > maximum) return ESP_ERR_INVALID_SIZE;
    size_t received = 0u;
    while (received < (size_t)request->content_len) {
        int count = httpd_req_recv(request, script_buffer + received,
                                   (size_t)request->content_len - received);
        if (count == HTTPD_SOCK_ERR_TIMEOUT) continue;
        if (count <= 0) return ESP_FAIL;
        received += (size_t)count;
    }
    script_buffer[received] = '\0';
    *length = received;
    return ESP_OK;
}

static char *trim(char *value) {
    while (*value == ' ' || *value == '\t' || *value == '\r' || *value == '\n') ++value;
    char *end = value + strlen(value);
    while (end > value && (end[-1] == ' ' || end[-1] == '\t' || end[-1] == '\r' || end[-1] == '\n')) --end;
    *end = '\0';
    return value;
}

static esp_err_t script_handler(httpd_req_t *request) {
    if (require_auth(request) != ESP_OK) return ESP_OK;
    size_t length;
    esp_err_t result = receive_body(request, SCRIPT_CAPACITY, &length);
    if (result != ESP_OK) return send_json(request, "413 Payload Too Large",
                                           "{\"ok\":false,\"message\":\"script exceeds fixture capacity\"}\n");
    char error[128];
    if (!fixture_runtime_load(script_buffer, length, error, sizeof(error))) {
        char body[192];
        snprintf(body, sizeof(body), "{\"ok\":false,\"message\":\"%s\"}\n", error);
        return send_json(request, "409 Conflict", body);
    }
    return send_json(request, "201 Created",
                     "{\"ok\":true,\"message\":\"script loaded and CRC verified\"}\n");
}

static esp_err_t small_command(httpd_req_t *request, const char *operation) {
    if (require_auth(request) != ESP_OK) return ESP_OK;
    size_t length;
    esp_err_t result = receive_body(request, 127u, &length);
    if (result != ESP_OK) return send_json(request, "400 Bad Request",
                                           "{\"ok\":false,\"message\":\"invalid command body\"}\n");
    (void)length;
    char *body_value = trim(script_buffer);
    char error[128];
    bool ok = false;
    const char *success = NULL;
    if (strcmp(operation, "arm") == 0) {
        ok = fixture_runtime_arm(body_value, error, sizeof(error));
        success = "fixture armed; safety release queued";
    } else {
        char run_id[FIXTURE_MAX_RUN_ID + 1u] = {0};
        unsigned int delay_ms;
        char extra;
        if (sscanf(body_value, "%48s %u %c", run_id, &delay_ms, &extra) != 2) {
            return send_json(request, "400 Bad Request",
                             "{\"ok\":false,\"message\":\"start body must contain run_id and delay_ms\"}\n");
        }
        ok = fixture_runtime_start(run_id, delay_ms, error, sizeof(error));
        success = "locally timed script scheduled";
    }
    if (!ok) {
        char body[192];
        snprintf(body, sizeof(body), "{\"ok\":false,\"message\":\"%s\"}\n", error);
        return send_json(request, "409 Conflict", body);
    }
    char response[192];
    snprintf(response, sizeof(response), "{\"ok\":true,\"message\":\"%s\"}\n", success);
    return send_json(request, "200 OK", response);
}

static esp_err_t arm_handler(httpd_req_t *request) { return small_command(request, "arm"); }
static esp_err_t start_handler(httpd_req_t *request) { return small_command(request, "start"); }

static esp_err_t abort_handler(httpd_req_t *request) {
    if (require_auth(request) != ESP_OK) return ESP_OK;
    fixture_runtime_abort("remote abort");
    return send_json(request, "200 OK",
                     "{\"ok\":true,\"message\":\"aborted; all-keys-released report queued\"}\n");
}

static bool json_u32(cJSON *root, const char *name, uint32_t maximum, uint32_t *output) {
    cJSON *item = cJSON_GetObjectItemCaseSensitive(root, name);
    if (!item) return true;
    if (!cJSON_IsNumber(item) || item->valuedouble < 0.0 || item->valuedouble > maximum ||
        item->valuedouble != (double)(uint32_t)item->valuedouble) return false;
    *output = (uint32_t)item->valuedouble;
    return true;
}

static bool json_text(cJSON *root, const char *name, char *output, size_t capacity) {
    cJSON *item = cJSON_GetObjectItemCaseSensitive(root, name);
    if (!item) return true;
    if (!cJSON_IsString(item) || !fixture_presentation_text_valid(item->valuestring, capacity - 1u)) return false;
    snprintf(output, capacity, "%s", item->valuestring);
    return true;
}

static esp_err_t presentation_handler(httpd_req_t *request) {
    if (require_auth(request) != ESP_OK) return ESP_OK;
    size_t length;
    if (receive_body(request, 1023u, &length) != ESP_OK) {
        return send_json(request, "400 Bad Request", "{\"ok\":false,\"message\":\"invalid presentation body\"}\n");
    }
    cJSON *root = cJSON_ParseWithLength(script_buffer, length);
    fixture_presentation_t presentation;
    fixture_presentation_init(&presentation);
    cJSON *phase = root ? cJSON_GetObjectItemCaseSensitive(root, "phase") : NULL;
    cJSON *result = root ? cJSON_GetObjectItemCaseSensitive(root, "result") : NULL;
    cJSON *brand = root ? cJSON_GetObjectItemCaseSensitive(root, "brand") : NULL;
    uint32_t progress = 0u;
    cJSON *safe_release = root ? cJSON_GetObjectItemCaseSensitive(root, "safeRelease") : NULL;
    bool valid = root && cJSON_IsObject(root) && cJSON_IsString(phase) &&
                 fixture_presentation_parse_phase(phase->valuestring, &presentation.phase) &&
                 (!result || (cJSON_IsString(result) &&
                              fixture_presentation_parse_result(result->valuestring, &presentation.result))) &&
                 (!brand || (cJSON_IsString(brand) &&
                             fixture_presentation_parse_brand(brand->valuestring, &presentation.brand))) &&
                 json_u32(root, "progress", 1000u, &progress) &&
                 json_u32(root, "reportsExpected", UINT32_MAX, &presentation.reports_expected) &&
                 json_u32(root, "reportsObserved", UINT32_MAX, &presentation.reports_observed) &&
                 json_u32(root, "dropped", UINT32_MAX, &presentation.dropped) &&
                 json_u32(root, "duplicated", UINT32_MAX, &presentation.duplicated) &&
                 json_u32(root, "repeated", UINT32_MAX, &presentation.repeated) &&
                 json_u32(root, "latencyP95Us", UINT32_MAX, &presentation.latency_p95_us) &&
                 json_text(root, "title", presentation.title, sizeof(presentation.title)) &&
                 json_text(root, "detail", presentation.detail, sizeof(presentation.detail)) &&
                 json_text(root, "next", presentation.next, sizeof(presentation.next)) &&
                 (!safe_release || cJSON_IsBool(safe_release));
    if (valid) {
        presentation.progress_per_mille = (uint16_t)progress;
        presentation.safe_release = safe_release && cJSON_IsTrue(safe_release);
        fixture_runtime_set_presentation(&presentation);
    }
    cJSON_Delete(root);
    if (!valid) {
        return send_json(request, "400 Bad Request",
                         "{\"ok\":false,\"message\":\"invalid phase, result, brand, metric, or display text\"}\n");
    }
    return send_json(request, "200 OK", "{\"ok\":true,\"message\":\"presentation updated\"}\n");
}

static unsigned int query_number(httpd_req_t *request, const char *name, unsigned int fallback) {
    char query[96], value[24];
    if (httpd_req_get_url_query_str(request, query, sizeof(query)) != ESP_OK) return fallback;
    if (httpd_query_key_value(query, name, value, sizeof(value)) != ESP_OK) return fallback;
    return (unsigned int)strtoul(value, NULL, 10);
}

static esp_err_t trace_handler(httpd_req_t *request) {
    if (require_auth(request) != ESP_OK) return ESP_OK;
    unsigned int from = query_number(request, "from", 0u);
    unsigned int limit = query_number(request, "limit", 8u);
    if (limit > 8u) limit = 8u;
    uint32_t available = fixture_runtime_trace_count();
    fixture_runtime_snapshot_t snapshot;
    fixture_runtime_snapshot(&snapshot);
    httpd_resp_set_type(request, "application/x-ndjson");
    httpd_resp_set_hdr(request, "Cache-Control", "no-store");
    char line[512];
    snprintf(line, sizeof(line), "{\"runId\":\"%s\",\"from\":%u,\"available\":%" PRIu32 "}\n",
             snapshot.run_id, from, available);
    httpd_resp_send_chunk(request, line, HTTPD_RESP_USE_STRLEN);
    for (unsigned int offset = 0u; offset < limit && from + offset < available; ++offset) {
        fixture_trace_t trace;
        if (!fixture_runtime_trace_at(from + offset, &trace)) break;
        snprintf(line, sizeof(line),
                 "{\"sequence\":%" PRIu64 ",\"scheduledUs\":%" PRIu64 ","
                 "\"submittedUs\":%" PRIu64 ",\"latenessUs\":%" PRId64 ","
                 "\"modifiers\":%u,\"keys\":[%u,%u,%u,%u,%u,%u]}\n",
                 trace.sequence, trace.scheduled_us, trace.submitted_us, trace.lateness_us,
                 trace.modifiers, trace.keys[0], trace.keys[1], trace.keys[2],
                 trace.keys[3], trace.keys[4], trace.keys[5]);
        httpd_resp_send_chunk(request, line, HTTPD_RESP_USE_STRLEN);
    }
    return httpd_resp_send_chunk(request, NULL, 0u);
}

static esp_err_t start_http_server(void) {
    if (http_server) return ESP_OK;
    httpd_config_t config = HTTPD_DEFAULT_CONFIG();
    config.server_port = CONFIG_KEYPATH_FIXTURE_HTTP_PORT;
    config.max_uri_handlers = 8;
    config.stack_size = 8192;
    config.core_id = 0;
    config.task_priority = 8;
    config.lru_purge_enable = true;
    config.recv_wait_timeout = 3;
    config.send_wait_timeout = 3;
    ESP_RETURN_ON_ERROR(httpd_start(&http_server, &config), TAG, "HTTP server start failed");
    ++http_server_start_count;
    const httpd_uri_t handlers[] = {
        {.uri = "/v1/status", .method = HTTP_GET, .handler = status_handler},
        {.uri = "/v1/script", .method = HTTP_POST, .handler = script_handler},
        {.uri = "/v1/arm", .method = HTTP_POST, .handler = arm_handler},
        {.uri = "/v1/start", .method = HTTP_POST, .handler = start_handler},
        {.uri = "/v1/abort", .method = HTTP_POST, .handler = abort_handler},
        {.uri = "/v1/trace", .method = HTTP_GET, .handler = trace_handler},
        {.uri = "/v1/presentation", .method = HTTP_POST, .handler = presentation_handler},
        {.uri = "/v1/firmware", .method = HTTP_POST, .handler = firmware_handler},
    };
    for (size_t index = 0; index < sizeof(handlers) / sizeof(handlers[0]); ++index) {
        ESP_RETURN_ON_ERROR(httpd_register_uri_handler(http_server, &handlers[index]), TAG,
                            "URI registration failed");
    }
    control_plane_ready = true;
    return ESP_OK;
}

static void stop_http_server(void) {
    control_plane_ready = false;
    if (!http_server) return;
    httpd_handle_t server = http_server;
    http_server = NULL;
    esp_err_t result = httpd_stop(server);
    if (result != ESP_OK) {
        ESP_LOGW(TAG, "HTTP server stop failed: %s", esp_err_to_name(result));
    }
}

bool fixture_network_control_ready(void) {
    return control_plane_ready;
}

static esp_err_t select_wifi_profile(size_t index) {
    wifi_model.profile_index = index % (sizeof(wifi_profiles) / sizeof(wifi_profiles[0]));
    const wifi_profile_t *profile = &wifi_profiles[wifi_model.profile_index];

    if (enterprise_wifi_enabled) {
        ESP_RETURN_ON_ERROR(esp_wifi_sta_enterprise_disable(), TAG,
                            "could not disable the previous enterprise profile");
        enterprise_wifi_enabled = false;
    }

    wifi_config_t wifi = {0};
    snprintf((char *)wifi.sta.ssid, sizeof(wifi.sta.ssid), "%s", profile->ssid);
    wifi.sta.pmf_cfg.capable = true;
    wifi.sta.pmf_cfg.required = false;
    if (profile->authentication == WIFI_PROFILE_ENTERPRISE) {
        wifi.sta.threshold.authmode = WIFI_AUTH_WPA2_ENTERPRISE;
    } else {
        snprintf((char *)wifi.sta.password, sizeof(wifi.sta.password), "%s", profile->password);
        wifi.sta.threshold.authmode = WIFI_AUTH_WPA2_PSK;
    }
    fixture_runtime_set_network_name(profile->ssid);
    ESP_LOGI(TAG, "selecting Wi-Fi profile %u", (unsigned int)(wifi_model.profile_index + 1u));
    ESP_RETURN_ON_ERROR(esp_wifi_set_config(WIFI_IF_STA, &wifi), TAG,
                        "could not configure the selected Wi-Fi profile");

    if (profile->authentication == WIFI_PROFILE_ENTERPRISE) {
        size_t username_length = strlen(profile->username);
        size_t password_length = strlen(profile->password);
        ESP_RETURN_ON_ERROR(
            esp_eap_client_set_identity((const unsigned char *)profile->username,
                                        (int)username_length),
            TAG, "could not configure enterprise identity");
        ESP_RETURN_ON_ERROR(
            esp_eap_client_set_username((const unsigned char *)profile->username,
                                        (int)username_length),
            TAG, "could not configure enterprise username");
        ESP_RETURN_ON_ERROR(
            esp_eap_client_set_password((const unsigned char *)profile->password,
                                        (int)password_length),
            TAG, "could not configure enterprise password");
        ESP_RETURN_ON_ERROR(esp_eap_client_set_eap_methods(ESP_EAP_TYPE_PEAP), TAG,
                            "could not select PEAP authentication");
        ESP_RETURN_ON_ERROR(esp_wifi_sta_enterprise_enable(), TAG,
                            "could not enable enterprise authentication");
        enterprise_wifi_enabled = true;
    }
    return ESP_OK;
}

static void wifi_event(void *argument, esp_event_base_t base, int32_t id, void *data) {
    (void)argument;
    if (base == WIFI_EVENT && id == WIFI_EVENT_STA_START) {
        esp_wifi_connect();
    } else if (base == WIFI_EVENT && id == WIFI_EVENT_STA_DISCONNECTED) {
        wifi_event_sta_disconnected_t *event = data;
        ++wifi_disconnect_count;
        last_wifi_disconnect_reason = event ? event->reason : 0u;
        fixture_runtime_set_network(false, "unassigned");
        stop_http_server();
        if (fixture_wifi_model_note_disconnect(&wifi_model,
                                               sizeof(wifi_profiles) / sizeof(wifi_profiles[0]),
                                               2u)) {
            ESP_ERROR_CHECK(select_wifi_profile(wifi_model.profile_index));
        }
        esp_wifi_connect();
    } else if (base == IP_EVENT && id == IP_EVENT_STA_GOT_IP) {
        ++wifi_connect_count;
        ip_event_got_ip_t *event = data;
        char address[16];
        snprintf(address, sizeof(address), IPSTR, IP2STR(&event->ip_info.ip));
        fixture_runtime_set_network(true, address);
        fixture_wifi_model_note_connected(&wifi_model);
        start_http_server();
    }
}

esp_err_t fixture_network_start(void) {
    script_buffer = heap_caps_malloc(SCRIPT_CAPACITY + 1u, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    if (!script_buffer) return ESP_ERR_NO_MEM;
    esp_err_t result = nvs_flash_init();
    if (result == ESP_ERR_NVS_NO_FREE_PAGES || result == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        result = nvs_flash_init();
    }
    ESP_RETURN_ON_ERROR(result, TAG, "NVS initialization failed");
    ESP_RETURN_ON_ERROR(esp_netif_init(), TAG, "network stack initialization failed");
    ESP_RETURN_ON_ERROR(esp_event_loop_create_default(), TAG, "event loop initialization failed");
    if (!esp_netif_create_default_wifi_sta()) return ESP_FAIL;

    wifi_init_config_t init = WIFI_INIT_CONFIG_DEFAULT();
    ESP_RETURN_ON_ERROR(esp_wifi_init(&init), TAG, "Wi-Fi initialization failed");
    fixture_wifi_model_init(&wifi_model);
    ESP_ERROR_CHECK(esp_event_handler_register(WIFI_EVENT, ESP_EVENT_ANY_ID, wifi_event, NULL));
    ESP_ERROR_CHECK(esp_event_handler_register(IP_EVENT, IP_EVENT_STA_GOT_IP, wifi_event, NULL));
    ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_STA));
    ESP_ERROR_CHECK(select_wifi_profile(0u));

    ESP_ERROR_CHECK(mdns_init());
    ESP_ERROR_CHECK(mdns_hostname_set("keypath-hid-fixture"));
    ESP_ERROR_CHECK(mdns_instance_name_set("KeyPath HID fixture"));
    ESP_ERROR_CHECK(mdns_service_add("KeyPath HID fixture", "_http", "_tcp",
                                     CONFIG_KEYPATH_FIXTURE_HTTP_PORT, NULL, 0));
    ESP_RETURN_ON_ERROR(esp_wifi_start(), TAG, "Wi-Fi start failed");
    return esp_wifi_set_ps(WIFI_PS_NONE);
}
