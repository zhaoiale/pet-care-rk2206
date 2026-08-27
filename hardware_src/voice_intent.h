#ifndef __VOICE_INTENT_H__
#define __VOICE_INTENT_H__

#include <stdbool.h>

/*
 * 叫声意图分类器 — 分布式感知节点(ESP32-C3+INMP441)上报8维声学特征,
 * 本模块在 RK2206 主控完成分类推理 (v1: 规则决策树; v2: 替换为训练好的MLP权重)
 *
 * 特征向量顺序 (与 ESP32 端 audio_features.h 严格一致):
 *   [0] dur_ms      整段叫声时长
 *   [1] syl_count   音节数
 *   [2] mean_syl_ms 平均音节时长
 *   [3] mean_gap_ms 平均音节间隔
 *   [4] peak_db     峰值响度 dBFS
 *   [5] mean_db     有声帧平均响度 dBFS
 *   [6] zcr_mean    平均过零率 (音高代理)
 *   [7] zcr_std     过零率标准差
 */

#define VOICE_FEAT_DIM 8

typedef enum {
    VOICE_INTENT_UNKNOWN = 0,
    VOICE_INTENT_HUNGRY,     /* 连续急促叫 -> 饥饿、需要喂食 */
    VOICE_INTENT_WARNING,    /* 低沉持续吼 -> 警告、请勿靠近 */
    VOICE_INTENT_LONELY,     /* 轻柔哼唧   -> 委屈、寻求陪伴 */
} voice_intent_t;

typedef struct {
    voice_intent_t intent;
    float confidence;        /* 0.0~1.0 */
    unsigned int seq;        /* ESP32 端序号 */
} voice_result_t;

/* 分类推理: 输入8维特征, 输出意图 */
void voice_intent_classify(const float feat[VOICE_FEAT_DIM], voice_result_t *out);

/* 供 iot.c 回调调用: 保存特征->分类->置待发布标志 */
void voice_intent_process(const float feat[VOICE_FEAT_DIM], unsigned int seq);

/* 主循环轮询: 有待发布结果时返回 true 并取走 (清标志) */
bool voice_intent_take_pending(voice_result_t *out);

/* 最近 window_s 秒内是否检测到叫声 (喂 anxiety_engine 的 sound_detected) */
bool voice_intent_recent(int window_s);

/* 最近一次意图 (LCD 显示用), 无则返回 VOICE_INTENT_UNKNOWN */
voice_intent_t voice_intent_last(void);

const char *voice_intent_name(voice_intent_t it);    /* 英文标识 e.g. "hungry" */
const char *voice_intent_text(voice_intent_t it);    /* 中文文案 e.g. "饥饿、需要喂食" */

#endif
