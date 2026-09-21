#ifndef __MPU6050_H__
#define __MPU6050_H__

#define MPU6050_GYRO_OUT        0x43
#define MPU6050_ACC_OUT         0x3B
#define MPU6050_SLAVE_ADDRESS   0x68
#define MPU6050_ADDRESS_AD0_LOW 0x68
#define MPU6050_RA_CONFIG       0x1A
#define MPU6050_RA_ACCEL_CONFIG 0x1C
#define MPU6050_RA_FF_THR       0x1D
#define MPU6050_RA_FF_DUR       0x1E
#define MPU6050_RA_MOT_THR      0x1F
#define MPU6050_RA_MOT_DUR      0x20
#define MPU6050_RA_ZRMOT_THR    0x21
#define MPU6050_RA_ZRMOT_DUR    0x22
#define MPU6050_RA_FIFO_EN      0x23
#define MPU6050_RA_INT_PIN_CFG  0x37
#define MPU6050_RA_INT_ENABLE   0x38
#define MPU6050_RA_TEMP_OUT_H   0x41
#define MPU6050_RA_USER_CTRL    0x6A
#define MPU6050_RA_PWR_MGMT_1   0x6B
#define MPU6050_RA_WHO_AM_I     0x75

int  mpu6050_init(void);               // returns 0 on success
void mpu6050_read_acc(short *acc_data); // x,y,z raw

#endif
