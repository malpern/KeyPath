#include "fixture_board.h"

#include <stdint.h>

#include "driver/gpio.h"
#include "driver/ledc.h"
#include "fixture_runtime.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/task.h"
#include "sdkconfig.h"

#define FIXTURE_BUTTON GPIO_NUM_0
#if CONFIG_KEYPATH_FIXTURE_BOARD_REVISION == 1
#define FIXTURE_BUZZER GPIO_NUM_33
#else
#define FIXTURE_BUZZER GPIO_NUM_42
#endif

typedef struct {
    uint16_t frequency_hz;
    uint16_t duration_ms;
} tone_request_t;

static QueueHandle_t tone_queue;
static volatile bool button_enabled;

static void board_task(void *context) {
    (void)context;
    bool previous_pressed = false;
    while (true) {
        tone_request_t tone;
        if (xQueueReceive(tone_queue, &tone, pdMS_TO_TICKS(10)) == pdTRUE) {
#if CONFIG_KEYPATH_FIXTURE_SOUND
            ledc_set_freq(LEDC_LOW_SPEED_MODE, LEDC_TIMER_2, tone.frequency_hz);
            ledc_set_duty(LEDC_LOW_SPEED_MODE, LEDC_CHANNEL_2, 128u);
            ledc_update_duty(LEDC_LOW_SPEED_MODE, LEDC_CHANNEL_2);
            vTaskDelay(pdMS_TO_TICKS(tone.duration_ms));
            ledc_stop(LEDC_LOW_SPEED_MODE, LEDC_CHANNEL_2, 0u);
#endif
        }
        bool pressed = gpio_get_level(FIXTURE_BUTTON) == 0;
        if (button_enabled && pressed && !previous_pressed) {
            fixture_runtime_abort("physical button abort");
            fixture_board_tone(220u, 90u);
        }
        previous_pressed = pressed;
    }
}

void fixture_board_init(void) {
    gpio_config_t button = {
        .pin_bit_mask = 1ULL << FIXTURE_BUTTON,
        .mode = GPIO_MODE_INPUT,
        .pull_up_en = GPIO_PULLUP_ENABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };
    ESP_ERROR_CHECK(gpio_config(&button));
#if CONFIG_KEYPATH_FIXTURE_SOUND
    ledc_timer_config_t timer = {
        .speed_mode = LEDC_LOW_SPEED_MODE,
        .duty_resolution = LEDC_TIMER_8_BIT,
        .timer_num = LEDC_TIMER_2,
        .freq_hz = 880,
        .clk_cfg = LEDC_AUTO_CLK,
    };
    ledc_channel_config_t channel = {
        .gpio_num = FIXTURE_BUZZER,
        .speed_mode = LEDC_LOW_SPEED_MODE,
        .channel = LEDC_CHANNEL_2,
        .intr_type = LEDC_INTR_DISABLE,
        .timer_sel = LEDC_TIMER_2,
        .duty = 0,
        .hpoint = 0,
    };
    ESP_ERROR_CHECK(ledc_timer_config(&timer));
    ESP_ERROR_CHECK(ledc_channel_config(&channel));
#endif
    tone_queue = xQueueCreate(4u, sizeof(tone_request_t));
    configASSERT(tone_queue);
    configASSERT(xTaskCreatePinnedToCore(board_task, "fixture_board", 3072, NULL, 5, NULL, 0) == pdPASS);
}

void fixture_board_tone(unsigned int frequency_hz, unsigned int duration_ms) {
    if (!tone_queue || frequency_hz > UINT16_MAX || duration_ms > UINT16_MAX) return;
    tone_request_t request = {(uint16_t)frequency_hz, (uint16_t)duration_ms};
    xQueueSend(tone_queue, &request, 0u);
}

void fixture_board_update(bool armed_or_running) {
    button_enabled = armed_or_running;
}
