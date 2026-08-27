#ifndef __MAX30102_H__
#define __MAX30102_H__

#include <stdint.h>

#define MAX30102_SLAVE_ADDRESS  0x57

/* Register map */
#define MAX30102_INT_STATUS_1   0x00
#define MAX30102_INT_STATUS_2   0x01
#define MAX30102_INT_ENABLE_1   0x02
#define MAX30102_INT_ENABLE_2   0x03
#define MAX30102_FIFO_WR_PTR    0x04
#define MAX30102_OVF_COUNTER    0x05
#define MAX30102_FIFO_RD_PTR    0x06
#define MAX30102_FIFO_DATA      0x07
#define MAX30102_FIFO_CONFIG    0x08
#define MAX30102_MODE_CONFIG    0x09
#define MAX30102_SPO2_CONFIG    0x0A
#define MAX30102_LED1_PA        0x0C
#define MAX30102_LED2_PA        0x0D
#define MAX30102_LED3_PA        0x0E
#define MAX30102_MULTI_LED_CTRL1 0x11
#define MAX30102_MULTI_LED_CTRL2 0x12
#define MAX30102_TEMP_INTR      0x1F
#define MAX30102_TEMP_FRAC      0x20
#define MAX30102_TEMP_CONFIG    0x21
#define MAX30102_PART_ID        0xFF

int  max30102_init(void);
int  max30102_read_fifo(uint32_t *ir_data, uint32_t *red_data, uint8_t count);
void max30102_feed_raw(const uint32_t *ir, const uint32_t *red, int count);
int  max30102_get_heart_rate(float *hr, float *spo2);
int  max30102_get_ibi(float *ibi_out, int max_count);
uint8_t max30102_is_detected(void);

#endif
