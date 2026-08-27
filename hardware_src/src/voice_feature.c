#include "voice_feature.h"
#include "voice_adc.h"
#include "voice_intent.h"
#include "los_task.h"
#include <stdio.h>
#include <math.h>
#include <string.h>

/* Frame: ~20ms @8kHz = 160 samples */
#define FRAME_SIZE         160

/* ---- VAD thresholds ---- */
#define VAD_RATIO          1.15f  /* energy > noise_floor * ratio → voiced */
#define VAD_CLIP_ZCR       0.02f  /* ZCR below this + energy > noise → clipping */
#define VAD_ONSET_FRAMES   3      /* N voiced frames to start recording */
#define VAD_OFFSET_FRAMES  20     /* N silence frames to end utterance (400ms) */
#define VAD_MAX_FRAMES     250    /* max 5s recording, force finish */
#define VAD_MIN_FRAMES     8      /* min ~160ms for valid vocalization */
#define VAD_NOISE_DECAY    0.01f  /* noise floor drifts up when louder */
#define VAD_NOISE_MIN       45.0f /* noise floor lower bound (quiet env) */
#define VAD_NOISE_MAX      250.0f /* noise floor upper bound (prevent clipping drift) */
#define VAD_WARMUP_FRAMES  50     /* first N frames just track noise, VAD off */

#define MAX_FRAMES         300

typedef struct {
    float energy;
    float zcr;
} frame_info_t;

/* ---- VAD state ---- */
typedef enum {
    VAD_IDLE,
    VAD_ONSET,    /* hearing possible voice, confirming */
    VAD_ACTIVE,   /* recording vocalization */
    VAD_OFFSET,   /* voice ended, confirming silence */
} vad_state_t;

static frame_info_t g_frames[MAX_FRAMES];
static int          g_frame_count = 0;
static float        g_sound_level = 0.0f;
static float        g_noise_floor = 999999.0f;  /* start high, will drop */
static float        g_dc_offset   = 2048.0f;

static vad_state_t  g_vad_state = VAD_IDLE;
static int          g_vad_counter = 0;  /* onset/offset confirm counter */
static int          g_warmup_ctr  = 0;  /* warmup frame counter */
static int          g_cooldown    = 0;  /* post-recording cooldown frames */
static unsigned int g_voice_seq = 0;

/* ---- internal helpers ---- */

static float frame_energy(const uint16_t *samples, int n)
{
    float sum = 0.0f;
    for (int i = 0; i < n; i++) {
        float s = (float)samples[i] - g_dc_offset;
        sum += fabsf(s);
    }
    return sum / (float)n;
}

static float frame_zcr(const uint16_t *samples, int n)
{
    int crossings = 0;
    float prev = (float)samples[0] - g_dc_offset;
    for (int i = 1; i < n; i++) {
        float cur = (float)samples[i] - g_dc_offset;
        if ((prev >= 0 && cur < 0) || (prev < 0 && cur >= 0)) {
            crossings++;
        }
        prev = cur;
    }
    return (float)crossings / (float)n;
}

static float db_approx(float energy)
{
    if (energy < 1.0f) return -60.0f;
    float db = 20.0f * log10f(energy / 2048.0f);
    if (db < -60.0f) db = -60.0f;
    if (db > 0.0f) db = 0.0f;
    return db;
}

/* ---- syllable counting ---- */

static int syllable_count(const frame_info_t *frames, int n)
{
    if (n < 2) return 1;
    int count = 1;
    float local_peak = frames[0].energy;
    bool in_dip = false;

    for (int i = 1; i < n; i++) {
        if (frames[i].energy > local_peak) {
            local_peak = frames[i].energy;
        }
        if (!in_dip && frames[i].energy < local_peak * 0.70f) {
            in_dip = true;
        }
        if (in_dip && frames[i].energy > local_peak * 0.60f) {
            count++;
            in_dip = false;
            local_peak = frames[i].energy;
        }
    }
    return count;
}

/* ---- finalize & classify ---- */

static void finalize_vocalization(const frame_info_t *frames, int n)
{
    if (n < VAD_MIN_FRAMES) return;

    float energies[MAX_FRAMES];
    float zcrs[MAX_FRAMES];
    float sum_e = 0.0f, peak_e = 0.0f;
    float sum_zcr = 0.0f, sum_zcr2 = 0.0f;

    for (int i = 0; i < n; i++) {
        energies[i] = frames[i].energy;
        zcrs[i] = frames[i].zcr;
        sum_e += energies[i];
        if (energies[i] > peak_e) peak_e = energies[i];
        sum_zcr += zcrs[i];
        sum_zcr2 += zcrs[i] * zcrs[i];
    }

    float mean_e = sum_e / (float)n;
    float mean_zcr = sum_zcr / (float)n;
    float zcr_std = sqrtf(sum_zcr2 / (float)n - mean_zcr * mean_zcr);
    if (zcr_std < 0.0f) zcr_std = 0.0f;

    float dur_ms = (float)n * 20.0f;

    int syl_n = syllable_count(frames, n);
    float mean_syl_ms = (syl_n > 0) ? dur_ms / (float)syl_n : dur_ms;
    float mean_gap_ms = (syl_n > 1) ? (dur_ms - mean_syl_ms * (float)syl_n)
                                     / (float)(syl_n - 1) : 0.0f;
    if (mean_gap_ms < 0.0f) mean_gap_ms = 0.0f;

    float feat[VOICE_FEAT_DIM];
    feat[0] = dur_ms;
    feat[1] = (float)syl_n;
    feat[2] = mean_syl_ms;
    feat[3] = mean_gap_ms;
    feat[4] = db_approx(peak_e);
    feat[5] = db_approx(mean_e);
    feat[6] = mean_zcr;
    feat[7] = zcr_std;

    printf("[VOICE] === vocalization end === dur=%.0fms syl=%d peak=%.1fdB mean=%.1fdB zcr=%.3f noise=%.0f\n",
           dur_ms, syl_n, feat[4], feat[5], mean_zcr, g_noise_floor);

    voice_intent_process(feat, g_voice_seq++);
}

/* ---- VAD state machine ---- */

static void vad_process_frame(frame_info_t *fi)
{
    /* Warmup: first N frames just track noise floor, VAD stays in IDLE */
    if (g_warmup_ctr < VAD_WARMUP_FRAMES) {
        g_warmup_ctr++;
        if (fi->energy < g_noise_floor) {
            g_noise_floor = fi->energy;
        }
        if (g_noise_floor < VAD_NOISE_MIN) g_noise_floor = VAD_NOISE_MIN;
        if (g_warmup_ctr == VAD_WARMUP_FRAMES) {
            printf("[VAD] warmup done, noise=%.0f thr=%.0f\n",
                   g_noise_floor, g_noise_floor * VAD_RATIO);
        }
        return;
    }

    /* Only update noise floor in IDLE and outside cooldown */
    if (g_vad_state == VAD_IDLE && g_cooldown == 0) {
        if (fi->energy < g_noise_floor) {
            g_noise_floor = fi->energy;
        } else {
            g_noise_floor += VAD_NOISE_DECAY * (fi->energy - g_noise_floor);
        }
        if (g_noise_floor < VAD_NOISE_MIN) g_noise_floor = VAD_NOISE_MIN;
        if (g_noise_floor > VAD_NOISE_MAX) g_noise_floor = VAD_NOISE_MAX;
    }

    float threshold = g_noise_floor * VAD_RATIO;
    bool voiced = (fi->energy > threshold)
               || (fi->energy > g_noise_floor * 1.05f && fi->zcr < VAD_CLIP_ZCR);

    switch (g_vad_state) {

    case VAD_IDLE:
        if (g_cooldown > 0) {
            g_cooldown--;
            break;
        }
        if (voiced) {
            g_vad_state = VAD_ONSET;
            g_vad_counter = 1;
            g_frames[0] = *fi;
            g_frame_count = 1;
        }
        break;

    case VAD_ONSET:
        g_frames[g_frame_count++] = *fi;
        if (voiced) {
            g_vad_counter++;
            if (g_vad_counter >= VAD_ONSET_FRAMES) {
                g_vad_state = VAD_ACTIVE;
                printf("[VAD] onset confirmed, recording... (noise=%.0f thr=%.0f)\n",
                       g_noise_floor, threshold);
            }
        } else {
            /* false alarm, back to idle */
            g_vad_state = VAD_IDLE;
            g_frame_count = 0;
            g_cooldown = 50;
        }
        break;

    case VAD_ACTIVE:
        if (g_frame_count < MAX_FRAMES) {
            g_frames[g_frame_count++] = *fi;
        }
        if (!voiced) {
            g_vad_state = VAD_OFFSET;
            g_vad_counter = 1;
        } else if (g_frame_count >= VAD_MAX_FRAMES) {
            /* forced finish */
            printf("[VAD] max duration reached, finalizing\n");
            finalize_vocalization(g_frames, g_frame_count);
            g_vad_state = VAD_IDLE;
            g_frame_count = 0;
            g_cooldown = 50;
        }
        break;

    case VAD_OFFSET:
        if (g_frame_count < MAX_FRAMES) {
            g_frames[g_frame_count++] = *fi;
        }
        if (voiced) {
            /* voice resumed, back to active */
            g_vad_state = VAD_ACTIVE;
        } else {
            g_vad_counter++;
            if (g_vad_counter >= VAD_OFFSET_FRAMES) {
                /* confirmed end of vocalization */
                int valid_frames = g_frame_count - VAD_OFFSET_FRAMES;
                if (valid_frames >= VAD_MIN_FRAMES) {
                    finalize_vocalization(g_frames, valid_frames);
                } else {
                    printf("[VAD] too short (%d frames), discarded\n", valid_frames);
                }
                g_vad_state = VAD_IDLE;
                g_frame_count = 0;
                g_cooldown = 50;
            }
        }
        break;
    }
}

/* ---- public API ---- */

void voice_feature_poll(void)
{
    /* Auto-calibrate DC offset once */
    {
        static int calibrated = 0;
        if (!calibrated && voice_adc_available() >= FRAME_SIZE) {
            uint16_t calib[FRAME_SIZE];
            voice_adc_read(calib, FRAME_SIZE);
            float sum = 0.0f;
            for (int i = 0; i < FRAME_SIZE; i++) sum += (float)calib[i];
            g_dc_offset = sum / (float)FRAME_SIZE;
            calibrated = 1;
            printf("[VOICE] DC offset calibrated: %.1f\n", g_dc_offset);
            printf("[VOICE] raw samples: ");
            for (int i = 0; i < 10; i++) printf("%u ", calib[i]);
            printf("... min=%u max=%u\n",
                   (unsigned)calib[0], (unsigned)calib[0]);
            /* print actual min/max across all 160 samples */
            {
                uint16_t rmin = calib[0], rmax = calib[0];
                for (int i = 1; i < FRAME_SIZE; i++) {
                    if (calib[i] < rmin) rmin = calib[i];
                    if (calib[i] > rmax) rmax = calib[i];
                }
                printf("[VOICE] raw range: %u ~ %u (span=%u)\n",
                       (unsigned)rmin, (unsigned)rmax, (unsigned)(rmax - rmin));
            }
        }
        if (!calibrated) return;
    }

    /* Process one frame at a time (each poll = 1 frame) */
    while (voice_adc_available() >= FRAME_SIZE) {
        uint16_t samples[FRAME_SIZE];
        voice_adc_read(samples, FRAME_SIZE);

        frame_info_t fi;
        fi.energy = frame_energy(samples, FRAME_SIZE);
        fi.zcr    = frame_zcr(samples, FRAME_SIZE);

        g_sound_level = fi.energy / 2000.0f;
        if (g_sound_level > 1.0f) g_sound_level = 1.0f;

        /* Log every 50 frames (~1s) in IDLE so we can see noise floor */
        {
            static int idle_log_ctr = 0;
            if (g_vad_state == VAD_IDLE) {
                idle_log_ctr++;
                if (idle_log_ctr >= 50) {
                    idle_log_ctr = 0;
                    printf("[VAD] idle noise=%.0f thr=%.0f cur=%.0f zcr=%.4f\r\n",
                           g_noise_floor, g_noise_floor * VAD_RATIO, fi.energy, fi.zcr);
                }
            }
        }

        /* Log during active recording */
        if (g_vad_state == VAD_ACTIVE && (g_frame_count % 10) == 0) {
            printf("[VAD] recording frame %d energy=%.0f zcr=%.4f\r\n",
                   g_frame_count, fi.energy, fi.zcr);
        }

        vad_process_frame(&fi);
    }
}

bool voice_feature_active(void)
{
    return (g_vad_state == VAD_ACTIVE || g_vad_state == VAD_OFFSET);
}

float voice_feature_sound_level(void)
{
    return g_sound_level;
}

/* ---- dedicated voice processing task ---- */

static void voice_feature_thread(uint32_t arg)
{
    (void)arg;
    printf("[VOICE] VAD task started\n");
    while (1) {
        voice_feature_poll();
        LOS_Msleep(20);
    }
}

int voice_feature_init(void)
{
    unsigned int task_id;
    TSK_INIT_PARAM_S task = {0};
    task.pfnTaskEntry = (TSK_ENTRY_FUNC)voice_feature_thread;
    task.uwStackSize = 8192;
    task.pcName = "voice_feat";
    task.usTaskPrio = 25;
    unsigned int ret = LOS_TaskCreate(&task_id, &task);
    if (ret != LOS_OK) {
        printf("[VOICE] task create failed: %u\n", ret);
        return -1;
    }
    printf("[VOICE] task created, id=%u\n", task_id);
    return 0;
}
