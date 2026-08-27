#ifndef __VOICE_ADC_H__
#define __VOICE_ADC_H__

#include <stdint.h>
#include <stdbool.h>

#define VOICE_ADC_CHANNEL    4     /* RK2206 PC4 = ADC channel 4 */
#define VOICE_ADC_RB_SIZE    8000  /* ~1 second buffer at 8kHz */

int  voice_adc_init(void);
int  voice_adc_start(void);
void voice_adc_stop(void);
bool voice_adc_is_running(void);

int  voice_adc_available(void);
int  voice_adc_read(uint16_t *buf, int max_samples);
void voice_adc_flush(void);

#endif
