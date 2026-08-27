#include "drv_body_induction.h"
#include "iot_gpio.h"

#define PIR_GPIO_ID GPIO0_PA3

void body_induction_dev_init(void)
{
    IoTGpioInit(PIR_GPIO_ID);
    IoTGpioSetDir(PIR_GPIO_ID, IOT_GPIO_DIR_IN);
}

void body_induction_get_state(bool *state)
{
    IotGpioValue val = IOT_GPIO_VALUE0;
    IoTGpioGetInputVal(PIR_GPIO_ID, &val);
    *state = (val == IOT_GPIO_VALUE1);
}
