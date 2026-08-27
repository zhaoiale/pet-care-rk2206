#ifndef _IOT_H_
#define _IOT_H_

#include <stdbool.h>

typedef struct
{
    double illumination;
    double temperature;
    double humidity;
    bool   motor_state;
    bool   light_state;
    bool   auto_state;
    int    anxiety_level;
    int    comfort_type;
    int    activity_level;     // MPU6050 活动量 0-100
    int    exceed_count;       // 超标指标数
    char   emotion[12];         // HAPPY/CALM/ALERT/ANXIOUS
    double food_weight;
    double food_eaten;
    float  heart_rate;         // MAX30102 心率 BPM
    float  spo2;               // MAX30102 血氧 %
    float  gps_lat;            // GPS 纬度 (decimal degrees)
    float  gps_lon;            // GPS 经度 (decimal degrees)
    float  hrv_stress;         // HRV 压力指数 (SD2/SD1)
    int    health_score;        // 健康综合评分 0-100
    float  body_temp;           // MLX90614 红外体温 ℃ (-999=无数据)
} e_iot_data;

#define IOT_CMD_LIGHT_ON  0x01
#define IOT_CMD_LIGHT_OFF 0x02
#define IOT_CMD_MOTOR_ON  0x03
#define IOT_CMD_MOTOR_OFF 0x04
#define IOT_CMD_AUTO_ON   0x05
#define IOT_CMD_AUTO_OFF  0x06
#define IOT_CMD_REFRESH   0x07
#define IOT_CMD_COMFORT   0x08
#define IOT_CMD_FEED      0x09
#define IOT_CMD_SET_HOME      0x0A
#define IOT_CMD_GET_PATH      0x0B
#define IOT_CMD_SCHEDULE_SYNC 0x0C
#define IOT_CMD_TIME_SYNC     0x0D
#define IOT_CMD_PLAY_SOUND    0x0E   /* App互动: SU-03T播放猫叫/狗叫音频 */

/* playSound 声音编号 (与智能公元平台词条一一对应) */
#define PET_SOUND_COMFORT   1   /* 安抚 - 呼噜声 */
#define PET_SOUND_FEED      2   /* 来吃饭 - 进食召唤 */
#define PET_SOUND_PLAY      3   /* 一起玩 - 玩耍嬉叫 */

/* playSound 物种 */
#define PET_SPECIES_CAT     0
#define PET_SPECIES_DOG     1

#define COMFORT_TYPE_LIGHT  1    // 灯光安抚 — RGB呼吸暖橙光
#define COMFORT_TYPE_AUDIO  2    // 语音安抚 — 统一类型, 由 audio_sub_type 细分

/* 语音安抚子类型 (仅当 comfort_type == COMFORT_TYPE_AUDIO 时有效) */
#define AUDIO_SUBTYPE_NOISE   1  // 白噪音 — 蜂鸣器低频起伏 + 暗蓝光
#define AUDIO_SUBTYPE_MUSIC   2  // 音乐   — 蜂鸣器五声音阶旋律 + 暖光
#define AUDIO_SUBTYPE_RECORD  3  // 录音   — SU-03T 播报安抚语 + 暖光

/* 向后兼容 */
#define COMFORT_TYPE_VOICE  2    // DEPRECATED
#define COMFORT_TYPE_NOISE  3    // DEPRECATED, 自动映射为 COMFORT_TYPE_AUDIO + AUDIO_SUBTYPE_NOISE

extern int g_audio_sub_type;

int wait_message();
void mqtt_init();
unsigned int mqtt_is_connected();
void send_msg_to_mqtt(e_iot_data *iot_data);
void send_path_to_mqtt(void);
void publish_voice_intent(void);

/* 穿戴设备远程数据接口 (ESP32 -> MQTT -> 主控) */
int  iot_wearable_data_available(void);
void iot_get_wearable_data(float *hr, float *spo2, int *activity);

#endif // _IOT_H_
