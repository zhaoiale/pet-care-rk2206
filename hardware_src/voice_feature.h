#ifndef __VOICE_FEATURE_H__
#define __VOICE_FEATURE_H__

#include <stdint.h>
#include <stdbool.h>

#define VOICE_FEAT_DIM  8   /* must match voice_intent.h */

/*
 * 本地 MAX9814 ADC 特征提取模块
 * 主循环每隔 ~100ms 调用 voice_feature_poll()
 * 检测到完整叫声 → 提取特征 → 调用 voice_intent_process()
 */

int  voice_feature_init(void);
void voice_feature_poll(void);
bool voice_feature_active(void);       /* currently hearing a vocalization */
float voice_feature_sound_level(void); /* 0.0~1.0, for anxiety D_BARK */

#endif
