#include "health_monitor.h"
#include <stdio.h>
#include <string.h>
#include <stdbool.h>

static int g_health_species = HEALTH_SPECIES_DOG; /* 默认狗 */

/* 告警原因字符串，供外部读取 */
static char g_health_alert[64];

void health_monitor_init(void)
{
    g_health_species = HEALTH_SPECIES_DOG;
    g_health_alert[0] = '\0';
}

void health_monitor_set_species(int species)
{
    if (species == HEALTH_SPECIES_CAT || species == HEALTH_SPECIES_DOG) {
        g_health_species = species;
    }
}

int health_monitor_evaluate(float heart_rate, float spo2,
                             float temperature, float body_temp, int activity_level)
{
    int score = 100;
    bool hr_alert = false;
    bool spo2_alert = false;
    bool temp_alert = false;
    bool activity_alert = false;

    /* 心率判断 */
    if (heart_rate > 0.0f) {
        if (g_health_species == HEALTH_SPECIES_CAT) {
            if (heart_rate < HR_CAT_MIN || heart_rate > HR_CAT_MAX) {
                hr_alert = true;
            }
        } else {
            if (heart_rate < HR_DOG_MIN || heart_rate > HR_DOG_MAX) {
                hr_alert = true;
            }
        }
    }

    /* 血氧判断 */
    if (spo2 > 0.0f && spo2 < SPO2_WARN) {
        spo2_alert = true;
    }

    /* 体温判断 (优先 MLX90614, 否则回退环境温度) */
    if (body_temp > 30.0f) {
        /* 有体温数据 → 用体温阈值 */
        float bt_min, bt_max;
        if (g_health_species == HEALTH_SPECIES_CAT) {
            bt_min = BODY_TEMP_CAT_MIN;
            bt_max = BODY_TEMP_CAT_MAX;
        } else {
            bt_min = BODY_TEMP_DOG_MIN;
            bt_max = BODY_TEMP_DOG_MAX;
        }
        if (body_temp < bt_min || body_temp > bt_max) {
            temp_alert = true;
        }
    } else if (temperature > TEMP_ENV_WARN) {
        /* 无体温 → 回退环境温度 */
        temp_alert = true;
    }

    /* 活动量萎靡判断 */
    if (heart_rate > 0.0f && activity_level < ACTIVITY_LETHARGY_MIN) {
        activity_alert = true;
    }

    /* 扣分 */
    int alert_count = 0;
    if (hr_alert)      { score -= SCORE_PENALTY_HR;       alert_count++; }
    if (spo2_alert)    { score -= SCORE_PENALTY_SPO2;     alert_count++; }
    if (temp_alert)    { score -= SCORE_PENALTY_TEMP;     alert_count++; }
    if (activity_alert){ score -= SCORE_PENALTY_ACTIVITY; alert_count++; }
    if (alert_count >= 2) { score -= SCORE_PENALTY_COMBO; }

    if (score < 0)  score = 0;
    if (score > 100) score = 100;

    /* 组装告警字符串 */
    g_health_alert[0] = '\0';
    if (hr_alert)       strcat(g_health_alert, "HR ");
    if (spo2_alert)     strcat(g_health_alert, "SpO2 ");
    if (temp_alert)     strcat(g_health_alert, "Temp ");
    if (activity_alert) strcat(g_health_alert, "Activity ");
    if (g_health_alert[0] == '\0') {
        snprintf(g_health_alert, sizeof(g_health_alert), "Normal");
    }

    return score;
}

void health_monitor_get_alert(char *buf, int buf_size)
{
    if (buf != NULL && buf_size > 0) {
        strncpy(buf, g_health_alert, buf_size - 1);
        buf[buf_size - 1] = '\0';
    }
}
