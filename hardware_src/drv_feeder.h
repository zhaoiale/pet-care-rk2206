#ifndef __DRV_FEEDER_H__
#define __DRV_FEEDER_H__

#include <stdbool.h>

// 每圈所需毫秒数（默认300ms/圈，待实测标定：数10圈出粮→称重→调整）
#define FEEDER_MS_PER_REVOLUTION_DEFAULT  300.0f

// HX711离线时圈→克换算（待实测标定）
#define FEEDER_GRAMS_PER_REVOLUTION_FALLBACK  11.7f

// 低电平触发继电器: 电路串在 COM-NO, GPIO 低电平=吸合=电机转
void feeder_dev_init(unsigned int gpio);
void feeder_feed(unsigned int duration_ms);
void feeder_feed_revolutions(unsigned int revolutions);
void feeder_feed_seconds(unsigned int seconds);

// HX711闭环克数投喂：启动电机→每200ms读HX711→减量达标自动停，60s超时
// HX711离线时自动退化为按圈估算
void feeder_feed_grams(unsigned int target_grams);

void feeder_stop(void);
int  feeder_is_feeding(void);
void feeder_dev_deinit(void);

// 标定每圈所需毫秒数 (实测后调整)
void  feeder_set_ms_per_rev(float ms_per_rev);
float feeder_get_ms_per_rev(void);

// 读取HX711食盆当前重量(g)，未连接返回-1
float feeder_get_food_remaining(void);

#endif
