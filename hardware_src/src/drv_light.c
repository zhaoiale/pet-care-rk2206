#include "drv_light.h"
#include "drv_rgb_led.h"

static bool g_light_state = false;

void light_dev_init(void)
{
    /* rgb_led_init() already called in smart_home_thread,
     * no separate GPIO init needed. */
}

void light_set_state(bool state)
{
    if (state == g_light_state) return;
    if (state) {
        rgb_led_set(99, 31, 1);
    } else {
        rgb_led_off();
    }
    g_light_state = state;
}

int get_light_state(void)
{
    return g_light_state;
}
