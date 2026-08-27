#include "drv_sensors.h"
#include "iot_i2c.h"
#include "stdint.h"
#include "iot_errno.h"

#define I2C_HANDLE EI2C0_M2
#define SHT30_I2C_ADDRESS 0x44
#define BH1750_I2C_ADDRESS 0x23

/***************************************************************
 * 函数名称: sht30_init
 * 说    明: sht30初始化
 * 参    数: 无
 * 返 回 值: uint32_t IOT_SUCCESS表示成功 IOT_FAILURE表示失败
 ***************************************************************/
static uint32_t sht30_init(void)
{
    uint32_t ret = 0;
    uint8_t send_data[2] = {0x22, 0x36};
    uint32_t send_len = 2;

    ret = IoTI2cWrite(I2C_HANDLE, SHT30_I2C_ADDRESS, send_data, send_len); 
    if (ret != IOT_SUCCESS)
    {
        printf("I2c write failure.\r\n");
        return IOT_FAILURE;
    }

    return IOT_SUCCESS;
}

/***************************************************************
 * 函数名称: bh1750_init
 * 说    明: bh1750初始化
 * 参    数: 无
 * 返 回 值: uint32_t IOT_SUCCESS表示成功 IOT_FAILURE表示失败
 ***************************************************************/
static uint32_t bh1750_init(void)
{
    uint32_t ret = 0;
    uint8_t send_data[1] = {0x10};
    uint32_t send_len = 1;

    ret = IoTI2cWrite(I2C_HANDLE, BH1750_I2C_ADDRESS, send_data, send_len);
    if (ret != IOT_SUCCESS)
    {
        printf("I2c write failure.\r\n");
        return IOT_FAILURE;
    }

    return IOT_SUCCESS;
}

/***************************************************************
* 函数名称: sht30_calc_RH
* 说    明: 湿度计算
* 参    数: u16sRH：读取到的湿度原始数据
* 返 回 值: 计算后的湿度数据
***************************************************************/
static float sht30_calc_RH(uint16_t u16sRH)
{
    float humidityRH = 0;

    /*clear bits [1..0] (status bits)*/
    u16sRH &= ~0x0003;
    /*calculate relative humidity [%RH]*/
    /*RH = rawValue / (2^16-1) * 10*/
    humidityRH = (100 * (float)u16sRH / 65535);

    return humidityRH;
}

/***************************************************************
* 函数名称: sht30_calc_temperature
* 说    明: 温度计算
* 参    数: u16sT：读取到的温度原始数据
* 返 回 值: 计算后的温度数据
***************************************************************/
static float sht30_calc_temperature(uint16_t u16sT)
{
    float temperature = 0;

    /*clear bits [1..0] (status bits)*/
    u16sT &= ~0x0003;
    /*calculate temperature [℃]*/
    /*T = -45 + 175 * rawValue / (2^16-1)*/
    temperature = (175 * (float)u16sT / 65535 - 45);

    return temperature;
}

/***************************************************************
* 函数名称: sht30_check_crc
* 说    明: 检查数据正确性
* 参    数: data：读取到的数据
            nbrOfBytes：需要校验的数量
            checksum：读取到的校对比验值
* 返 回 值: 校验结果，0-成功 1-失败
***************************************************************/
static uint8_t sht30_check_crc(uint8_t *data, uint8_t nbrOfBytes, uint8_t checksum)
{
    uint8_t crc = 0xFF;
    uint8_t bit = 0;
    uint8_t byteCtr ;
    const int16_t POLYNOMIAL = 0x131;

    /*calculates 8-Bit checksum with given polynomial*/
    for(byteCtr = 0; byteCtr < nbrOfBytes; ++byteCtr)
    {
        crc ^= (data[byteCtr]);
        for ( bit = 8; bit > 0; --bit)
        {
            if (crc & 0x80) crc = (crc << 1) ^ POLYNOMIAL;
            else crc = (crc << 1);
        }
    }

    if(crc != checksum)
        return 1;
    else
        return 0;
}

/***************************************************************
* 函数名称: sht30_read_data
* 说    明: 读取温度、湿度
* 参    数: temp,humi：读取到的数据,通过指针返回 
* 返 回 值: 无
***************************************************************/
void sht30_read_data(double *temp, double *humi)
{
    /*checksum verification*/
    uint8_t data[3];
    uint16_t tmp;
    uint8_t rc;
    /*byte 0,1 is temperature byte 4,5 is humidity*/
    uint8_t SHT30_Data_Buffer[6];
    memset(SHT30_Data_Buffer, 0, 6);
    uint8_t send_data[2] = {0xE0, 0x00};

    /* Default to safe values in case I2C/CRC fails */
    *temp = 25.0;
    *humi = 50.0;

    uint32_t send_len = 2;
    IoTI2cWrite(I2C_HANDLE, SHT30_I2C_ADDRESS, send_data, send_len);

    uint32_t receive_len = 6;
    IoTI2cRead(I2C_HANDLE, SHT30_I2C_ADDRESS, SHT30_Data_Buffer, receive_len);

    /*check temperature*/
    data[0] = SHT30_Data_Buffer[0];
    data[1] = SHT30_Data_Buffer[1];
    data[2] = SHT30_Data_Buffer[2];
    rc = sht30_check_crc(data, 2, data[2]);
    if(!rc)
    {
        tmp = ((uint16_t)data[0] << 8) | data[1];
        *temp = sht30_calc_temperature(tmp);
    }

    /*check humidity*/
    data[0] = SHT30_Data_Buffer[3];
    data[1] = SHT30_Data_Buffer[4];
    data[2] = SHT30_Data_Buffer[5];
    rc = sht30_check_crc(data, 2, data[2]);
    if(!rc)
    {
        tmp = ((uint16_t)data[0] << 8) | data[1];
        *humi = sht30_calc_RH(tmp);
    }
}

/***************************************************************
* 函数名称: bh1750_read_data
* 说    明: 读取光照强度
* 参    数: dat：读取到的数据
* 返 回 值: 无
***************************************************************/
void bh1750_read_data(double *dat)
{
    uint8_t send_data[1] = {0x10};
    uint32_t send_len = 1;

    IoTI2cWrite(I2C_HANDLE, BH1750_I2C_ADDRESS, send_data, send_len); 

    uint8_t recv_data[2] = {0};
    uint32_t receive_len = 2;   

    IoTI2cRead(I2C_HANDLE, BH1750_I2C_ADDRESS, recv_data, receive_len);
    *dat = (float)(((recv_data[0] << 8) + recv_data[1]) / 1.2);
}

/***************************************************************
* 函数名称: i2c_dev_init
* 说    明: i2c设备初始化
* 参    数: 无
* 返 回 值: 无
***************************************************************/
void i2c_dev_init(void)
{
    IoTI2cInit(I2C_HANDLE, EI2C_FRE_400K);
    sht30_init();
    bh1750_init();
}

