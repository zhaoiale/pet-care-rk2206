#ifndef __SU_03T_H__
#define __SU_03T_H__

#include <stdint.h>

enum auto_command
{
    auto_state_on = 0x0001,
    auto_state_off,
};

enum light_command
{
    light_state_on = 0x0101,
    light_state_off,
};

enum motor_command
{
    motor_state_on = 0x0201,
    motor_state_off,
};

enum feeder_command
{
    feed_start = 0x0401,   // "喂食" — 触发投喂
};

enum senror_command
{
    temperature_get = 0x0301,
    humidity_get,
    illumination_get,
    anxiety_get,        // "查询焦虑等级"
    heart_rate_get,     // "查询心率"
};

// SU-03T voice prompt indices
#define SU03T_VOICE_TEMP      1
#define SU03T_VOICE_HUMI      2
#define SU03T_VOICE_LUM       3
#define SU03T_VOICE_COMFORT   4   // 安抚语音
#define SU03T_VOICE_ANXIETY   5   // 焦虑等级播报
#define SU03T_VOICE_HEART     6   // 心率播报
#define SU03T_VOICE_FEED_DONE 7   // 投喂完成确认

// 宠物叫声播放 (人→宠物 反向交互)
#define SU03T_VOICE_PET_HUNGRY    10
#define SU03T_VOICE_PET_HAPPY_DOG 11
#define SU03T_VOICE_PET_HAPPY_CAT 12
#define SU03T_VOICE_PET_WARNING   13
#define SU03T_VOICE_PET_LONELY    14
#define SU03T_VOICE_PET_PLAY      15
#define SU03T_VOICE_PET_CALM      16

void su03t_init(void);
void su03t_send_double_msg(uint8_t index, double dat);
void su03t_send_u8_msg(uint8_t index, int32_t dat);
void su03t_play_pet_sound(const char *species, const char *intent);

#endif
