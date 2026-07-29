#include <stdio.h>
#include <string.h>

#include "bsp/board_api.h"
#include "fixture_config.h"
#include "fixture_core.h"
#include "hardware/watchdog.h"
#include "http_server.h"
#include "lwip/apps/mdns.h"
#include "lwip/ip4_addr.h"
#include "lwip/netif.h"
#include "pico/cyw43_arch.h"
#include "pico/stdlib.h"
#include "tusb.h"
#include "usb_descriptors.h"

static fixture_t fixture;
static bool mdns_started;

static bool send_keyboard_report(uint8_t modifiers, const uint8_t keys[6], void *context) {
    (void)context;
    if (!tud_hid_ready()) return false;
    return tud_hid_keyboard_report(REPORT_ID_KEYBOARD, modifiers, keys);
}

void tud_hid_report_complete_cb(uint8_t instance, uint8_t const *report, uint16_t length) {
    (void)instance;
    (void)report;
    (void)length;
    fixture_note_transfer_complete(&fixture);
}

static bool wifi_is_connected(void) {
    return cyw43_tcpip_link_status(&cyw43_state, CYW43_ITF_STA) == CYW43_LINK_UP;
}

static void announce_fixture(void) {
    if (!netif_default) return;
    if (!mdns_started) {
        mdns_resp_init();
        if (mdns_resp_add_netif(netif_default, "keypath-hid-fixture") != ERR_OK) return;
        mdns_resp_add_service(netif_default, "KeyPath HID fixture", "_http",
                              DNSSD_PROTO_TCP, KEYPATH_FIXTURE_HTTP_PORT, NULL, NULL);
        mdns_started = true;
    }
    mdns_resp_announce(netif_default);
}

static void update_led(uint64_t now_ms, bool wifi_connected) {
    uint32_t phase = (uint32_t)(now_ms % 2000u);
    bool on = false;
    if (!wifi_connected) {
        on = phase < 50u || (phase >= 150u && phase < 200u);
    } else {
        switch (fixture.state) {
            case FIXTURE_ARMED: on = true; break;
            case FIXTURE_RUNNING: on = (phase % 200u) < 100u; break;
            case FIXTURE_COMPLETE: on = phase < 80u || (phase >= 180u && phase < 260u) ||
                                        (phase >= 360u && phase < 440u); break;
            case FIXTURE_ERROR: on = (phase % 120u) < 60u; break;
            case FIXTURE_LOADED: on = phase < 80u || (phase >= 180u && phase < 260u); break;
            default: on = phase < 80u; break;
        }
    }
    cyw43_arch_gpio_put(CYW43_WL_GPIO_LED_PIN, on ? 1 : 0);
}

int main(void) {
    board_init();
    fixture_init(&fixture);

    tusb_rhport_init_t usb = {
        .role = TUSB_ROLE_DEVICE,
        .speed = TUSB_SPEED_FULL,
    };
    if (!tud_rhport_init(BOARD_TUD_RHPORT, &usb)) return 1;
    board_init_after_tusb();

    if (cyw43_arch_init()) {
        fixture.state = FIXTURE_ERROR;
        snprintf(fixture.error, sizeof(fixture.error), "CYW43 initialization failed");
        while (true) {
            tud_task();
            fixture_poll(&fixture, time_us_64(), tud_mounted(), tud_hid_ready(),
                         send_keyboard_report, NULL);
        }
    }
    cyw43_arch_enable_sta_mode();
    cyw43_arch_wifi_connect_async(KEYPATH_WIFI_SSID, KEYPATH_WIFI_PASSWORD, CYW43_AUTH_WPA2_AES_PSK);
    if (!fixture_http_server_init(&fixture, KEYPATH_FIXTURE_TOKEN, KEYPATH_FIXTURE_HTTP_PORT)) {
        fixture.state = FIXTURE_ERROR;
        snprintf(fixture.error, sizeof(fixture.error), "HTTP server initialization failed");
    }
    watchdog_enable(8000u, true);

    uint64_t next_wifi_retry_ms = 15000u;
    bool previous_wifi = false;
    while (true) {
        uint64_t now_us = time_us_64();
        uint64_t now_ms = now_us / 1000u;
        tud_task();
        cyw43_arch_poll();
        bool connected = wifi_is_connected();
        if (connected != previous_wifi) {
            const char *address = "unassigned";
            if (connected && netif_default) address = ip4addr_ntoa(netif_ip4_addr(netif_default));
            fixture_http_set_network(connected, address);
            if (connected) announce_fixture();
            previous_wifi = connected;
        }
        if (!connected && now_ms >= next_wifi_retry_ms) {
            cyw43_arch_wifi_connect_async(KEYPATH_WIFI_SSID, KEYPATH_WIFI_PASSWORD, CYW43_AUTH_WPA2_AES_PSK);
            next_wifi_retry_ms = now_ms + 15000u;
        }
        fixture_poll(&fixture, now_us, tud_mounted(), tud_hid_ready(), send_keyboard_report, NULL);
        update_led(now_ms, connected);
        watchdog_update();
        tight_loop_contents();
    }
}
