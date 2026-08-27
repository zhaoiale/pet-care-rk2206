#include "anxiety_engine.h"
#include "baseline_learner.h"
#include "hrv_analyzer.h"
#include "max30102.h"
#include <math.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <time.h>

#define SOUND_WINDOW       20
#define Z_THRESHOLD        2.5f
#define MAHA_K             50.0f   /* recalibrated for weighted dimensions */
#define COMFORT_ALPHA      0.1f
#define EPSILON_GREEDY     0.1f
#define TREND_WINDOW       10      /* samples for slope detection */
#define TREND_SLOPE_THRESH 1.5f    /* anxiety units/sample = sustained rise */

/* C. Trend detection state */
static float g_anxiety_hist[TREND_WINDOW];
static int   g_anxiety_hist_idx;

/*
 * Per-dimension importance weights for anxiety fusion.
 *
 * Physiological rationale:
 *   HRV stress index  — most direct physiological stress biomarker
 *   Heart rate        — strong arousal correlate
 *   Bark count        — behavioral indicator of distress
 *   Activity level    — anomalous movement (too high or too low)
 *   Temperature       — mild indicator (fever, environmental stress)
 *   Env discomfort    — indirect/contextual factor
 */
#define W_HRV        2.5f
#define W_HEARTRATE  2.0f
#define W_BARK       1.5f
#define W_ACTIVITY   1.2f
#define W_TEMP       0.8f
#define W_ENV        0.6f

static const float g_dim_weight[Z_VECTOR_SIZE] = {
    W_ACTIVITY, W_HEARTRATE, W_HRV, W_BARK, W_TEMP, W_ENV
};

static int  prev_anxiety = 0;

static bool sound_hist[SOUND_WINDOW];
static int  sound_pos = 0;

static int bark_count(void)
{
    int c = 0;
    for (int i = 0; i < SOUND_WINDOW; i++)
        if (sound_hist[i]) c++;
    return c;
}

static float env_discomfort(double humidity, double illumination)
{
    float discomfort = 0;

    /* Humidity: comfort zone 30-80% */
    if (humidity < 25.0)      discomfort += 5.0f;
    else if (humidity < 35.0) discomfort += (35.0f - (float)humidity) * 0.5f;
    else if (humidity > 85.0) discomfort += 5.0f;
    else if (humidity > 75.0) discomfort += ((float)humidity - 75.0f) * 0.5f;

    /* Illumination: comfort zone 10-1000 Lux */
    if (illumination < 5.0)      discomfort += 5.0f;
    else if (illumination < 10.0) discomfort += (10.0f - (float)illumination) * 1.0f;
    else if (illumination > 3000.0) discomfort += 5.0f;
    else if (illumination > 1000.0) discomfort += ((float)illumination - 1000.0f) * 0.0025f;

    return (discomfort > 10.0f) ? 10.0f : discomfort;
}

static float comfort_score[4] = {0, 1.0f, 1.0f, 1.0f};

static int pick_comfort_type(void)
{
    if ((float)rand() / (float)RAND_MAX < EPSILON_GREEDY) {
        return (rand() % 3) + 1;
    }

    int best = 1;
    if (comfort_score[2] > comfort_score[best]) best = 2;
    if (comfort_score[3] > comfort_score[best]) best = 3;
    return best;
}

/* Weighted Mahalanobis distance */
static float mahalanobis_d2(float z[Z_VECTOR_SIZE])
{
    /* Apply dimension weights */
    float wz[Z_VECTOR_SIZE];
    for (int i = 0; i < Z_VECTOR_SIZE; i++) {
        wz[i] = z[i] * g_dim_weight[i];
    }

    static float cov_inv[Z_VECTOR_SIZE][Z_VECTOR_SIZE];

    if (baseline_get_covariance(cov_inv) != 0) {
        /* Fallback to weighted Euclidean while covariance not ready */
        float d2 = 0;
        for (int i = 0; i < Z_VECTOR_SIZE; i++)
            d2 += wz[i] * wz[i];
        return d2;
    }

    /* D² = wzᵀ · Σ⁻¹ · wz */
    float d2 = 0;
    for (int i = 0; i < Z_VECTOR_SIZE; i++) {
        float row_sum = 0;
        for (int j = 0; j < Z_VECTOR_SIZE; j++) {
            row_sum += wz[j] * cov_inv[i][j];
        }
        d2 += wz[i] * row_sum;
    }
    return (d2 < 0) ? 0 : d2;
}

void anxiety_engine_init(void)
{
    memset(sound_hist, 0, sizeof(sound_hist));
    sound_pos = 0;
    comfort_score[0] = 0;
    comfort_score[1] = 1.0f;
    comfort_score[2] = 1.0f;
    comfort_score[3] = 1.0f;
    prev_anxiety = 0;

    baseline_learner_init();
    hrv_analyzer_init();

    g_anxiety_hist_idx = 0;
    for (int i = 0; i < TREND_WINDOW; i++) g_anxiety_hist[i] = 0;

    printf("[ANXIETY] engine v4.2 init (K=%.1f, trend=%ds)\n", MAHA_K, TREND_WINDOW);
    printf("[ANXIETY] weights: ACT=%.1f HR=%.1f HRV=%.1f "
           "BARK=%.1f TEMP=%.1f ENV=%.1f\n",
           W_ACTIVITY, W_HEARTRATE, W_HRV, W_BARK, W_TEMP, W_ENV);
}

void anxiety_engine_process(pet_env_data_t *env, anxiety_result_t *result)
{
    /* 1. Update bark history */
    sound_hist[sound_pos] = env->sound_detected;
    sound_pos = (sound_pos + 1) % SOUND_WINDOW;
    int barks = bark_count();

    /* 2. Update HRV analyser */
    hrv_analyzer_update();
    hrv_result_t hrv;
    hrv_analyzer_get_result(&hrv);
    float hrv_stress = hrv.valid ? hrv.stress_index : 0;

    /* 3. Compute env discomfort */
    float env_disc = env_discomfort(env->humidity, env->illumination);

    /* 4. Build 6-dim feature vector */
    /* Offline sensors are excluded from baseline via valid_mask — see below */

    float features[Z_VECTOR_SIZE];
    uint8_t valid_mask = 0;
    features[D_ACTIVITY]  = (float)env->activity_level;
    valid_mask |= (1 << D_ACTIVITY);
    features[D_BARK]      = (float)barks;
    valid_mask |= (1 << D_BARK);
    features[D_TEMP]      = (float)env->temperature;
    valid_mask |= (1 << D_TEMP);
    features[D_ENV]       = env_disc;
    valid_mask |= (1 << D_ENV);

    if (env->heart_rate > 0) {
        features[D_HEARTRATE] = (float)env->heart_rate;
        valid_mask |= (1 << D_HEARTRATE);
    } else {
        features[D_HEARTRATE] = 0;
    }

    if (hrv.valid && hrv_stress > 0.0f) {
        features[D_HRV] = hrv_stress;
        valid_mask |= (1 << D_HRV);
    } else {
        features[D_HRV] = 0;
    }

    /* 5. Update baseline learner */
    int hour = env->hour_of_day;
    if (hour < 0 || hour > 23) hour = 0;
    baseline_learner_update(hour, features, valid_mask);

    /* 6. Get Z-scores */
    baseline_z_t bz;
    baseline_learner_get_zscore(&bz);

    /* If heart rate is 0 (sensor off) or HRV invalid, zero their Z-scores */
    if (env->heart_rate == 0) bz.z[D_HEARTRATE] = 0;
    if (!hrv.valid)           bz.z[D_HRV]       = 0;

    /* A. HR-Activity decoupling: distinguish exercise from anxiety.
     *     High activity + high Z_HR = normal exercise -> dampen.
     *     Low activity + high Z_HR = resting tachycardia -> amplify (true distress).
     */
    if (env->heart_rate > 0 && env->activity_level > 35) {
        bz.z[D_HEARTRATE] *= 0.4f;
    } else if (env->heart_rate > 0 && env->activity_level < 8) {
        bz.z[D_HEARTRATE] *= 1.4f;
    }

    /* 7. Weighted Mahalanobis distance */
    float d2 = mahalanobis_d2(bz.z);

    /* 8. Map to anxiety 0-100 via sigmoid */
    /*
     * anxiety = 100 * (1 - exp(-D² / K))
     * With K=10.0:
     *   D²=3  → 26  (alert threshold)
     *   D²=6  → 45  (anxious threshold)
     *   D²=12 → 70  (distressed threshold)
     */
    int anxiety = (int)(100.0f * (1.0f - expf(-d2 / MAHA_K)));
    if (anxiety > 100) anxiety = 100;
    if (anxiety < 0)   anxiety = 0;

    /* 9. env_discomfort now goes through Mahalanobis pathway only (D_ENV) */
    (void)env_disc; /* already contributed via features[D_ENV] → Z-score → Mahalanobis */

    /* During learning phase, dampen high anxiety to avoid false alarms */
    if (bz.learning && anxiety > 40) {
        anxiety = 40 + (anxiety - 40) / 2;
    }

    result->anxiety_level = anxiety;
    result->mahalanobis_d2 = d2;

    /* 10. Count exceeded dimensions */
    int exceeds = 0;
    for (int d = 0; d < Z_VECTOR_SIZE; d++) {
        result->z_scores[d] = bz.z[d];
        if (bz.z[d] > Z_THRESHOLD || bz.z[d] < -Z_THRESHOLD) exceeds++;
    }
    result->exceed_count = exceeds;
    result->activity_level = env->activity_level;

    /* C. Trend detection: slope of anxiety over recent history */
    g_anxiety_hist[g_anxiety_hist_idx % TREND_WINDOW] = (float)anxiety;
    g_anxiety_hist_idx++;
    if (g_anxiety_hist_idx >= TREND_WINDOW) {
        float x_mean = (TREND_WINDOW - 1) / 2.0f;
        float y_mean = 0;
        for (int i = 0; i < TREND_WINDOW; i++) y_mean += g_anxiety_hist[i];
        y_mean /= TREND_WINDOW;
        float num = 0, den = 0;
        for (int i = 0; i < TREND_WINDOW; i++) {
            float dx = (float)i - x_mean;
            num += dx * (g_anxiety_hist[i] - y_mean);
            den += dx * dx;
        }
        float slope = (den > 0.01f) ? (num / den) : 0;
        if (slope > TREND_SLOPE_THRESH && anxiety >= 16) {
            if (anxiety >= 36 && result->emotion < EMOTION_ALERT)
                result->emotion = EMOTION_ALERT;
            else if (anxiety >= 61 && result->emotion < EMOTION_ANXIOUS)
                result->emotion = EMOTION_ANXIOUS;
        }
    }

    /* F. Sleep period (0-5am): low activity/HR is normal, reduce sensitivity */
    if (env->hour_of_day >= 0 && env->hour_of_day < 5) {
        anxiety = (int)(anxiety * 0.7f);
        if (exceeds >= 3) exceeds = 2;
    }

    /* 11. Emotion classification */
    if (anxiety >= 61)      result->emotion = EMOTION_ANXIOUS;
    else if (anxiety >= 36) result->emotion = EMOTION_ALERT;
    else if (anxiety >= 16) result->emotion = EMOTION_CALM;
    else                    result->emotion = EMOTION_HAPPY;

    /* 12. Comfort decision */
    switch (result->emotion) {
    case EMOTION_ANXIOUS:
        result->need_comfort = true;
        result->comfort_type = 3;
        break;
    case EMOTION_ALERT:
        result->need_comfort = true;
        result->comfort_type = pick_comfort_type();
        break;
    default:
        result->need_comfort = false;
        result->comfort_type = 0;
        break;
    }

    /* Escalation: 3+ dimensions exceeded → force anxiety */
    if (exceeds >= 3) {
        result->comfort_type = 3;
        if (result->anxiety_level < 61) result->anxiety_level = 61;
        result->emotion = EMOTION_ANXIOUS;
        result->need_comfort = true;
    } else if (exceeds >= 2 && result->emotion < EMOTION_ANXIOUS) {
        result->emotion = EMOTION_ANXIOUS;
        if (result->anxiety_level < 61) result->anxiety_level = 61;
        result->need_comfort = true;
        if (result->comfort_type < 2) result->comfort_type = 2;
    }

    /* 13. Diagnostic log */
    {
        const char *emo_str[] = {"HAPPY", "CALM", "ALERT", "ANXIOUS"};
        float contrib[Z_VECTOR_SIZE];
        for (int d = 0; d < Z_VECTOR_SIZE; d++) {
            contrib[d] = bz.z[d] * bz.z[d] * g_dim_weight[d] * g_dim_weight[d];
        }
        printf("[ANXIETY] Lv=%d D²=%.2f %s x=%d envD=%.1f "
               "w_z²=[%.2f %.2f %.2f %.2f %.2f %.2f] cmf=%d %s\n",
               anxiety, d2, emo_str[result->emotion], exceeds, env_disc,
               contrib[0], contrib[1], contrib[2],
               contrib[3], contrib[4], contrib[5],
               result->comfort_type,
               bz.learning ? "(learn)" : "");
    }

    prev_anxiety = anxiety;
}

void anxiety_engine_feedback(int comfort_type, int anxiety_before)
{
    if (comfort_type < 1 || comfort_type > 3) return;

    int anxiety_after = prev_anxiety;
    float delta = (float)(anxiety_before - anxiety_after);

    comfort_score[comfort_type] =
        COMFORT_ALPHA * delta + (1.0f - COMFORT_ALPHA) * comfort_score[comfort_type];

    printf("[ANXIETY] comfort feedback type=%d Δ=%+.0f "
           "scores=[%.1f %.1f %.1f]\n",
           comfort_type, delta,
           comfort_score[1], comfort_score[2], comfort_score[3]);
}
