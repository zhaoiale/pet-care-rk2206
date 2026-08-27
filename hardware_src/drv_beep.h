#ifndef __DRV_BEEP_H__
#define __DRV_BEEP_H__

#include <stdbool.h>

void beep_dev_init(void);
void beep_set_state(bool state);
void beep_set_freq(unsigned int freq, unsigned int duty);

#endif
