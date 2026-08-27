#ifndef __DRV_MOTOR_H__
#define __DRV_MOTOR_H__

#include  "stdbool.h"


void motor_dev_init(void);
void motor_set_state(bool state);
int get_motor_state(void);

#endif