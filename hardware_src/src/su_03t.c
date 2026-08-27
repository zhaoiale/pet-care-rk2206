#include "su_03t.h"

#include "los_task.h"
#include "ohos_init.h"

#include "iot_errno.h"
#include "iot_uart.h"

#include "smart_home.h"
#include "smart_home_event.h"

#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>

// SU-03T connected to UART2 (B2=RX_M1, B3=TX_M1), NOT the debug UART1
#define SU03T_UART EUART2_M1

#define MSG_QUEUE_LENGTH                                16
#define BUFFER_LEN                                      50

/***************************************************************
* 函数名称: su_03t_thread
* 说    明: 语音模块处理线程
* 参    数: 无
* 返 回 值: 无
***************************************************************/
static void su_03t_thread(void *arg)
{
    printf("SU03T: thread started\n");
    IotUartAttribute attr;
    unsigned int ret = 0;

    printf("SU03T: deiniting UART1...\n");
    IoTUartDeinit(SU03T_UART);
    printf("SU03T: deinit done\n");

    attr.baudRate = 115200;
    attr.dataBits = IOT_UART_DATA_BIT_8;
    attr.pad = IOT_FLOW_CTRL_NONE;
    attr.parity = IOT_UART_PARITY_NONE;
    attr.rxBlock = IOT_UART_BLOCK_STATE_BLOCK;
    attr.stopBits = IOT_UART_STOP_BIT_1;
    attr.txBlock = IOT_UART_BLOCK_STATE_BLOCK;

    ret = IoTUartInit(SU03T_UART, &attr);
    if (ret != IOT_SUCCESS)
    {
        printf("SU03T: IoTUartInit(UART1) failed, ret=%d!\n", ret);
        return;
    }
    printf("SU03T: UART1 init OK, listening...\n");

    event_info_t event = {0};
    event.event = event_su03t;

    while(1)
    {
        uint8_t data[64] = {0};
        uint8_t rec_len = IoTUartRead(SU03T_UART, data, sizeof(data));

        if (rec_len != 0)
        {
            printf("SU03T: recv %d bytes: ", rec_len);
            for (int i = 0; i < rec_len; i++) printf("%02X ", data[i]);
            printf("\n");
            uint16_t command = data[0] << 8 | data[1];
            event.data.su03t_data = command;
            smart_home_event_send(&event);
        }

        LOS_Msleep(500);
    }
}

/***************************************************************
* 函数名称: su03t_send_double_msg
* 说    明: 发送double类型数据到语音模块
* 参    数: 无
* 返 回 值: 无
***************************************************************/
void su03t_send_double_msg(uint8_t index, double dat)
{
    uint8_t buf[50] = {0};
    uint8_t *buf_ptr = buf;
    uint8_t *u8_ptr = (uint8_t *)&dat;

    *buf_ptr = 0xAA;
    buf_ptr++;
    *buf_ptr = 0x55;
    buf_ptr++;
    *buf_ptr = index;
    buf_ptr++;

    for (uint8_t i = 0; i < sizeof(double); i++)
    {
        *buf_ptr = u8_ptr[i];
        buf_ptr++;
    }

    *buf_ptr = 0x55;
    buf_ptr++;
    *buf_ptr = 0xAA;

    IoTUartWrite(SU03T_UART, buf, 12);
}

/***************************************************************
* 函数名称: su03t_send_u8_msg
* 说    明: 发送int32_t类型数据到语音模块（触发预录语音播报）
* 参    数: index 语音索引, dat 参数值（4字节整数）
* 返 回 值: 无
***************************************************************/
void su03t_send_u8_msg(uint8_t index, int32_t dat)
{
    uint8_t buf[50] = {0};
    uint8_t *buf_ptr = buf;
    uint8_t *u8_ptr = (uint8_t *)&dat;

    *buf_ptr = 0xAA;
    buf_ptr++;
    *buf_ptr = 0x55;
    buf_ptr++;
    *buf_ptr = index;
    buf_ptr++;

    for (uint8_t i = 0; i < sizeof(int32_t); i++)
    {
        *buf_ptr = u8_ptr[i];
        buf_ptr++;
    }

    *buf_ptr = 0x55;
    buf_ptr++;
    *buf_ptr = 0xAA;

    IoTUartWrite(SU03T_UART, buf, 9);
}

/***************************************************************
* 函数名称: su03t_play_pet_sound
* 说    明: 人→宠物反向交互，播放猫/狗叫声
* 参    数: species "cat"/"dog", intent "hungry"/"happy"/...
* 返 回 值: 无
***************************************************************/
void su03t_play_pet_sound(const char *species, const char *intent)
{
    uint8_t index = SU03T_VOICE_PET_HAPPY_DOG; // default
    int is_dog = (species && species[0] == 'd');

    if (!intent) { intent = "happy"; }

    if (!strcmp(intent, "hungry") || !strcmp(intent, "hungry\n"))
        index = SU03T_VOICE_PET_HUNGRY;
    else if (!strcmp(intent, "happy") || !strcmp(intent, "happy\n"))
        index = is_dog ? SU03T_VOICE_PET_HAPPY_DOG : SU03T_VOICE_PET_HAPPY_CAT;
    else if (!strcmp(intent, "warning") || !strcmp(intent, "warning\n"))
        index = SU03T_VOICE_PET_WARNING;
    else if (!strcmp(intent, "lonely") || !strcmp(intent, "lonely\n"))
        index = SU03T_VOICE_PET_LONELY;
    else if (!strcmp(intent, "play") || !strcmp(intent, "play\n"))
        index = SU03T_VOICE_PET_PLAY;
    else if (!strcmp(intent, "calm") || !strcmp(intent, "calm\n"))
        index = SU03T_VOICE_PET_CALM;

    printf("[SU-03T] pet_sound: %s/%s -> voice idx %d\n",
           species ? species : "cat", intent, index);
    su03t_send_u8_msg(index, 0);
}

/***************************************************************
* 函数名称: su03t_init
* 说    明: 语音模块初始化
* 参    数: 无
* 返 回 值: 无
***************************************************************/
void su03t_init(void)
{
    printf("SU03T: init called, creating thread...\n");
    unsigned int thread_id;
    TSK_INIT_PARAM_S task = {0};
    unsigned int ret = LOS_OK;

    task.pfnTaskEntry = (TSK_ENTRY_FUNC)su_03t_thread;
    task.uwStackSize = 8192;
    task.pcName = "su-03t thread";
    task.usTaskPrio = 24;
    ret = LOS_TaskCreate(&thread_id, &task);
    if (ret != LOS_OK)
    {
        printf("SU03T: Failed to create task ret:0x%x\n", ret);
        return;
    }
    printf("SU03T: thread created OK, id=%u\n", thread_id);
}
