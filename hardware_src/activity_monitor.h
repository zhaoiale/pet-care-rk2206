#ifndef __ACTIVITY_MONITOR_H__
#define __ACTIVITY_MONITOR_H__

// 用 MPU6050 加速度计替代 PIR 二元检测，实现连续活动量测量
void activity_monitor_init(void);
void activity_monitor_update(void);              // 每轮调用：读加速度计，更新窗口
int  activity_get_level(void);                   // 当前活动量 0-100
int  activity_get_window_hits(int threshold);    // 窗口内超过阈值的次数
void activity_reset(void);

#endif
