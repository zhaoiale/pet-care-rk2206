#include "hrv_analyzer.h"
#include "max30102.h"
#include <math.h>
#include <stdio.h>
#include <string.h>

/* We need ~60 IBI values for stable HRV (at 60-100bpm: ~1 minute of data) */
#define HRV_IBI_BUF_SIZE  64
#define HRV_MIN_IBI_COUNT 10   /* minimum IBIs for a valid estimate */

static float g_ibi[HRV_IBI_BUF_SIZE];
static int   g_ibi_cnt = 0;
static float g_last_stress = 0;

static hrv_result_t g_result;

void hrv_analyzer_init(void)
{
    memset(g_ibi, 0, sizeof(g_ibi));
    g_ibi_cnt = 0;
    g_last_stress = 0;
    memset(&g_result, 0, sizeof(g_result));
    printf("[HRV] analyzer init (Poincare SD1/SD2 method)\n");
}

void hrv_analyzer_update(void)
{
    float new_ibi[32];
    int n = max30102_get_ibi(new_ibi, 32);
    if (n == 0) return;

    /* Append to ring buffer */
    for (int i = 0; i < n; i++) {
        if (g_ibi_cnt < HRV_IBI_BUF_SIZE) {
            g_ibi[g_ibi_cnt++] = new_ibi[i];
        } else {
            /* shift left (drop oldest) */
            for (int j = 0; j < HRV_IBI_BUF_SIZE - 1; j++)
                g_ibi[j] = g_ibi[j + 1];
            g_ibi[HRV_IBI_BUF_SIZE - 1] = new_ibi[i];
        }
    }

    if (g_ibi_cnt < HRV_MIN_IBI_COUNT) {
        g_result.valid = 0;
        return;
    }
    g_result.valid = 1;
    g_result.ibi_count = g_ibi_cnt;

    /* ---- SDNN: standard deviation of IBI ---- */
    float sum = 0;
    for (int i = 0; i < g_ibi_cnt; i++) sum += g_ibi[i];
    float mean = sum / (float)g_ibi_cnt;

    float var = 0;
    for (int i = 0; i < g_ibi_cnt; i++) {
        float d = g_ibi[i] - mean;
        var += d * d;
    }
    var /= (float)g_ibi_cnt;
    g_result.sdnn = sqrtf(var);

    /* ---- RMSSD & pNN50 & SDSD ---- */
    float sum_sq_diff = 0;
    int nn50 = 0;
    for (int i = 1; i < g_ibi_cnt; i++) {
        float diff = g_ibi[i] - g_ibi[i - 1];
        sum_sq_diff += diff * diff;
        if (diff > 50.0f || diff < -50.0f) nn50++;
    }
    float sdsd_sq = sum_sq_diff / (float)(g_ibi_cnt - 1);
    g_result.rmssd = sqrtf(sdsd_sq);
    g_result.pnn50 = (float)nn50 / (float)(g_ibi_cnt - 1) * 100.0f;

    /* ---- Poincaré SD1 / SD2 ---- */
    /*
     * SD1 = sqrt(0.5 * SDSD²)  → short-term variability (parasympathetic)
     * SD2 = sqrt(2 * SDNN² - 0.5 * SDSD²)  → long-term variability
     *
     * Ref: Brennan et al. (2001), "Poincaré plot interpretation
     *      using a physiological model of HRV"
     */
    g_result.sd1 = sqrtf(0.5f * sdsd_sq);
    float sd2_sq = 2.0f * var - 0.5f * sdsd_sq;
    if (sd2_sq < 0) sd2_sq = 0;
    g_result.sd2 = sqrtf(sd2_sq);

    /* ---- Stress Index = SD2 / SD1 ---- */
    /*
     * Higher ratio → dominant sympathetic activity → stress/anxiety.
     * Typical range: 1.5 (relaxed) to 6.0+ (stressed).
     * Low-pass filter to avoid jitter.
     */
    if (g_result.sd1 > 0.01f) {
        float raw_stress = g_result.sd2 / g_result.sd1;
        if (g_last_stress > 0) {
            g_result.stress_index = 0.3f * raw_stress + 0.7f * g_last_stress;
        } else {
            g_result.stress_index = raw_stress;
        }
        g_last_stress = g_result.stress_index;
    } else {
        g_result.stress_index = g_last_stress;
    }

    /* Diag every 10 updates */
    static int diag = 0;
    if (++diag >= 10) {
        diag = 0;
        printf("[HRV] n=%d SDNN=%.1f RMSSD=%.1f pNN50=%.0f%% "
               "SD1=%.1f SD2=%.1f stressIdx=%.2f\n",
               g_ibi_cnt,
               g_result.sdnn, g_result.rmssd, g_result.pnn50,
               g_result.sd1, g_result.sd2,
               g_result.stress_index);
    }
}

void hrv_analyzer_get_result(hrv_result_t *out)
{
    *out = g_result;
}
