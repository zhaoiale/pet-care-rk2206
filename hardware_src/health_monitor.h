#ifndef __HEALTH_MONITOR_H__
#define __HEALTH_MONITOR_H__

#include <stdint.h>

/* 物种与健康阈值 */
#define HEALTH_SPECIES_CAT      0
#define HEALTH_SPECIES_DOG      1

#define HR_DOG_MIN     60    /* 狗正常心率下限 bpm */
#define HR_DOG_MAX    140    /* 狗正常心率上限 bpm */
#define HR_CAT_MIN    140    /* 猫正常心率下限 bpm */
#define HR_CAT_MAX    220    /* 猫正常心率上限 bpm */

#define SPO2_WARN     94     /* 血氧低于此值预警 */
#define TEMP_ENV_WARN  30.0f /* 环境温度高于此值预警 */

/* 体温阈值 (MLX90614, ℃) */
#define BODY_TEMP_CAT_MIN   37.5f
#define BODY_TEMP_CAT_MAX   39.2f
#define BODY_TEMP_DOG_MIN   37.5f
#define BODY_TEMP_DOG_MAX   39.0f
#define BODY_TEMP_FEVER     39.5f  /* 发烧 */
#define BODY_TEMP_HYPO      37.0f  /* 低温 */

#define ACTIVITY_LETHARGY_MIN  10  /* 活动量低于10 → 萎靡预警 */

/* 单项扣分 */
#define SCORE_PENALTY_HR       15
#define SCORE_PENALTY_SPO2     20
#define SCORE_PENALTY_TEMP     10
#define SCORE_PENALTY_ACTIVITY 15
#define SCORE_PENALTY_COMBO    10  /* 两项以上同时告警额外扣分 */

void health_monitor_init(void);
void health_monitor_set_species(int species);
int  health_monitor_evaluate(float heart_rate, float spo2,
                              float temperature, float body_temp, int activity_level);
void health_monitor_get_alert(char *buf, int buf_size);

#endif
