#include "fixture_http.h"

#include <inttypes.h>
#include <stdlib.h>
#include <string.h>

#include "esp_event.h"
#include "esp_check.h"
#include "esp_heap_caps.h"
#include "esp_http_server.h"
#include "esp_log.h"
#include "esp_netif.h"
#include "esp_wifi.h"
#include "fixture_config.h"
#include "fixture_runtime.h"
#include "freertos/FreeRTOS.h"
#include "mdns.h"
#include "nvs_flash.h"
#include "sdkconfig.h"

#define SCRIPT_CAPACITY (96u * 1024u)

static const char *TAG = "fixture_network";
static char *script_buffer;
static httpd_handle_t http_server;

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
    return httpd_resp_sendstr(request, body);
}

static esp_err_t require_auth(httpd_req_t *request) {
    if (authorized(request)) return ESP_OK;
    send_json(request, "401 Unauthorized", "{\"ok\":false,\"message\":\"bearer token required\"}\n");
    return ESP_FAIL;
}

static esp_err_t status_handler(httpd_req_t *request) {
    if (require_auth(request) != ESP_OK) return ESP_OK;
    fixture_runtime_snapshot_t snapshot;
    fixture_runtime_snapshot(&snapshot);
    bool wifi_connected;
    char address[48];
    fixture_runtime_network_snapshot(&wifi_connected, address, sizeof(address));
    char body[1280];
    snprintf(body, sizeof(body),
             "{\"ok\":true,\"firmware\":\"%s\",\"platform\":\"waveshare-esp32-s3-touch-lcd-1.69\","
             "\"state\":\"%s\",\"runId\":\"%s\",\"scriptCRC32\":\"%08" PRIx32 "\","
             "\"eventCount\":%" PRIu32 ",\"repeatCount\":%" PRIu32 ",\"currentRepeat\":%" PRIu32 ","
             "\"reportsSubmitted\":%" PRIu64 ",\"transfersCompleted\":%" PRIu64 ","
             "\"lateReports\":%" PRIu64 ",\"maximumLatenessUs\":%" PRId64 ","
             "\"submittedCRC32\":\"%08" PRIx32 "\",\"usbMounted\":%s,"
             "\"wifiConnected\":%s,\"address\":\"%s\",\"error\":\"%s\"}\n",
             KEYPATH_FIXTURE_FIRMWARE_VERSION, fixture_state_name(snapshot.ui.state), snapshot.run_id,
             snapshot.script_crc32, snapshot.ui.event_count, snapshot.ui.repeat_count,
             snapshot.ui.current_repeat, snapshot.ui.reports_submitted, snapshot.transfers_completed,
             snapshot.ui.late_reports, snapshot.ui.maximum_lateness_us, snapshot.submitted_crc32,
             snapshot.ui.usb_mounted ? "true" : "false", wifi_connected ? "true" : "false",
             address, snapshot.error);
    return send_json(request, "200 OK", body);
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
    config.max_uri_handlers = 6;
    config.stack_size = 8192;
    config.core_id = 0;
    config.task_priority = 4;
    ESP_RETURN_ON_ERROR(httpd_start(&http_server, &config), TAG, "HTTP server start failed");
    const httpd_uri_t handlers[] = {
        {.uri = "/v1/status", .method = HTTP_GET, .handler = status_handler},
        {.uri = "/v1/script", .method = HTTP_POST, .handler = script_handler},
        {.uri = "/v1/arm", .method = HTTP_POST, .handler = arm_handler},
        {.uri = "/v1/start", .method = HTTP_POST, .handler = start_handler},
        {.uri = "/v1/abort", .method = HTTP_POST, .handler = abort_handler},
        {.uri = "/v1/trace", .method = HTTP_GET, .handler = trace_handler},
    };
    for (size_t index = 0; index < sizeof(handlers) / sizeof(handlers[0]); ++index) {
        ESP_RETURN_ON_ERROR(httpd_register_uri_handler(http_server, &handlers[index]), TAG,
                            "URI registration failed");
    }
    return ESP_OK;
}

static void wifi_event(void *argument, esp_event_base_t base, int32_t id, void *data) {
    (void)argument;
    if (base == WIFI_EVENT && id == WIFI_EVENT_STA_START) {
        esp_wifi_connect();
    } else if (base == WIFI_EVENT && id == WIFI_EVENT_STA_DISCONNECTED) {
        fixture_runtime_set_network(false, "unassigned");
        esp_wifi_connect();
    } else if (base == IP_EVENT && id == IP_EVENT_STA_GOT_IP) {
        ip_event_got_ip_t *event = data;
        char address[16];
        snprintf(address, sizeof(address), IPSTR, IP2STR(&event->ip_info.ip));
        fixture_runtime_set_network(true, address);
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
    ESP_ERROR_CHECK(esp_event_handler_register(WIFI_EVENT, ESP_EVENT_ANY_ID, wifi_event, NULL));
    ESP_ERROR_CHECK(esp_event_handler_register(IP_EVENT, IP_EVENT_STA_GOT_IP, wifi_event, NULL));
    wifi_config_t wifi = {0};
    snprintf((char *)wifi.sta.ssid, sizeof(wifi.sta.ssid), "%s", KEYPATH_WIFI_SSID);
    snprintf((char *)wifi.sta.password, sizeof(wifi.sta.password), "%s", KEYPATH_WIFI_PASSWORD);
    wifi.sta.threshold.authmode = WIFI_AUTH_WPA2_PSK;
    wifi.sta.pmf_cfg.capable = true;
    wifi.sta.pmf_cfg.required = false;
    ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_STA));
    ESP_ERROR_CHECK(esp_wifi_set_config(WIFI_IF_STA, &wifi));

    ESP_ERROR_CHECK(mdns_init());
    ESP_ERROR_CHECK(mdns_hostname_set("keypath-hid-fixture"));
    ESP_ERROR_CHECK(mdns_instance_name_set("KeyPath HID fixture"));
    ESP_ERROR_CHECK(mdns_service_add("KeyPath HID fixture", "_http", "_tcp",
                                     CONFIG_KEYPATH_FIXTURE_HTTP_PORT, NULL, 0));
    return esp_wifi_start();
}
