#include "mpu6050.h"
#include <stdio.h>
#include <stdint.h>
#include "iot_i2c.h"
#include "iot_errno.h"
#include "los_task.h"

#define MPU6050_I2C_PORT EI2C0_M2

static uint8_t mpu6050_detected = 0;

static void mpu6050_write_reg(uint8_t reg, uint8_t data)
{
    uint8_t send_data[2] = {reg, data};
    IoTI2cWrite(MPU6050_I2C_PORT, MPU6050_SLAVE_ADDRESS, send_data, 2);
}

static void mpu6050_read_reg(uint8_t reg, uint8_t *buf, uint8_t length)
{
    uint8_t r = reg;
    IoTI2cWrite(MPU6050_I2C_PORT, MPU6050_SLAVE_ADDRESS, &r, 1);
    IoTI2cRead(MPU6050_I2C_PORT, MPU6050_SLAVE_ADDRESS, buf, length);
}

static int mpu6050_check_id(void)
{
    uint8_t id = 0;
    mpu6050_read_reg(MPU6050_RA_WHO_AM_I, &id, 1);
    if (id != 0x68) {
        printf("MPU6050 ID mismatch: got 0x%02X, expected 0x68\n", id);
        return 0;
    }
    return 1;
}

int mpu6050_init(void)
{
    // I2C bus already initialized by i2c_dev_init() at 400KHz
    LOS_Msleep(1000);

    mpu6050_write_reg(MPU6050_RA_PWR_MGMT_1, 0x80);  // reset
    LOS_Msleep(200);
    mpu6050_write_reg(MPU6050_RA_PWR_MGMT_1, 0x00);  // wake up
    mpu6050_write_reg(MPU6050_RA_INT_ENABLE, 0x00);   // all interrupts off
    mpu6050_write_reg(MPU6050_RA_USER_CTRL, 0x00);    // I2C master off
    mpu6050_write_reg(MPU6050_RA_FIFO_EN, 0x00);      // FIFO off
    mpu6050_write_reg(MPU6050_RA_INT_PIN_CFG, 0x80);
    mpu6050_write_reg(MPU6050_RA_MOT_THR, 0x03);      // motion threshold
    mpu6050_write_reg(MPU6050_RA_MOT_DUR, 0x14);      // 20ms
    mpu6050_write_reg(MPU6050_RA_CONFIG, 0x04);        // DLPF 42Hz
    mpu6050_write_reg(MPU6050_RA_ACCEL_CONFIG, 0x1C);  // +/-16g, high-pass on
    mpu6050_write_reg(MPU6050_RA_INT_PIN_CFG, 0x1C);
    mpu6050_write_reg(MPU6050_RA_INT_ENABLE, 0x40);

    mpu6050_detected = mpu6050_check_id();
    if (mpu6050_detected) {
        printf("MPU6050 init OK\n");
    }
    return mpu6050_detected ? 0 : -1;
}

void mpu6050_read_acc(short *acc_data)
{
    uint8_t buf[6];
    mpu6050_read_reg(MPU6050_ACC_OUT, buf, 6);
    acc_data[0] = (buf[0] << 8) | buf[1];  // X
    acc_data[1] = (buf[2] << 8) | buf[3];  // Y
    acc_data[2] = (buf[4] << 8) | buf[5];  // Z
}
