#include "max30102.h"
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <math.h>
#include "iot_i2c.h"
#include "lz_hardware.h"
#include "iot_errno.h"
#include "los_task.h"

#define MAX30102_I2C_PORT  EI2C0_M2
#define MAX30102_FIFO_SIZE 32
#define MAX30102_SAMPLE_BYTES 6

static uint8_t g_detected = 0;

static void max30102_write_reg(uint8_t reg, uint8_t data)
{
    uint8_t send[2] = {reg, data};
    IoTI2cWrite(MAX30102_I2C_PORT, MAX30102_SLAVE_ADDRESS, send, 2);
}

static void max30102_read_reg(uint8_t reg, uint8_t *buf, uint8_t len)
{
    IoTI2cWrite(MAX30102_I2C_PORT, MAX30102_SLAVE_ADDRESS, &reg, 1);
    IoTI2cRead(MAX30102_I2C_PORT, MAX30102_SLAVE_ADDRESS, buf, len);
}

static int max30102_check_id(void)
{
    uint8_t id = 0;
    max30102_read_reg(MAX30102_PART_ID, &id, 1);
    printf("MAX30102 Part ID: 0x%02X\n", id);
    if (id != 0x15) {
        printf("MAX30102: unexpected Part ID 0x%02X\n", id);
        return 0;
    }
    return 1;
}

int max30102_init(void)
{
    printf("MAX30102: init start (I2C addr 0x57 on A0=SDA A1=SCL)\n");
    LOS_Msleep(100);

    /* Try reading Part ID first */
    int detected = 0;
    for (int attempt = 0; attempt < 3; attempt++) {
        uint8_t id = 0;
        max30102_read_reg(MAX30102_PART_ID, &id, 1);
        printf("MAX30102: attempt %d, Part ID = 0x%02X (expected 0x15)\n", attempt + 1, id);
        if (id == 0x15) {
            detected = 1;
            break;
        }
        LOS_Msleep(200);
    }

    if (!detected) {
        printf("MAX30102: NOT FOUND on I2C bus!\n");
        printf("MAX30102: Check: VIN->3.3V GND->GND SDA->A0 SCL->A1\n");
        g_detected = 0;
        return -1;
    }

    /* Reset */
    max30102_write_reg(MAX30102_MODE_CONFIG, 0x40);
    for (int i = 0; i < 50; i++) {
        uint8_t mode;
        max30102_read_reg(MAX30102_MODE_CONFIG, &mode, 1);
        if (!(mode & 0x40)) break;
        LOS_Msleep(10);
    }

    /* Clear FIFO pointers */
    max30102_write_reg(MAX30102_FIFO_WR_PTR, 0x00);
    max30102_write_reg(MAX30102_OVF_COUNTER, 0x00);
    max30102_write_reg(MAX30102_FIFO_RD_PTR, 0x00);

    /* FIFO config: average 4, rollover on, almost-full at 17 */
    max30102_write_reg(MAX30102_FIFO_CONFIG, 0x5F);

    /* SpO2 config: ADC range 4096, 100Hz, 411us pulse (18-bit) */
    max30102_write_reg(MAX30102_SPO2_CONFIG, 0x27);

    /* LED currents: ~9.4mA Red (low for power stability) */
    max30102_write_reg(MAX30102_LED1_PA, 0x2F);
    max30102_write_reg(MAX30102_LED2_PA, 0x2F);

    /* SpO2 mode */
    max30102_write_reg(MAX30102_MODE_CONFIG, 0x03);
    LOS_Msleep(100);

    /* Verify register writes took effect */
    {
        uint8_t v_led1, v_led2, v_mode, v_spo2;
        max30102_read_reg(MAX30102_LED1_PA, &v_led1, 1);
        max30102_read_reg(MAX30102_LED2_PA, &v_led2, 1);
        max30102_read_reg(MAX30102_MODE_CONFIG, &v_mode, 1);
        max30102_read_reg(MAX30102_SPO2_CONFIG, &v_spo2, 1);
        printf("MAX30102 verify: LED1=0x%02X LED2=0x%02X MODE=0x%02X SPO2=0x%02X\n",
               v_led1, v_led2, v_mode, v_spo2);
    }

    g_detected = 1;
    printf("MAX30102 init OK (I2C 0x57, 411Hz SpO2 mode)\n");
    return 0;
}

uint8_t max30102_is_detected(void)
{
    return g_detected;
}

int max30102_read_fifo(uint32_t *ir_data, uint32_t *red_data, uint8_t count)
{
    uint8_t wr_ptr, rd_ptr;
    int num_samples;

    if (!g_detected) return 0;

    max30102_read_reg(MAX30102_FIFO_WR_PTR, &wr_ptr, 1);
    max30102_read_reg(MAX30102_FIFO_RD_PTR, &rd_ptr, 1);

    num_samples = (int)wr_ptr - (int)rd_ptr;
    if (num_samples < 0) num_samples += MAX30102_FIFO_SIZE;
    if (num_samples == 0) return 0;
    if (num_samples > (int)count) num_samples = count;
    if (num_samples > MAX30102_FIFO_SIZE) num_samples = MAX30102_FIFO_SIZE;

    for (int i = 0; i < num_samples; i++) {
        uint8_t buf[6];
        max30102_read_reg(MAX30102_FIFO_DATA, buf, 6);

        ir_data[i]   = ((uint32_t)buf[0] << 16) | ((uint32_t)buf[1] << 8) | buf[2];
        ir_data[i]  &= 0x03FFFF;

        red_data[i]  = ((uint32_t)buf[3] << 16) | ((uint32_t)buf[4] << 8) | buf[5];
        red_data[i] &= 0x03FFFF;
    }

    return num_samples;
}

/* Effective sample rate after SMP_AVE=4 at 100Hz = 25Hz */
#define HR_SAMPLE_RATE  25.0f
#define HR_BUF_SIZE     100   /* 4 seconds at 25Hz */
#define HR_MIN_SAMPLES  50    /* need at least 2 seconds for first reading */
#define MIN_PEAK_GAP    8     /* ~0.32s between peaks → max ~187bpm */
#define IBI_BUF_SIZE    64

/* Static working buffer — avoids VLA stack pressure on Cortex-M4 */
static float g_work[HR_BUF_SIZE];

/* Ring buffer — always keeps the most recent HR_BUF_SIZE samples */
static uint32_t g_ir_ring[HR_BUF_SIZE];
static uint32_t g_red_ring[HR_BUF_SIZE];
static int g_ring_head = 0;
static int g_ring_count = 0;
static float g_last_hr = 0;

/* IBI buffer for HRV analysis */
static float g_ibi_buffer[IBI_BUF_SIZE];
static int   g_ibi_count = 0;
static int   g_ibi_head  = 0;

/* BPM median filter history */
#define BPM_MEDIAN_N 5
static float g_bpm_hist[BPM_MEDIAN_N] = {0};
static int   g_bpm_hist_idx = 0;
static int   g_bpm_hist_cnt = 0;

static int cmp_float(const void *a, const void *b)
{
    float fa = *(const float *)a;
    float fb = *(const float *)b;
    if (fa < fb) return -1;
    if (fa > fb) return 1;
    return 0;
}

static float median_bpm(float new_bpm)
{
    g_bpm_hist[g_bpm_hist_idx] = new_bpm;
    g_bpm_hist_idx = (g_bpm_hist_idx + 1) % BPM_MEDIAN_N;
    if (g_bpm_hist_cnt < BPM_MEDIAN_N) g_bpm_hist_cnt++;

    float sorted[BPM_MEDIAN_N];
    for (int i = 0; i < g_bpm_hist_cnt; i++) sorted[i] = g_bpm_hist[i];
    qsort(sorted, g_bpm_hist_cnt, sizeof(float), cmp_float);
    return sorted[g_bpm_hist_cnt / 2];
}

/* Light 3-point MA for high-freq spike suppression */
static void smooth_signal_float(float *src, float *dst, int n)
{
    if (n < 3) {
        for (int i = 0; i < n; i++) dst[i] = src[i];
        return;
    }
    dst[0] = (src[0] + src[1]) / 2.0f;
    for (int i = 1; i < n - 1; i++) {
        dst[i] = (src[i-1] + src[i] + src[i+1]) / 3.0f;
    }
    dst[n-1] = (src[n-2] + src[n-1]) / 2.0f;
}

/*
 * Optimized HR estimation pipeline (all steps use static g_work[]):
 *   1. EMA baseline drift tracking (DC removal)
 *   2. 1st-order IIR low-pass (fc ≈ 2.6Hz @ 25Hz)
 *   3. Adaptive threshold peak detection with hysteresis
 */
static float estimate_hr(float *sig, int n, float sample_rate)
{
    /* Step 1: EMA DC removal → g_work */
    float dc_ema = sig[0];
    g_work[0] = sig[0] - dc_ema;
    for (int i = 1; i < n; i++) {
        dc_ema = 0.005f * sig[i] + 0.995f * dc_ema;
        g_work[i] = sig[i] - dc_ema;
    }

    /* Step 2: IIR low-pass in-place on g_work */
    for (int i = 1; i < n; i++) {
        g_work[i] = 0.4f * g_work[i] + 0.6f * g_work[i - 1];
    }

    /* Step 3: Check signal quality */
    float sum = 0.0f;
    for (int i = 0; i < n; i++) sum += g_work[i];
    float mean = sum / (float)n;

    float var = 0.0f;
    for (int i = 0; i < n; i++) {
        float d = g_work[i] - mean;
        var += d * d;
    }
    var /= (float)n;
    if (var < 30.0f) {
        static int vprn = 0;
        if (++vprn >= 20) { vprn = 0;
            printf("MAX30102 HR: var=%.1f < 30, no pulsatile signal\n", var); }
        return 0.0f;
    }

    /* Step 4: Adaptive threshold peak detection */
    static int peaks[64];
    int peak_count = 0;
    int last_peak = -MIN_PEAK_GAP;
    int in_refractory = 0;

    for (int i = 30; i < n - 1; i++) {
        /* Sliding window local min/max (~1.2s) */
        float local_min = g_work[i];
        float local_max = g_work[i];
        for (int j = i - 30; j <= i; j++) {
            if (g_work[j] < local_min) local_min = g_work[j];
            if (g_work[j] > local_max) local_max = g_work[j];
        }

        float amplitude = local_max - local_min;
        if (amplitude < 20.0f) continue;

        float threshold = local_min + 0.4f * amplitude;
        float rearm     = local_min + 0.2f * amplitude;

        /* Hysteresis re-arm */
        if (in_refractory) {
            if (g_work[i] < rearm) in_refractory = 0;
            continue;
        }

        if (g_work[i] > g_work[i - 1] && g_work[i] > g_work[i + 1] &&
            g_work[i] > threshold &&
            (i - last_peak) >= MIN_PEAK_GAP) {
            peaks[peak_count++] = i;
            last_peak = i;
            in_refractory = 1;
            if (peak_count >= 64) break;
        }
    }

    if (peak_count < 2) {
        static int pprn = 0;
        if (++pprn >= 20) { pprn = 0;
            printf("MAX30102 HR: var=%.1f peaks=%d < 2, insufficient peaks\n", var, peak_count); }
        return 0.0f;
    }

    /* Step 5: BPM from average inter-peak interval */
    float total_interval = 0.0f;
    int valid_ibi = 0;
    for (int i = 1; i < peak_count; i++) {
        float interval_samples = (float)(peaks[i] - peaks[i - 1]);
        float ibi_ms = interval_samples / sample_rate * 1000.0f;

        total_interval += interval_samples;
        valid_ibi++;

        if (ibi_ms >= 300.0f && ibi_ms <= 2000.0f) {
            g_ibi_buffer[g_ibi_head] = ibi_ms;
            g_ibi_head = (g_ibi_head + 1) % IBI_BUF_SIZE;
            if (g_ibi_count < IBI_BUF_SIZE) g_ibi_count++;
        }
    }

    float avg_interval = total_interval / (float)valid_ibi;
    float bpm = 60.0f * sample_rate / avg_interval;

    if (bpm < 30.0f || bpm > 200.0f) {
        static int bprn = 0;
        if (++bprn >= 20) { bprn = 0;
            printf("MAX30102 HR: bpm=%.1f out of range [30-200], peaks=%d\n", bpm, peak_count); }
        return 0.0f;
    }
    return median_bpm(bpm);
}

/*
 * Improved SpO2: use RMS (standard deviation) as AC component.
 * RMS is more robust to outliers than mean absolute deviation.
 */
/*
 * Finger detection: when no finger is on the sensor, the IR LED light
 * scatters into air and the photodiode only sees low ambient levels.
 * With a finger, tissue reflects LED light → IR DC is much higher.
 * FINGER_IR_DC_MIN lowered from 80000 to 50000 — at 9.4mA LED current
 * (0x2F), IR DC with a finger typically reads 40k-70k. The old 80k
 * threshold was tuned for 25mA and caused frequent false "no finger"
 * detection on the RK2206's weak 3.3V rail.
 */
#define FINGER_IR_DC_MIN   50000.0f
#define FINGER_IR_AC_MIN   5.0f

/* Hysteresis: require this many consecutive "no finger" readings before
 * flushing the ring buffer. Prevents transient LED dropouts (common on
 * RK2206 due to weak 3.3V regulator) from nuking accumulated data. */
#define FINGER_ABSENT_FLUSH 5

static int g_finger_absent_cnt = 0;

static int is_finger_present(float *ir, float *red, int n,
                             float *ir_mean_out, float *ir_ac_out)
{
    float ir_sum = 0.0f;
    for (int i = 0; i < n; i++) ir_sum += ir[i];
    float ir_mean = ir_sum / (float)n;

    /* IR DC level: ambient without finger is typically < 10k */
    if (ir_mean < FINGER_IR_DC_MIN) return 0;

    /* IR AC amplitude: real PPG has clear pulsatile component */
    float ir_ac2 = 0.0f;
    for (int i = 0; i < n; i++) {
        float d = ir[i] - ir_mean;
        ir_ac2 += d * d;
    }
    float ir_ac = sqrtf(ir_ac2 / (float)n);
    if (ir_ac < FINGER_IR_AC_MIN) return 0;

    *ir_mean_out = ir_mean;
    *ir_ac_out = ir_ac;
    return 1;
}

static float estimate_spo2(float *ir, float *red, int n)
{
    float ir_mean, ir_ac;
    if (!is_finger_present(ir, red, n, &ir_mean, &ir_ac)) {
        return 0.0f;
    }

    float red_sum = 0.0f;
    for (int i = 0; i < n; i++) red_sum += red[i];
    float red_mean = red_sum / (float)n;

    /* RMS of AC component (std dev, more robust than MAD) */
    float red_ac2 = 0.0f;
    for (int i = 0; i < n; i++) {
        float d = red[i] - red_mean;
        red_ac2 += d * d;
    }
    float red_ac = sqrtf(red_ac2 / (float)n);

    float ratio = (red_ac / red_mean) / (ir_ac / ir_mean);
    float spo2 = 110.0f - 25.0f * ratio;
    if (spo2 > 100.0f) spo2 = 100.0f;
    if (spo2 < 70.0f)  spo2 = 70.0f;
    return spo2;
}

/* Feed raw IR/RED samples from wearable MQTT into local ring buffer */
void max30102_feed_raw(const uint32_t *ir, const uint32_t *red, int count)
{
    if (!ir || !red || count <= 0) return;
    for (int i = 0; i < count && i < HR_BUF_SIZE; i++) {
        g_ir_ring[g_ring_head]  = ir[i];
        g_red_ring[g_ring_head] = red[i];
        g_ring_head = (g_ring_head + 1) % HR_BUF_SIZE;
        if (g_ring_count < HR_BUF_SIZE) g_ring_count++;
    }
}

int max30102_get_heart_rate(float *hr, float *spo2)
{
    uint32_t ir_buf[32], red_buf[32];
    int n = max30102_read_fifo(ir_buf, red_buf, 32);

    /*
     * Quick finger check on the new FIFO batch: if the average IR is well
     * below the finger threshold, discard this batch and start draining the
     * ring buffer so stale data doesn't persist.
     */
    int finger_detected = 0;
    if (n > 0) {
        float batch_mean = 0.0f;
        for (int i = 0; i < n; i++) batch_mean += (float)ir_buf[i];
        batch_mean /= (float)n;
        finger_detected = (batch_mean > FINGER_IR_DC_MIN) ? 1 : 0;
    }

    if (finger_detected) {
        g_finger_absent_cnt = 0;  /* reset hysteresis */
        /* Push new samples into ring buffer */
        for (int i = 0; i < n; i++) {
            g_ir_ring[g_ring_head]   = ir_buf[i];
            g_red_ring[g_ring_head]  = red_buf[i];
            g_ring_head = (g_ring_head + 1) % HR_BUF_SIZE;
            if (g_ring_count < HR_BUF_SIZE) g_ring_count++;
        }
    } else if (n > 0) {
        /*
         * No finger on this batch — increment hysteresis counter.
         * Only flush after FINGER_ABSENT_FLUSH consecutive misses.
         * This prevents transient LED dropouts (RK2206 3.3V sag)
         * from needlessly destroying accumulated data.
         */
        g_finger_absent_cnt++;
        if (g_finger_absent_cnt >= FINGER_ABSENT_FLUSH) {
            printf("MAX30102: finger absent x%d, flushing ring buffer\n", g_finger_absent_cnt);
            g_ring_count = 0;
            g_ring_head = 0;
            g_last_hr = 0.0f;
            g_finger_absent_cnt = 0;
        }
    }

    /* Diagnostic print every ~3 seconds (15 calls at ~5Hz call rate) */
    {
        static int diag_cnt = 0;
        diag_cnt++;
        if (diag_cnt >= 15) {
            diag_cnt = 0;
            uint8_t wr, rd;
            max30102_read_reg(MAX30102_FIFO_WR_PTR, &wr, 1);
            max30102_read_reg(MAX30102_FIFO_RD_PTR, &rd, 1);
            printf("MAX30102 diag: wr=%u rd=%u n=%d cnt=%d finger=%d ir[0]=%lu\n",
                   wr, rd, n, g_ring_count, finger_detected,
                   (n > 0) ? (unsigned long)ir_buf[0] : 0);
        }
    }

    if (g_ring_count < HR_MIN_SAMPLES) {
        *hr = 0.0f;
        *spo2 = 0.0f;
        return -1;
    }

    /* Linearize ring buffer (static — avoid 800B stack pressure) */
    static float ir_lin[HR_BUF_SIZE], red_lin[HR_BUF_SIZE];
    int start = (g_ring_count < HR_BUF_SIZE) ? 0 : g_ring_head;
    for (int i = 0; i < g_ring_count; i++) {
        int idx = (start + i) % HR_BUF_SIZE;
        ir_lin[i]  = (float)g_ir_ring[idx];
        red_lin[i] = (float)g_red_ring[idx];
    }

    /* Light smoothing for spike suppression (static — avoid 800B stack pressure) */
    static float ir_smooth[HR_BUF_SIZE], red_smooth[HR_BUF_SIZE];
    smooth_signal_float(ir_lin, ir_smooth, g_ring_count);
    smooth_signal_float(red_lin, red_smooth, g_ring_count);

    *hr   = estimate_hr(ir_smooth, g_ring_count, HR_SAMPLE_RATE);
    *spo2 = estimate_spo2(ir_smooth, red_smooth, g_ring_count);

    /* HR/SpO2 diagnostic print */
    {
        static int hr_prn = 0;
        hr_prn++;
        if (hr_prn >= 15) {
            hr_prn = 0;
            printf("MAX30102 HR: %.0f bpm  SpO2: %.0f%%\n", *hr, *spo2);
        }
    }

    if (*hr > 0) g_last_hr = *hr;
    if (*spo2 > 0 && g_last_hr > 0) return 0;

    if (g_last_hr > 0) {
        *hr = g_last_hr;
        return 0;
    }
    return -1;
}

/* ========== HRV IBI interface ========== */

int max30102_get_ibi(float *ibi_out, int max_count)
{
    if (g_ibi_count == 0) return 0;

    int start = (g_ibi_count < IBI_BUF_SIZE) ? 0 : g_ibi_head;
    int n = (g_ibi_count < max_count) ? g_ibi_count : max_count;
    for (int i = 0; i < n; i++) {
        int idx = (start + i) % IBI_BUF_SIZE;
        ibi_out[i] = g_ibi_buffer[idx];
    }
    return n;
}
