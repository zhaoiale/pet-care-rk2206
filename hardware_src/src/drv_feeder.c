#include "drv_feeder.h"
#include "drv_hx711.h"
#include "iot_gpio.h"
#include "cmsis_os2.h"
#include <stdio.h>
#include <math.h>

static unsigned int g_feeder_gpio = 0;
static int g_is_feeding = 0;
static float g_ms_per_revolution = FEEDER_MS_PER_REVOLUTION_DEFAULT;

void feeder_dev_init(unsigned int gpio)
{
    g_feeder_gpio = gpio;
    int ret = IoTGpioInit(gpio);
    printf("[FEEDER] init gpio=%d ret=%d\n", gpio, ret);
    IoTGpioSetDir(gpio, IOT_GPIO_DIR_OUT);
    IoTGpioSetOutputVal(gpio, IOT_GPIO_VALUE1);
    printf("[FEEDER] gpio=%d set to HIGH (relay off)\n", gpio);
}

void feeder_feed(unsigned int duration_ms)
{
    if (g_is_feeding) {
        printf("[FEEDER] already feeding, skip\n");
        return;
    }
    g_is_feeding = 1;

    printf("[FEEDER] gpio=%d -> LOW (relay ON)\n", g_feeder_gpio);
    IoTGpioSetOutputVal(g_feeder_gpio, IOT_GPIO_VALUE0);

    osDelay(duration_ms);

    printf("[FEEDER] gpio=%d -> HIGH (relay OFF)\n", g_feeder_gpio);
    IoTGpioSetOutputVal(g_feeder_gpio, IOT_GPIO_VALUE1);

    g_is_feeding = 0;
}

void feeder_stop(void)
{
    IoTGpioSetOutputVal(g_feeder_gpio, IOT_GPIO_VALUE1);
    g_is_feeding = 0;
}

int feeder_is_feeding(void)
{
    return g_is_feeding;
}

void feeder_feed_revolutions(unsigned int revolutions)
{
    unsigned int duration = (unsigned int)((float)revolutions * g_ms_per_revolution);
    printf("[FEEDER] feed %u rev -> %ums (%.1f ms/rev)\n",
           revolutions, duration, g_ms_per_revolution);
    feeder_feed(duration);
}

void feeder_feed_seconds(unsigned int seconds)
{
    unsigned int duration = seconds * 1000;
    printf("[FEEDER] feed %u seconds -> %ums\n", seconds, duration);
    feeder_feed(duration);
}

#define FEEDER_MIN_FEED_MS   3000   // minimum guaranteed feed time before HX711 check
#define FEEDER_MAX_HX711_ERR 3      // consecutive HX711 errors before fallback

void feeder_feed_grams(unsigned int target_grams)
{
    printf("[FEEDER] feed %ug requested\n", target_grams);

    // Quick probe: is HX711 reachable?
    int probe = hx711_read();
    if (probe == (int)0x80000000) {
        unsigned int revs = (unsigned int)((float)target_grams /
            FEEDER_GRAMS_PER_REVOLUTION_FALLBACK + 0.5f);
        if (revs < 1) revs = 1;
        printf("[FEEDER] HX711 offline, fallback: %ug -> %u rev\n", target_grams, revs);
        feeder_feed_revolutions(revs);
        return;
    }

    // HX711 present: force tare to baseline current hopper weight.
    // After tare, hx711_get_grams() reports cumulative weight DISPENSED
    // from the hopper (INCREASING as food leaves, abs diff from tare point).
    hx711_tare(10);

    if (g_is_feeding) {
        printf("[FEEDER] already feeding, skip\n");
        return;
    }
    g_is_feeding = 1;

    float start = hx711_get_grams();  // ~0 after fresh tare
    float target_weight = start + (float)target_grams;

    IoTGpioSetOutputVal(g_feeder_gpio, IOT_GPIO_VALUE0);
    printf("[FEEDER] gpio=%d -> LOW (relay ON), start=%.1fg target=%.1fg (+%ug)\n",
           g_feeder_gpio, start, target_weight, target_grams);

    int max_loops = 300;    // 300 * 200ms = 60s timeout
    int loop = 0;
    int hx711_errs = 0;     // consecutive HX711 read errors
    int min_loops = FEEDER_MIN_FEED_MS / 200;  // loops before HX711 target check

    while (loop < max_loops) {
        osDelay(200);
        loop++;

        float current = hx711_get_grams();
        if (current < 0) {
            hx711_errs++;
            if (hx711_errs >= FEEDER_MAX_HX711_ERR) {
                printf("[FEEDER] HX711 lost mid-feed at loop %d (%d errors)\n",
                       loop, hx711_errs);
                break;
            }
            continue;
        }
        hx711_errs = 0;  // reset on successful read

        if (loop % 5 == 0) {
            printf("[FEEDER] %5.1fs: %.1fg dispensed / target %.1fg\n",
                   loop * 0.2f, current, target_weight);
        }

        // Skip HX711 target check during minimum feed window
        // (relay EMI can cause false high readings in first seconds)
        if (loop < min_loops) continue;

        // After tare, grams INCREASES as food leaves hopper.
        // Require 2 consecutive above-target readings to reject EMI spikes.
        static int consecutive_above = 0;
        if (current >= target_weight) {
            consecutive_above++;
            if (consecutive_above >= 2) {
                printf("[FEEDER] target reached: %.1fg >= %.1fg (2x confirm)\n",
                       current, target_weight);
                break;
            }
        } else {
            consecutive_above = 0;
        }
    }

    if (loop >= max_loops) {
        printf("[FEEDER] timeout after 60s, stopped at loop %d\n", loop);
    }

    IoTGpioSetOutputVal(g_feeder_gpio, IOT_GPIO_VALUE1);
    printf("[FEEDER] gpio=%d -> HIGH (relay OFF)\n", g_feeder_gpio);
    g_is_feeding = 0;

    float end = hx711_get_grams();
    float actual = (end >= 0 && start >= 0) ? (end - start) : -1.0f;
    printf("[FEEDER] done: dispensed=%.1fg (%d loops)\n", actual, loop);
}

void feeder_set_ms_per_rev(float ms_per_rev)
{
    g_ms_per_revolution = ms_per_rev;
    printf("[FEEDER] ms/rev set to %.1f\n", ms_per_rev);
}

float feeder_get_ms_per_rev(void)
{
    return g_ms_per_revolution;
}

float feeder_get_food_remaining(void)
{
    return hx711_get_grams();
}

void feeder_dev_deinit(void)
{
    feeder_stop();
    IoTGpioDeinit(g_feeder_gpio);
}
