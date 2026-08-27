#include "drv_motor.h"
#include "iot_pwm.h"

static bool g_motor_state = false;


#define MOTOR_PWM_HANDLE EPWMDEV_PWM6_M0

/***************************************************************
* 函数名称: motor_dev_init
* 说    明: 电机初始化
* 参    数: 无
* 返 回 值: 无
***************************************************************/
void motor_dev_init(void)
{
    IoTPwmInit(MOTOR_PWM_HANDLE);
}


/***************************************************************
* 函数名称: motor_set_pwm
* 说    明: 设置电机pwm占空比
* 参    数: unsigned int duty 占空比
* 返 回 值: 无
***************************************************************/
void motor_set_pwm(unsigned int duty)
{
    IoTPwmStart(MOTOR_PWM_HANDLE, duty, 1000);
}



/***************************************************************
* 函数名称: motor_set_state
* 说    明: 控制电机状态
* 参    数: bool state true：打开 false：关闭
* 返 回 值: 无
***************************************************************/
void motor_set_state(bool state)
{

    if (state == g_motor_state)
    {
        return;
    }

    if (state)
    {
        motor_set_pwm(20);
    }
    else
    {
        motor_set_pwm(1);
        IoTPwmStop(MOTOR_PWM_HANDLE);
    } 
    g_motor_state = state;
 
}

int get_motor_state(void)
{
    return g_motor_state;
}
