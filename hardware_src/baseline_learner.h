#ifndef __BASELINE_LEARNER_H__
#define __BASELINE_LEARNER_H__

#include <stdbool.h>
#include <stdint.h>

/*
 * 自适应基线学习器
 *
 * 24 小时分桶 EWMA — 为每只宠物学习个性化、时变的行为基线。
 * 输出 6 维 Z-score 向量, 表示当前值偏离正常基线的标准差数。
 *
 * 维度:
 *   D_ACTIVITY  — MPU6050 活动量 (0-100)
 *   D_HEARTRATE — MAX30102 心率 (bpm)
 *   D_HRV       — HRV 压力指数 (0-10+)
 *   D_BARK      — 叫声密度 (窗口内计数)
 *   D_TEMP      — 体表温度 (°C)
 *   D_ENV       — 环境不适指数 (0-10)
 */

typedef enum {
    D_ACTIVITY = 0,
    D_HEARTRATE,
    D_HRV,
    D_BARK,
    D_TEMP,
    D_ENV,
    DIM_COUNT   /* = 6 */
} baseline_dim_t;

#define Z_VECTOR_SIZE  DIM_COUNT

typedef struct {
    float z[Z_VECTOR_SIZE];   /* Z-score per dimension */
    int   ready_dimensions;   /* how many dims have enough samples */
    bool  learning;           /* still in initial learning phase */
} baseline_z_t;

void baseline_learner_init(void);
void baseline_learner_update(int hour, float values[Z_VECTOR_SIZE], uint8_t valid_mask);
void baseline_learner_get_zscore(baseline_z_t *out);

/* Access to learned covariance matrix for Mahalanobis fusion */
int  baseline_get_covariance(float cov[Z_VECTOR_SIZE][Z_VECTOR_SIZE]);
bool baseline_is_ready(void);  /* enough data for Mahalanobis? */

/* Flash persistence — saves EWMA buckets + covariance, restores across reboot */
int  baseline_save_to_flash(void);
int  baseline_load_from_flash(void);

#endif
