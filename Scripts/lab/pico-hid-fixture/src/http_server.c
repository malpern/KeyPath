#include "http_server.h"

#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "lwip/pbuf.h"
#include "lwip/tcp.h"
#include "pico/stdlib.h"

#define REQUEST_CAPACITY (96u * 1024u)
#define RESPONSE_CAPACITY 4096u

typedef struct {
    struct tcp_pcb *pcb;
    size_t length;
    size_t expected_length;
    bool headers_parsed;
    char request[REQUEST_CAPACITY + 1u];
} http_client_t;

static fixture_t *server_fixture;
static const char *server_token;
static bool network_connected;
static char network_address[48] = "unassigned";
static bool client_active;

static void close_client(http_client_t *client) {
    if (!client) return;
    if (client->pcb) {
        tcp_arg(client->pcb, NULL);
        tcp_recv(client->pcb, NULL);
        tcp_err(client->pcb, NULL);
        tcp_close(client->pcb);
    }
    client_active = false;
    free(client);
}

static const char *reason_phrase(int status) {
    switch (status) {
        case 200: return "OK";
        case 201: return "Created";
        case 400: return "Bad Request";
        case 401: return "Unauthorized";
        case 404: return "Not Found";
        case 409: return "Conflict";
        case 413: return "Payload Too Large";
        case 503: return "Service Unavailable";
        default: return "Error";
    }
}

static void reply(http_client_t *client, int status, const char *content_type, const char *body) {
    char response[RESPONSE_CAPACITY];
    size_t body_length = body ? strlen(body) : 0u;
    int count = snprintf(response, sizeof(response),
                         "HTTP/1.1 %d %s\r\n"
                         "Content-Type: %s\r\n"
                         "Content-Length: %zu\r\n"
                         "Cache-Control: no-store\r\n"
                         "Connection: close\r\n\r\n%s",
                         status, reason_phrase(status), content_type, body_length, body ? body : "");
    if (count > 0 && (size_t)count < sizeof(response)) {
        tcp_write(client->pcb, response, (u16_t)count, TCP_WRITE_FLAG_COPY);
        tcp_output(client->pcb);
    }
    close_client(client);
}

static void json_message(http_client_t *client, int status, bool ok, const char *message) {
    char body[256];
    snprintf(body, sizeof(body), "{\"ok\":%s,\"message\":\"%s\"}\n",
             ok ? "true" : "false", message ? message : "");
    reply(client, status, "application/json", body);
}

static char *trim(char *value) {
    while (*value == ' ' || *value == '\t' || *value == '\r' || *value == '\n') ++value;
    char *end = value + strlen(value);
    while (end > value && (end[-1] == ' ' || end[-1] == '\t' || end[-1] == '\r' || end[-1] == '\n')) --end;
    *end = '\0';
    return value;
}

static bool authorized(const char *request) {
    const char *header = strstr(request, "Authorization: Bearer ");
    if (!header) return false;
    header += strlen("Authorization: Bearer ");
    const char *end = strstr(header, "\r\n");
    size_t token_length = strlen(server_token);
    return end && (size_t)(end - header) == token_length && memcmp(header, server_token, token_length) == 0;
}

static void status_response(http_client_t *client) {
    char body[1024];
    snprintf(body, sizeof(body),
             "{\"ok\":true,\"firmware\":\"%s\",\"state\":\"%s\","
             "\"runId\":\"%s\",\"scriptCRC32\":\"%08" PRIx32 "\","
             "\"eventCount\":%" PRIu32 ",\"repeatCount\":%" PRIu32 ","
             "\"currentRepeat\":%" PRIu32 ",\"reportsSubmitted\":%" PRIu64 ","
             "\"transfersCompleted\":%" PRIu64 ",\"lateReports\":%" PRIu64 ","
             "\"maximumLatenessUs\":%" PRId64 ",\"submittedCRC32\":\"%08" PRIx32 "\","
             "\"usbMounted\":%s,\"wifiConnected\":%s,\"address\":\"%s\","
             "\"error\":\"%s\"}\n",
             KEYPATH_FIXTURE_FIRMWARE_VERSION, fixture_state_name(server_fixture->state),
             server_fixture->run_id, server_fixture->script_crc32,
             server_fixture->event_count, server_fixture->repeat_count,
             server_fixture->current_repeat, server_fixture->reports_submitted,
             server_fixture->transfers_completed, server_fixture->late_reports,
             server_fixture->maximum_lateness_us, server_fixture->submitted_crc32,
             server_fixture->usb_mounted ? "true" : "false",
             network_connected ? "true" : "false", network_address, server_fixture->error);
    reply(client, 200, "application/json", body);
}

static unsigned int query_number(const char *path, const char *name, unsigned int fallback) {
    const char *query = strchr(path, '?');
    if (!query) return fallback;
    char needle[32];
    snprintf(needle, sizeof(needle), "%s=", name);
    const char *found = strstr(query + 1, needle);
    if (!found) return fallback;
    return (unsigned int)strtoul(found + strlen(needle), NULL, 10);
}

static void trace_response(http_client_t *client, const char *path) {
    unsigned int from = query_number(path, "from", 0u);
    unsigned int limit = query_number(path, "limit", 8u);
    if (limit > 8u) limit = 8u;
    uint32_t available = fixture_trace_count(server_fixture);
    char body[3072];
    size_t used = (size_t)snprintf(body, sizeof(body),
                                   "{\"runId\":\"%s\",\"from\":%u,\"available\":%" PRIu32 "}\n",
                                   server_fixture->run_id, from, available);
    for (unsigned int index = 0u; index < limit && from + index < available; ++index) {
        const fixture_trace_t *trace = fixture_trace_at(server_fixture, from + index);
        int count = snprintf(body + used, sizeof(body) - used,
                             "{\"sequence\":%" PRIu64 ",\"scheduledUs\":%" PRIu64 ","
                             "\"submittedUs\":%" PRIu64 ",\"latenessUs\":%" PRId64 ","
                             "\"modifiers\":%u,\"keys\":[%u,%u,%u,%u,%u,%u]}\n",
                             trace->sequence, trace->scheduled_us, trace->submitted_us,
                             trace->lateness_us, trace->modifiers, trace->keys[0], trace->keys[1],
                             trace->keys[2], trace->keys[3], trace->keys[4], trace->keys[5]);
        if (count < 0 || (size_t)count >= sizeof(body) - used) break;
        used += (size_t)count;
    }
    reply(client, 200, "application/x-ndjson", body);
}

static void dispatch(http_client_t *client) {
    char method[8] = {0}, path[160] = {0};
    if (sscanf(client->request, "%7s %159s", method, path) != 2) {
        json_message(client, 400, false, "invalid request line");
        return;
    }
    if (!authorized(client->request)) {
        json_message(client, 401, false, "bearer token required");
        return;
    }
    char *header_end = strstr(client->request, "\r\n\r\n");
    char *body = header_end ? header_end + 4 : client->request + client->length;

    if (strcmp(method, "GET") == 0 && strcmp(path, "/v1/status") == 0) {
        status_response(client);
    } else if (strcmp(method, "GET") == 0 && strncmp(path, "/v1/trace", 9u) == 0) {
        trace_response(client, path);
    } else if (strcmp(method, "POST") == 0 && strcmp(path, "/v1/script") == 0) {
        char error[128];
        size_t body_length = client->length - (size_t)(body - client->request);
        if (fixture_load_script(server_fixture, body, body_length, error, sizeof(error))) {
            json_message(client, 201, true, "script loaded and CRC verified");
        } else {
            json_message(client, 409, false, error);
        }
    } else if (strcmp(method, "POST") == 0 && strcmp(path, "/v1/arm") == 0) {
        char error[128];
        if (fixture_arm(server_fixture, trim(body), error, sizeof(error))) {
            json_message(client, 200, true, "fixture armed; safety release queued");
        } else {
            json_message(client, 409, false, error);
        }
    } else if (strcmp(method, "POST") == 0 && strcmp(path, "/v1/start") == 0) {
        char run_id[FIXTURE_MAX_RUN_ID + 1u] = {0};
        unsigned int delay_ms = 0u;
        char extra = '\0', error[128];
        if (sscanf(trim(body), "%48s %u %c", run_id, &delay_ms, &extra) != 2) {
            json_message(client, 400, false, "start body must contain run_id and delay_ms");
        } else if (fixture_start(server_fixture, run_id, delay_ms, time_us_64(), error, sizeof(error))) {
            json_message(client, 200, true, "locally timed script scheduled");
        } else {
            json_message(client, 409, false, error);
        }
    } else if (strcmp(method, "POST") == 0 && strcmp(path, "/v1/abort") == 0) {
        fixture_abort(server_fixture, "remote abort");
        json_message(client, 200, true, "aborted; all-keys-released report queued");
    } else {
        json_message(client, 404, false, "endpoint not found");
    }
}

static err_t receive_callback(void *argument, struct tcp_pcb *pcb, struct pbuf *packet, err_t error) {
    (void)error;
    http_client_t *client = argument;
    if (!packet) {
        close_client(client);
        return ERR_OK;
    }
    if (client->length + packet->tot_len > REQUEST_CAPACITY) {
        pbuf_free(packet);
        json_message(client, 413, false, "request exceeds fixture capacity");
        return ERR_OK;
    }
    pbuf_copy_partial(packet, client->request + client->length, packet->tot_len, 0u);
    client->length += packet->tot_len;
    client->request[client->length] = '\0';
    tcp_recved(pcb, packet->tot_len);
    pbuf_free(packet);

    if (!client->headers_parsed) {
        char *header_end = strstr(client->request, "\r\n\r\n");
        if (!header_end) return ERR_OK;
        client->headers_parsed = true;
        size_t header_length = (size_t)(header_end + 4 - client->request);
        size_t content_length = 0u;
        const char *length_header = strstr(client->request, "Content-Length:");
        if (length_header && length_header < header_end) {
            content_length = strtoul(length_header + strlen("Content-Length:"), NULL, 10);
        }
        client->expected_length = header_length + content_length;
        if (client->expected_length > REQUEST_CAPACITY) {
            json_message(client, 413, false, "declared body exceeds fixture capacity");
            return ERR_OK;
        }
    }
    if (client->headers_parsed && client->length >= client->expected_length) dispatch(client);
    return ERR_OK;
}

static void error_callback(void *argument, err_t error) {
    (void)error;
    http_client_t *client = argument;
    if (client) client->pcb = NULL;
    close_client(client);
}

static err_t accept_callback(void *argument, struct tcp_pcb *pcb, err_t error) {
    (void)argument;
    if (error != ERR_OK || !pcb || client_active) {
        if (pcb) tcp_abort(pcb);
        return ERR_ABRT;
    }
    http_client_t *client = calloc(1u, sizeof(*client));
    if (!client) {
        tcp_abort(pcb);
        return ERR_ABRT;
    }
    client_active = true;
    client->pcb = pcb;
    tcp_arg(pcb, client);
    tcp_recv(pcb, receive_callback);
    tcp_err(pcb, error_callback);
    return ERR_OK;
}

bool fixture_http_server_init(fixture_t *fixture, const char *bearer_token, uint16_t port) {
    server_fixture = fixture;
    server_token = bearer_token;
    struct tcp_pcb *server = tcp_new_ip_type(IPADDR_TYPE_ANY);
    if (!server) return false;
    if (tcp_bind(server, NULL, port) != ERR_OK) {
        tcp_close(server);
        return false;
    }
    server = tcp_listen_with_backlog(server, 1u);
    if (!server) return false;
    tcp_accept(server, accept_callback);
    return true;
}

void fixture_http_set_network(bool connected, const char *address) {
    network_connected = connected;
    snprintf(network_address, sizeof(network_address), "%s", address ? address : "unassigned");
}
