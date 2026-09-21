#include "drv_mlx90614.h"
#include "iot_i2c.h"
#include "iot_errno.h"
#include "los_task.h"
#include <stdio.h>
#include <stdint.h>

#define I2C_HANDLE        EI2C0_M2
#define HW691_ADDR        0x7F
#define HW691_REG_CMD     0x30
#define HW691_REG_DATA    0x10   /* 3 bytes: 0x10(MSB), 0x11, 0x12(LSB) */
#define HW691_CMD_ON      0x08
#define HW691_CMD_OFF     0x00
#define HW691_SCALE       16384.0f

static bool g_present = false;

int mlx90614_init(void)
{
    /* Reset: power off then on */
    uint8_t cmd[2];

    cmd[0] = HW691_REG_CMD;
    cmd[1] = HW691_CMD_OFF;
    uint32_t ret = IoTI2cWrite(I2C_HANDLE, HW691_ADDR, cmd, 2);
    if (ret != IOT_SUCCESS) {
        printf("MLX90614: NOT FOUND (I2C @ 0x7F)\n");
        g_present = false;
        return -1;
    }

    cmd[0] = HW691_REG_CMD;
    cmd[1] = HW691_CMD_ON;
    IoTI2cWrite(I2C_HANDLE, HW691_ADDR, cmd, 2);

    g_present = true;
    printf("MLX90614: OK (HW-691 temp sensor @ 0x7F)\n");
    return 0;
}

bool mlx90614_is_present(void)
{
    return g_present;
}

float mlx90614_read_body_temp(void)
{
    if (!g_present) return -999.0f;

    /* Retry up to 2 times in case of glitch reading */
    for (int attempt = 0; attempt < 2; attempt++) {
        uint8_t cmd[2] = {HW691_REG_CMD, HW691_CMD_ON};
        IoTI2cWrite(I2C_HANDLE, HW691_ADDR, cmd, 2);
        LOS_Msleep(50);

        /* Read 3 bytes from DATA register (0x10, 0x11, 0x12) */
        uint8_t buf[3] = {0};
        int ok = 1;
        for (int i = 0; i < 3; i++) {
            uint8_t reg = HW691_REG_DATA + i;
            if (IoTI2cWrite(I2C_HANDLE, HW691_ADDR, &reg, 1) != IOT_SUCCESS) {
                ok = 0; break;
            }
            uint8_t val = 0;
            if (IoTI2cRead(I2C_HANDLE, HW691_ADDR, &val, 1) != IOT_SUCCESS) {
                ok = 0; break;
            }
            buf[i] = val;
        }
        if (!ok) continue;

        int32_t raw = ((int32_t)buf[0] << 16) | ((int32_t)buf[1] << 8) | buf[2];
        if (raw & 0x00800000) raw |= 0xFF000000;

        float temp = (float)raw / HW691_SCALE;

        printf("MLX90614: raw=%06lX (%.1f C)\n", raw & 0xFFFFFF, temp);

        if (temp >= 25.0f && temp <= 50.0f) return temp;
    }
    return -999.0f;
}
