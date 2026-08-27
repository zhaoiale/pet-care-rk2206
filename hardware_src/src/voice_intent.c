#include "voice_intent.h"
#include <stdio.h>
#include <string.h>
#include "los_task.h"

/* 规则阈值 (第一版, 用样本音频标定后调整; v2 换 MLP 时整体替换 classify 实现) */
#define TH_HUNGRY_SYL_MIN     3      /* 急促连叫: 音节数下限 */
#define TH_HUNGRY_SYL_MS_MAX  350.0f /* 急促连叫: 单音节偏短 */
#define TH_HUNGRY_ZCR_MIN     0.12f  /* 急促连叫: 音高偏高 */
#define TH_WARN_ZCR_MAX       0.08f  /* 低吼: 音高低 */
#define TH_WARN_SYL_MS_MIN    400.0f /* 低吼: 音节拖长 */
#define TH_WARN_DB_MIN        -28.0f /* 低吼: 响度大 */
#define TH_LONELY_DB_MAX      -32.0f /* 哼唧: 响度小 */
#define TH_LONELY_SYL_MS_MIN  250.0f /* 哼唧: 音节偏长 */

static voice_result_t g_last_result = {VOICE_INTENT_UNKNOWN, 0.0f, 0};
static bool g_pending = false;
static unsigned long long g_last_voice_ms = 0;

void voice_intent_classify(const float feat[VOICE_FEAT_DIM], voice_result_t *out)
{
    float syl_count   = feat[1];
    float mean_syl_ms = feat[2];
    float peak_db     = feat[4];
    float mean_db     = feat[5];
    float zcr_mean    = feat[6];

    out->intent = VOICE_INTENT_UNKNOWN;
    out->confidence = 0.5f;

    /* 决策树: lonely(呜咽) > warning(骂人/低吼) > hungry(急促叫) */
    if (syl_count < 4.0f && mean_syl_ms > 300.0f && mean_db < -22.0f &&
        zcr_mean < 0.12f && peak_db < -20.0f) {
        /* 音节少+拖长+安静+低音高+峰值也低(防削顶) → 委屈/呜咽 */
        out->intent = VOICE_INTENT_LONELY;
        out->confidence = 0.80f;
    } else if ((zcr_mean > 0.15f && (mean_db > -22.0f || mean_syl_ms > 600.0f)) ||
               (mean_db > -22.0f && syl_count >= 5.0f) ||
               (zcr_mean < TH_WARN_ZCR_MAX && mean_syl_ms > TH_WARN_SYL_MS_MIN &&
                mean_db > TH_WARN_DB_MIN)) {
        /* 高音高+响亮/拖长=骂人/吠叫 或 多音节大响=骂人 或 低吼长音节=警告 */
        out->intent = VOICE_INTENT_WARNING;
        out->confidence = 0.85f;
    } else if (syl_count >= TH_HUNGRY_SYL_MIN && mean_syl_ms < TH_HUNGRY_SYL_MS_MAX &&
               (zcr_mean > TH_HUNGRY_ZCR_MIN || mean_db > -28.0f)) {
        /* 急促短音节+高音高=饥饿 或 短音节+中等响度(削顶容错) */
        out->intent = VOICE_INTENT_HUNGRY;
        out->confidence = 0.85f;
    } else if (mean_db < TH_LONELY_DB_MAX && mean_syl_ms > TH_LONELY_SYL_MS_MIN && zcr_mean < 0.10f) {
        out->intent = VOICE_INTENT_LONELY;
        out->confidence = 0.75f;
    } else if (syl_count >= TH_HUNGRY_SYL_MIN) {
        out->intent = VOICE_INTENT_HUNGRY;
        out->confidence = 0.55f;
    }
}

void voice_intent_process(const float feat[VOICE_FEAT_DIM], unsigned int seq)
{
    voice_result_t r;
    voice_intent_classify(feat, &r);
    r.seq = seq;

    g_last_voice_ms = LOS_TickCountGet();  /* tick=1ms (默认1000Hz) */

    printf("VoiceIntent: seq=%u intent=%s conf=%.2f "
           "(dur=%.0f syl=%.0f sylms=%.0f db=%.1f zcr=%.3f)\n",
           seq, voice_intent_name(r.intent), r.confidence,
           feat[0], feat[1], feat[2], feat[5], feat[6]);

    if (r.intent != VOICE_INTENT_UNKNOWN) {
        g_last_result = r;
        g_pending = true;
    }
}

bool voice_intent_take_pending(voice_result_t *out)
{
    if (!g_pending) return false;
    *out = g_last_result;
    g_pending = false;
    return true;
}

bool voice_intent_recent(int window_s)
{
    if (g_last_voice_ms == 0) return false;
    unsigned long long now = LOS_TickCountGet();
    return (now - g_last_voice_ms) < (unsigned long long)window_s * 1000ULL;
}

voice_intent_t voice_intent_last(void)
{
    return g_last_result.intent;
}

const char *voice_intent_name(voice_intent_t it)
{
    switch (it) {
    case VOICE_INTENT_HUNGRY:  return "hungry";
    case VOICE_INTENT_WARNING: return "warning";
    case VOICE_INTENT_LONELY:  return "lonely";
    default:                   return "unknown";
    }
}

const char *voice_intent_text(voice_intent_t it)
{
    switch (it) {
    case VOICE_INTENT_HUNGRY:  return "饥饿、需要喂食";
    case VOICE_INTENT_WARNING: return "警告、请勿靠近";
    case VOICE_INTENT_LONELY:  return "委屈、寻求陪伴";
    default:                   return "未识别";
    }
}
