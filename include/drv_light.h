#ifndef _DRV_LIGHT_H__
#define _DRV_LIGHT_H__

#include  "stdbool.h"

void light_dev_init(void);

void light_set_state(bool state);

int get_light_state(void);


#endif