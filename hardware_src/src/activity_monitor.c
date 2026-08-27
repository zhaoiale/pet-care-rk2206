#include "activity_monitor.h"
#include "mpu6050.h"
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include "los_task.h"

#define ACT_WINDOW_SIZE   20
#define ACT_THRESHOLD_LOW  5
#define ACT_THRESHOLD_HIGH 30
#define ACT_HUMAN_MIN      8
#define ACT_HUMAN_MAX      80

static int act_history[ACT_WINDOW_SIZE];
static int act_idx = 0;
static int act_level = 0;
static int mpu6050_ok = 0;

#define ALPHA 0.4f
static float filtered_mag = 0;

/*
 * 静止基线校准:
 *   MPU6050 ±16g 量程, 1g ≈ 2048 LSB
 *   三轴合矢量静止时 = sqrt(gx² + gy² + gz²) ≈ 2048
 *   活动时矢量增大, 正常活动可到 3000-5000, 剧烈活动可达 6000+
 *
 *   将 [2048, 6000+] 映射到 [0, 100]:
 *     raw_level = (magnitude - 2048) / 30
 *      3000: (3000-2048)/30 = 31.7  (缓步)
 *      4000: (4000-2048)/30 = 65.1  (奔跑)
 *      5000: (5000-2048)/30 = 98.4  (剧烈)
 */

static float g_gravity_baseline = 2048.0f;  /* calibrated at init */
#define ACTIVITY_SCALE    30.0f

void activity_monitor_init(void)
{
    mpu6050_ok = (mpu6050_init() == 0);
    for (int i = 0; i < ACT_WINDOW_SIZE; i++) act_history[i] = 0;
    act_idx = 0;
    act_level = 0;

    /* Dynamic calibration: sample 100 readings to find resting baseline */
    if (mpu6050_ok) {
        float sum = 0;
        short acc[3];
        for (int i = 0; i < 100; i++) {
            mpu6050_read_acc(acc);
            float ax = (float)acc[0];
            float ay = (float)acc[1];
            float az = (float)acc[2];
            sum += sqrtf(ax * ax + ay * ay + az * az);
            LOS_Msleep(10);
        }
        g_gravity_baseline = sum / 100.0f;
        if (g_gravity_baseline < 1500.0f || g_gravity_baseline > 2500.0f) {
            g_gravity_baseline = 2048.0f;
            printf("[ACTIVITY] calibration out of range, using default 2048\n");
        }
    }
    filtered_mag = g_gravity_baseline;
    printf("[ACTIVITY] monitor init, MPU6050=%s, baseline=%.0f (calibrated), scale=%.0f\n",
           mpu6050_ok ? "OK" : "FAIL", g_gravity_baseline, ACTIVITY_SCALE);
}

void activity_monitor_update(void)
{
    if (!mpu6050_ok) {
        act_level = 0;
        return;
    }

    short acc[3];
    mpu6050_read_acc(acc);

    float ax = (float)acc[0];
    float ay = (float)acc[1];
    float az = (float)acc[2];
    float magnitude = sqrtf(ax * ax + ay * ay + az * az);

    filtered_mag = ALPHA * magnitude + (1.0f - ALPHA) * filtered_mag;

    int raw_level = (int)((filtered_mag - g_gravity_baseline) / ACTIVITY_SCALE);
    if (raw_level < 0) raw_level = 0;
    if (raw_level > 100) raw_level = 100;

    act_level = raw_level;
    act_history[act_idx] = act_level;
    act_idx = (act_idx + 1) % ACT_WINDOW_SIZE;

    static int diag = 0;
    if (++diag >= 20) {
        diag = 0;
        printf("[ACTIVITY] mag=%.0f filtered=%.0f level=%d\n",
               magnitude, filtered_mag, act_level);
    }
}

int activity_get_level(void)
{
    return act_level;
}

int activity_get_window_hits(int threshold)
{
    int hits = 0;
    for (int i = 0; i < ACT_WINDOW_SIZE; i++) {
        if (act_history[i] >= threshold) hits++;
    }
    return hits;
}

void activity_reset(void)
{
    for (int i = 0; i < ACT_WINDOW_SIZE; i++) act_history[i] = 0;
    act_level = 0;
}
