#ifndef __DRV_RGB_LED_H__
#define __DRV_RGB_LED_H__

#include <stdbool.h>

void rgb_led_init(void);
void rgb_led_set(unsigned char r, unsigned char g, unsigned char b);
void rgb_led_off(void);

#endif
