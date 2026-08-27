#include "drv_beep.h"
#include "iot_pwm.h"

#define BEEP_PORT EPWMDEV_PWM5_M0

static unsigned int g_beep_freq = 1000;
static unsigned int g_beep_duty = 20;
static bool g_beep_on = false;

void beep_dev_init(void)
{
    IoTPwmInit(BEEP_PORT);
}

void beep_set_state(bool state)
{
    if (state == g_beep_on) return;

    if (state) {
        IoTPwmStart(BEEP_PORT, g_beep_duty, g_beep_freq);
    } else {
        IoTPwmStop(BEEP_PORT);
    }
    g_beep_on = state;
}

void beep_set_freq(unsigned int freq, unsigned int duty)
{
    g_beep_freq = freq;
    g_beep_duty = duty;
    if (g_beep_on) {
        IoTPwmStart(BEEP_PORT, duty, freq);
    }
}
