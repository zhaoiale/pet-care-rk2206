#ifndef __ANXIETY_ENGINE_H__
#define __ANXIETY_ENGINE_H__

#include <stdbool.h>

/*
 * 宠物情绪检测引擎 v4 — 马氏距离 + HRV + 自适应基线
 *
 * 核心改进:
 *   1. HRV 心率变异性分析 (Poincaré SD1/SD2 → 压力指数)
 *   2. 24h 分桶 EWMA 自适应基线 → 6 维 Z-score
 *   3. 马氏距离多维融合 (替代 v3 的线性加权)
 *   4. 安抚效果 ε-greedy 反馈
 *
 * 情绪分级:
 *   高兴   (0-15):  愉悦/放松
 *   平静   (16-35): 正常/安稳
 *   警觉   (36-60): 注意/轻度紧张
 *   焦虑   (61-100): 不安/需安抚
 */

typedef enum {
    EMOTION_HAPPY = 0,
    EMOTION_CALM,
    EMOTION_ALERT,
    EMOTION_ANXIOUS
} emotion_state_t;

typedef struct {
    double temperature;
    double humidity;
    double illumination;
    bool   body_detected;
    bool   sound_detected;
    int    hour_of_day;
    int    activity_level;
    int    heart_rate;
    int    spo2;
    float  body_temp;       /* MLX90614, -999 = N/A */
} pet_env_data_t;

typedef struct {
    int  anxiety_level;          /* 0-100, Mahalanobis→sigmoid */
    int  activity_level;         /* raw MPU6050 activity 0-100 */
    int  exceed_count;           /* dimensions with |Z| > 2.5 */
    emotion_state_t emotion;
    bool need_comfort;
    int  comfort_type;           /* 1=light 2=voice 3=noise, ε-greedy selected */
    float mahalanobis_d2;        /* D² for diag */
    float z_scores[6];           /* per-dim Z-score for explainability */
} anxiety_result_t;

void anxiety_engine_init(void);
void anxiety_engine_process(pet_env_data_t *env, anxiety_result_t *result);

/* Call after comfort execution to give feedback on effectiveness */
void anxiety_engine_feedback(int comfort_type, int anxiety_before);
void anxiety_engine_poll_feedback(void);

#endif
