#ifndef __DRV_HX711_H__
#define __DRV_HX711_H__

#include <stdbool.h>

// B0 = DOUT (data from HX711 → MCU input)
// B1 = PD_SCK (clock from MCU → HX711 output)
#define HX711_DOUT_PIN  8   // GPIO0_PB0
#define HX711_SCK_PIN   9   // GPIO0_PB1

void hx711_init(void);
int  hx711_read(void);              // raw 24-bit, -1 on timeout
void hx711_tare(int samples);       // zero calibration (avg of N)
float hx711_get_grams(void);        // calibrated weight
void hx711_set_calibration(float cal_factor);
bool hx711_is_ready(void);          // data available?

#endif
