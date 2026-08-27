#ifndef __DRV_MLX90614_H__
#define __DRV_MLX90614_H__

#include <stdbool.h>

/*
 * MLX90614 红外体温传感器驱动 (I2C, 0x5A)
 * 接线: VIN→3.3V  GND→GND  SDA→PA0  SCL→PA1
 */

int  mlx90614_init(void);
bool mlx90614_is_present(void);
float mlx90614_read_body_temp(void);  /* returns °C, or -999 on error */

#endif
