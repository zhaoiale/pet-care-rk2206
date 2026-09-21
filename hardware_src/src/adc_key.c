/*
 * Copyright (c) 2024 iSoftStone Education Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include <stdio.h>
#include "los_task.h"
#include "ohos_init.h"
#include "iot_adc.h"
#include "iot_errno.h"
#include "smart_home_event.h"
#include "adc_key.h"

/* 按键对应ADC通道 */
#define KEY_ADC_CHANNEL 7

/***************************************************************
* 函数名称: adc_dev_init
* 说    明: 初始化ADC
* 参    数: 无
* 返 回 值: 0为成功，反之为失败
***************************************************************/
static unsigned int adc_dev_init()
{
    unsigned int ret = 0;

    /* 初始化ADC */
    ret = IoTAdcInit(KEY_ADC_CHANNEL);

    if(ret != IOT_SUCCESS)
    {
        printf("%s, %s, %d: ADC Init fail\n", __FILE__, __func__, __LINE__);
    }

    return 0;
}

/***************************************************************
* 函数名称: Get_Voltage
* 说    明: 获取ADC电压值
* 参    数: 无
* 返 回 值: 电压值
***************************************************************/
static float adc_get_voltage()
{
    unsigned int ret = IOT_SUCCESS;
    unsigned int data = 0;

    /* 获取ADC值 */
    ret = IoTAdcGetVal(KEY_ADC_CHANNEL, &data);

    if (ret != IOT_SUCCESS)
    {
        printf("%s, %s, %d: ADC Read Fail\n", __FILE__, __func__, __LINE__);
        return 0.0;
    }

    return (float)(data * 3.3 / 1024.0);
}

#define KEY_RELEASED 0
#define KEY_PRESSED 1

/***************************************************************
* 函数名称: adc_key_thread
* 说    明: ADC采集循环任务
* 参    数: 无
* 返 回 值: 无
***************************************************************/
void adc_key_thread(uint32_t arg)
{
    float voltage;
    int pressed = KEY_RELEASED;
    /* 初始化adc设备 */
    adc_dev_init();

    event_info_t key_event={0};
    key_event.event = event_key_press;

    while (1)
    {
        // printf("***************Adc Example*************\r\n");
        /*获取电压值*/
        voltage = adc_get_voltage();
        // printf("vlt:%.3fV\n", voltage);

        if(voltage >3.2){
            // printf("no key\n");
            pressed = KEY_RELEASED;
            key_event.data.key_no = KEY_RELEASE;
        }else if ((voltage > 1.50) && (pressed == KEY_RELEASED)){
            // printf("LEFT\n");
            pressed = KEY_PRESSED;
            key_event.data.key_no = KEY_LEFT;
        }else if ((voltage > 1.0) && (pressed == KEY_RELEASED)){
            // printf("DOWN\n");
            pressed = KEY_PRESSED;
            key_event.data.key_no = KEY_DOWN;
        }else if ((voltage > 0.5) && (pressed == KEY_RELEASED)){
            // printf("RIGHT\n");
            pressed = KEY_PRESSED;  
            key_event.data.key_no = KEY_RIGHT;
        }else if ( (voltage > 0.0) && (pressed == KEY_RELEASED)){
            // printf("UP\n");
            pressed = KEY_PRESSED;
            key_event.data.key_no = KEY_UP;
        }

        if(key_event.data.key_no != KEY_RELEASE)
        {
            printf("==> send key event: %d\n",key_event.data.key_no);
            smart_home_event_send(&key_event);
            //只发送一次,避免长按按键重复发送
            key_event.data.key_no = KEY_RELEASE;
        }

        LOS_Msleep(100);
    }
}


/***************************************************************
* 函数名称: adc_example
* 说    明: 开机自启动调用函数
* 参    数: 无
* 返 回 值: 无
***************************************************************/
void adc_example()
{
    unsigned int thread_id;
    TSK_INIT_PARAM_S task = {0};
    unsigned int ret = LOS_OK;

    task.pfnTaskEntry = (TSK_ENTRY_FUNC)adc_key_thread;
    task.uwStackSize = 8192;
    task.pcName = "adc process";
    task.usTaskPrio = 24;
    ret = LOS_TaskCreate(&thread_id, &task);
    if (ret != LOS_OK)
    {
        printf("Falied to create task ret:0x%x\n", ret);
        return;
    }
}

// APP_FEATURE_INIT(adc_example);