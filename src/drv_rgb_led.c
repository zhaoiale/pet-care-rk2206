#include "drv_rgb_led.h"
#include "iot_pwm.h"

#define LED_R_PORT EPWMDEV_PWM1_M1
#define LED_G_PORT EPWMDEV_PWM7_M1
#define LED_B_PORT EPWMDEV_PWM0_M1

static unsigned char g_led_r = 0;
static unsigned char g_led_g = 0;
static unsigned char g_led_b = 0;
static bool g_led_on = false;

void rgb_led_init(void)
{
    IoTPwmInit(LED_R_PORT);
    IoTPwmInit(LED_G_PORT);
    IoTPwmInit(LED_B_PORT);
}

void rgb_led_set(unsigned char r, unsigned char g, unsigned char b)
{
    g_led_r = r;
    g_led_g = g;
    g_led_b = b;

    IoTPwmStart(LED_R_PORT, r, 1000);
    IoTPwmStart(LED_G_PORT, g, 1000);
    IoTPwmStart(LED_B_PORT, b, 1000);

    g_led_on = true;
}

void rgb_led_off(void)
{
    IoTPwmStop(LED_R_PORT);
    IoTPwmStop(LED_G_PORT);
    IoTPwmStop(LED_B_PORT);
    g_led_on = false;
}
