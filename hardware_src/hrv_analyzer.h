#ifndef __HRV_ANALYZER_H__
#define __HRV_ANALYZER_H__

/*
 * HRV 心率变异性分析器
 *
 * 从 MAX30102 PPG 信号的峰间期 (IBI) 序列提取自主神经系统状态指标。
 * 采用 Poincaré 图 SD1/SD2 替代 FFT 频域分析, 适合 MCU。
 *
 * 输出指标:
 *   SDNN      — IBI 序列标准差 (ms), 总自主神经调节能力
 *   RMSSD     — 相邻 IBI 差值的 RMS (ms), 副交感神经活性
 *   pNN50     — 相邻 IBI 差 >50ms 的占比 (%), 副交感张力
 *   SD1       — Poincaré 短轴 (ms), 短程变异性
 *   SD2       — Poincaré 长轴 (ms), 长程变异性
 *   stress_index — SD2/SD1, >3 = 交感主导 = 压力/焦虑
 */

typedef struct {
    float sdnn;          /* IBI std dev (ms) */
    float rmssd;         /* sqrt(mean(squared diffs)) (ms) */
    float pnn50;         /* % of diffs > 50ms */
    float sd1;           /* Poincaré short axis (ms) */
    float sd2;           /* Poincaré long axis (ms) */
    float stress_index;  /* SD2/SD1, higher = more stress */
    int   ibi_count;     /* number of valid IBI samples used */
    int   valid;         /* 1 if enough data for reliable estimate */
} hrv_result_t;

void hrv_analyzer_init(void);
void hrv_analyzer_update(void);              /* fetch IBIs from MAX30102 */
void hrv_analyzer_get_result(hrv_result_t *out);

#endif
