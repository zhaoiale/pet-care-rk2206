#include "baseline_learner.h"
#include <math.h>
#include <stdio.h>
#include <string.h>
#include "lz_hardware/flash.h"
#include <stddef.h>

#define MIN_SAMPLES_PER_BUCKET  5
#define EPSILON  0.001f
#define ALPHA      0.05f
#define COV_ALPHA  0.01f
#define MIN_VAR    100.0f    /* minimum variance floor — prevents Z-score blowup */

/* --- Flash layout --- */
#define FLASH_BASELINE_OFFSET  0x7F2000
#define FLASH_BASELINE_MAGIC   0x424C534E  /* "BLSN" */

typedef struct {
    float mean;
    float var;
    int   count;
} bucket_t;

typedef struct {
    bucket_t buckets[24];
    float    last_z;
} dim_state_t;

/* Packed struct for flash — must match runtime layout exactly */
typedef struct {
    uint32_t    magic;
    uint32_t    checksum;
    uint32_t    snapshot_count;
    uint8_t     reserved[4];
    dim_state_t dims[DIM_COUNT];
    float       cov[Z_VECTOR_SIZE][Z_VECTOR_SIZE];
    float       cov_inv[Z_VECTOR_SIZE][Z_VECTOR_SIZE];
} baseline_flash_data_t;

static dim_state_t g_dim[DIM_COUNT];
static float g_cov[Z_VECTOR_SIZE][Z_VECTOR_SIZE];
static float g_cov_inv[Z_VECTOR_SIZE][Z_VECTOR_SIZE];
static int   g_cov_snapshot_count = 0;
static bool  g_cov_ready = false;
static bool  g_baseline_ready = false;

static float safe_sqrt(float x)
{
    return (x > 0) ? sqrtf(x) : 0.001f;
}

void baseline_learner_init(void)
{
    memset(g_dim, 0, sizeof(g_dim));
    memset(g_cov, 0, sizeof(g_cov));
    memset(g_cov_inv, 0, sizeof(g_cov_inv));
    g_cov_snapshot_count = 0;
    g_cov_ready = false;
    g_baseline_ready = false;

    for (int i = 0; i < Z_VECTOR_SIZE; i++)
        g_cov[i][i] = 1.0f;

    printf("[BASELINE] learner init (24h buckets, EWMA a=%.2f, min_var=%.1f)\n",
           ALPHA, MIN_VAR);
}

static float update_dim(dim_state_t *dim, int hour, float value)
{
    if (hour < 0 || hour > 23) return 0;
    bucket_t *b = &dim->buckets[hour];

    b->count++;

    if (b->count == 1) {
        b->mean = value;
        b->var  = MIN_VAR;
    } else {
        float delta = value - b->mean;
        b->mean += ALPHA * delta;
        b->var  += ALPHA * (delta * delta - b->var);
        if (b->var < MIN_VAR) b->var = MIN_VAR;
    }

    if (b->count < MIN_SAMPLES_PER_BUCKET) {
        dim->last_z = 0;
    } else {
        dim->last_z = (value - b->mean) / safe_sqrt(b->var + EPSILON);
    }
    return dim->last_z;
}

void baseline_learner_update(int hour, float values[Z_VECTOR_SIZE], uint8_t valid_mask)
{
    float z_snapshot[Z_VECTOR_SIZE];

    for (int d = 0; d < Z_VECTOR_SIZE; d++) {
        if (valid_mask & (1 << d)) {
            z_snapshot[d] = update_dim(&g_dim[d], hour, values[d]);
        } else {
            z_snapshot[d] = 0;
        }
    }

    /* Only update covariance when all validated dimensions have enough samples */
    bool all_valid = true;
    for (int d = 0; d < Z_VECTOR_SIZE; d++) {
        if ((valid_mask & (1 << d)) && g_dim[d].buckets[hour].count < MIN_SAMPLES_PER_BUCKET) {
            all_valid = false;
            break;
        }
    }

    if (all_valid) {
        for (int i = 0; i < Z_VECTOR_SIZE; i++) {
            for (int j = 0; j < Z_VECTOR_SIZE; j++) {
                g_cov[i][j] = (1.0f - COV_ALPHA) * g_cov[i][j]
                            + COV_ALPHA * z_snapshot[i] * z_snapshot[j];
            }
        }
        g_cov_snapshot_count++;

        if (g_cov_snapshot_count >= 288 && !g_baseline_ready) {
            g_baseline_ready = true;
            printf("[BASELINE] enough snapshots (%d), baseline ready\n",
                   g_cov_snapshot_count);
        }

        if (g_cov_snapshot_count >= 50 && g_cov_snapshot_count % 50 == 0) {
            static float L[Z_VECTOR_SIZE][Z_VECTOR_SIZE];
            memset(L, 0, sizeof(L));

            for (int i = 0; i < Z_VECTOR_SIZE; i++) {
                float sum = g_cov[i][i];
                for (int k = 0; k < i; k++)
                    sum -= L[i][k] * L[i][k];
                if (sum <= 0) sum = EPSILON;
                L[i][i] = sqrtf(sum);

                for (int j = i + 1; j < Z_VECTOR_SIZE; j++) {
                    sum = g_cov[j][i];
                    for (int k = 0; k < i; k++)
                        sum -= L[j][k] * L[i][k];
                    L[j][i] = sum / L[i][i];
                }
            }

            static float Li[Z_VECTOR_SIZE][Z_VECTOR_SIZE];
            memset(Li, 0, sizeof(Li));

            for (int i = 0; i < Z_VECTOR_SIZE; i++) {
                Li[i][i] = 1.0f / L[i][i];
                for (int j = 0; j < i; j++) {
                    float sum = 0;
                    for (int k = j; k < i; k++)
                        sum += L[i][k] * Li[k][j];
                    Li[i][j] = -sum / L[i][i];
                }
            }

            for (int i = 0; i < Z_VECTOR_SIZE; i++) {
                for (int j = i; j < Z_VECTOR_SIZE; j++) {
                    float sum = 0;
                    for (int k = j; k < Z_VECTOR_SIZE; k++)
                        sum += Li[k][i] * Li[k][j];
                    g_cov_inv[i][j] = sum;
                    g_cov_inv[j][i] = sum;
                }
            }

            if (!g_cov_ready) {
                g_cov_ready = true;
                printf("[BASELINE] covariance inverse ready "
                       "(snapshots=%d)\n", g_cov_snapshot_count);
            }

            /* Auto-save after each Cholesky update */
            baseline_save_to_flash();
        }
    }
}

void baseline_learner_get_zscore(baseline_z_t *out)
{
    for (int d = 0; d < Z_VECTOR_SIZE; d++) {
        out->z[d] = g_dim[d].last_z;
    }

    out->ready_dimensions = 0;
    for (int d = 0; d < Z_VECTOR_SIZE; d++) {
        for (int h = 0; h < 24; h++) {
            if (g_dim[d].buckets[h].count >= MIN_SAMPLES_PER_BUCKET) {
                out->ready_dimensions++;
                break;
            }
        }
    }
    out->learning = !g_baseline_ready;
}

int baseline_get_covariance(float cov[Z_VECTOR_SIZE][Z_VECTOR_SIZE])
{
    for (int i = 0; i < Z_VECTOR_SIZE; i++)
        for (int j = 0; j < Z_VECTOR_SIZE; j++)
            cov[i][j] = g_cov[i][j];
    return g_cov_ready ? 0 : -1;
}

bool baseline_is_ready(void)
{
    return g_cov_ready;
}

/* ================================================================
 * Flash persistence — 4K sector at FLASH_BASELINE_OFFSET
 * Saves: 6×24 EWMA buckets + covariance + inverse covariance
 * Auto-saves after each Cholesky update (every 50 snapshots)
 * ================================================================ */

static uint32_t baseline_checksum(const baseline_flash_data_t *data)
{
    uint32_t sum = 0;
    const uint8_t *p = (const uint8_t *)&data->snapshot_count;
    size_t len = sizeof(baseline_flash_data_t) - offsetof(baseline_flash_data_t, snapshot_count);
    for (size_t i = 0; i < len; i++) {
        sum = sum * 31 + p[i];
    }
    return sum;
}

int baseline_save_to_flash(void)
{
    /* Don't save if we have no meaningful data yet */
    if (g_cov_snapshot_count < 50) return 0;

    static uint8_t block[4096];
    memset(block, 0xFF, sizeof(block));

    baseline_flash_data_t *data = (baseline_flash_data_t *)block;
    data->magic          = FLASH_BASELINE_MAGIC;
    data->snapshot_count = (uint32_t)g_cov_snapshot_count;
    memset(data->reserved, 0, sizeof(data->reserved));

    memcpy(&data->dims, g_dim, sizeof(g_dim));
    memcpy(data->cov, g_cov, sizeof(g_cov));
    memcpy(data->cov_inv, g_cov_inv, sizeof(g_cov_inv));

    data->checksum = baseline_checksum(data);

    unsigned int ret = FlashErase(FLASH_BASELINE_OFFSET, 4096);
    if (ret != 0) {
        printf("[BASELINE-FLASH] erase failed: %u\n", ret);
        return -1;
    }

    ret = FlashWrite(FLASH_BASELINE_OFFSET, 4096, block, 1);
    if (ret != 0) {
        printf("[BASELINE-FLASH] write failed: %u\n", ret);
        return -1;
    }

    printf("[BASELINE-FLASH] saved (snapshots=%d, offset=0x%X)\n",
           g_cov_snapshot_count, FLASH_BASELINE_OFFSET);
    return 0;
}

int baseline_load_from_flash(void)
{
    static uint8_t block[4096];

    unsigned int ret = FlashRead(FLASH_BASELINE_OFFSET, 4096, block);
    if (ret != 0) {
        printf("[BASELINE-FLASH] read failed: %u\n", ret);
        return -1;
    }

    baseline_flash_data_t *data = (baseline_flash_data_t *)block;

    if (data->magic != FLASH_BASELINE_MAGIC) {
        printf("[BASELINE-FLASH] no valid data (magic=0x%X), starting fresh\n", data->magic);
        return -1;
    }

    uint32_t calc_sum = baseline_checksum(data);
    if (calc_sum != data->checksum) {
        printf("[BASELINE-FLASH] checksum mismatch (calc=0x%X stored=0x%X)\n",
               calc_sum, data->checksum);
        return -1;
    }

    if (data->snapshot_count < 50) {
        printf("[BASELINE-FLASH] too few snapshots (%u), starting fresh\n",
               data->snapshot_count);
        return -1;
    }

    /* Restore all state */
    memcpy(g_dim, &data->dims, sizeof(g_dim));
    memcpy(g_cov, data->cov, sizeof(g_cov));
    memcpy(g_cov_inv, data->cov_inv, sizeof(g_cov_inv));

    g_cov_snapshot_count = (int)data->snapshot_count;
    g_cov_ready = (g_cov_snapshot_count >= 50);
    g_baseline_ready = (g_cov_snapshot_count >= 288);

    int total_samples = 0;
    for (int d = 0; d < DIM_COUNT; d++)
        for (int h = 0; h < 24; h++)
            total_samples += g_dim[d].buckets[h].count;

    printf("[BASELINE-FLASH] loaded (snapshots=%d, samples=%d, cov_ready=%d, baseline_ready=%d)\n",
           g_cov_snapshot_count, total_samples, g_cov_ready, g_baseline_ready);
    return 0;
}
