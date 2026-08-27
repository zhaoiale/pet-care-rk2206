#ifndef __ADC_KEY_H__
#define __ADC_KEY_H__

#define KEY_RELEASE 0x00
#define KEY_UP      0x01
#define KEY_DOWN    0x02
#define KEY_LEFT    0x04
#define KEY_RIGHT   0x08

/**
 * @brief 按键初始化
 * 
 */
void adc_key_thread(uint32_t arg);


#endif