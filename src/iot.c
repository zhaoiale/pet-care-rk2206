/*
 * Copyright (c) 2024 iSoftStone Education Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "MQTTClient.h"
#include "cJSON.h"
#include "cmsis_os2.h"
#include "config_network.h"
#include "iot.h"
#include "geofence.h"
#include "feed_scheduler.h"
#include "los_task.h"
#include "ohos_init.h"
#include "smart_home_event.h"
#include "smart_home.h"
#include "su_03t.h"
#include "voice_intent.h"

#define MQTT_DEVICES_PWD "public"

// HiveMQ 公共 MQTT Broker
#define HOST_ADDR "broker.hivemq.com"

#define DEVICE_ID "petcare_rk2206_001"

// 公共 topic，App 端订阅同一个 topic 即可接收数据
#define PUBLISH_TOPIC "petcare/device/data"
#define SUBCRIB_TOPIC "petcare/device/command"
#define RESPONSE_TOPIC "petcare/device/response"
#define VOICE_FEAT_TOPIC "petcare/voice/features"   /* ESP32感知节点 -> 主控 */
#define VOICE_INTENT_TOPIC "petcare/voice/intent"   /* 主控分类结果 -> App */
#define WEARABLE_TOPIC     "pet/wearable/data"      /* ESP32穿戴设备 -> 主控 */

#define MAX_BUFFER_LENGTH 1024
#define MAX_STRING_LENGTH 64
#define PATH_CHUNK_SIZE 10    /* GPS points per MQTT message */

static unsigned char sendBuf[MAX_BUFFER_LENGTH];
static unsigned char readBuf[MAX_BUFFER_LENGTH];

Network network;
MQTTClient client;

static char mqtt_devid[64]=DEVICE_ID;
static char mqtt_pwd[64]=MQTT_DEVICES_PWD;
static char mqtt_username[64]=DEVICE_ID;
static char mqtt_hostaddr[64]=HOST_ADDR;

static char publish_topic[128] = PUBLISH_TOPIC;
static char subcribe_topic[128] = SUBCRIB_TOPIC;
static char response_topic[128] = RESPONSE_TOPIC;

static unsigned int mqttConnectFlag = 0;

void mqtt_voice_feat_arrived(MessageData *data);
void mqtt_wearable_arrived(MessageData *data);

/* 穿戴设备远程数据 (ESP32 -> MQTT -> 主控) */
static float  g_wearable_hr     = 0;
static float  g_wearable_spo2   = 0;
static int    g_wearable_activity = 0;
volatile static int g_wearable_fresh = 0;
#define WEARABLE_TIMEOUT_MS  10000   /* 超过10秒无新数据则回退本地传感器 */

extern bool motor_state;
extern bool light_state;
extern bool auto_state;

/***************************************************************
* 函数名称: send_msg_to_mqtt
* 说    明: 发送信息到 MQTT (HiveMQ 公共 Broker)
* 参    数: e_iot_data *iot_data：数据
* 返 回 值: 无
***************************************************************/
void send_msg_to_mqtt(e_iot_data *iot_data) {
  int rc;
  MQTTMessage message;
  char payload[MAX_BUFFER_LENGTH] = {0};
  char str[MAX_STRING_LENGTH] = {0};

  if (mqttConnectFlag == 0) {
    printf("mqtt not connect\n");
    return;
  }

  cJSON *root = cJSON_CreateObject();
  if (root != NULL) {
    cJSON *serv_arr = cJSON_AddArrayToObject(root, "services");
    cJSON *arr_item = cJSON_CreateObject();
    cJSON_AddStringToObject(arr_item, "service_id", "petCare");
    cJSON *pro_obj = cJSON_CreateObject();
    cJSON_AddItemToObject(arr_item, "properties", pro_obj);

    memset(str, 0, sizeof(str));
    // 光照强度
    snprintf(str, sizeof(str), "%5.2fLux", iot_data->illumination);
    cJSON_AddStringToObject(pro_obj, "illumination", str);
    // 温度
    snprintf(str, sizeof(str), "%5.2f", iot_data->temperature);
    cJSON_AddStringToObject(pro_obj, "temperature", str);
    // 湿度
    snprintf(str, sizeof(str), "%5.2f", iot_data->humidity);
    cJSON_AddStringToObject(pro_obj, "humidity", str);
    // 电机状态
    if (iot_data->motor_state == true) {
      cJSON_AddStringToObject(pro_obj, "motorStatus", "ON");
    } else {
      cJSON_AddStringToObject(pro_obj, "motorStatus", "OFF");
    }
    // 灯光状态
    if (iot_data->light_state == true) {
      cJSON_AddStringToObject(pro_obj, "lightStatus", "ON");
    } else {
      cJSON_AddStringToObject(pro_obj, "lightStatus", "OFF");
    }
    // 自动状态模式
    if (iot_data->auto_state == true) {
      cJSON_AddStringToObject(pro_obj, "autoStatus", "ON");
    } else {
      cJSON_AddStringToObject(pro_obj, "autoStatus", "OFF");
    }
    // 焦虑指数
    cJSON_AddNumberToObject(pro_obj, "anxietyLevel", iot_data->anxiety_level);
    // 安抚类型
    cJSON_AddNumberToObject(pro_obj, "comfortType", iot_data->comfort_type);
    // 音频安抚子类型 (仅当 comfortType==2 时有效)
    {
        extern int g_audio_sub_type;
        cJSON_AddNumberToObject(pro_obj, "audioSubType", g_audio_sub_type);
    }
    // 活动量 (MPU6050)
    cJSON_AddNumberToObject(pro_obj, "activityLevel", iot_data->activity_level);
    // 超标计数
    cJSON_AddNumberToObject(pro_obj, "exceedCount", iot_data->exceed_count);
    // 情绪状态
    cJSON_AddStringToObject(pro_obj, "emotion", iot_data->emotion);
    // 食盆重量 (HX711)
    cJSON_AddNumberToObject(pro_obj, "foodWeight", iot_data->food_weight);
    // 宠物已食量
    cJSON_AddNumberToObject(pro_obj, "foodEaten", iot_data->food_eaten);
    // 心率 (MAX30102)
    cJSON_AddNumberToObject(pro_obj, "heartRate", iot_data->heart_rate);
    // 血氧 (MAX30102)
    cJSON_AddNumberToObject(pro_obj, "spo2", iot_data->spo2);
    // GPS 纬度
    cJSON_AddNumberToObject(pro_obj, "gpsLat", iot_data->gps_lat);
    // GPS 经度
    cJSON_AddNumberToObject(pro_obj, "gpsLon", iot_data->gps_lon);
    // HRV 压力指数
    cJSON_AddNumberToObject(pro_obj, "hrvStress", iot_data->hrv_stress);
    // 体温 (MLX90614, -999 = 无数据)
    cJSON_AddNumberToObject(pro_obj, "bodyTemp", iot_data->body_temp);
    // 健康评分
    cJSON_AddNumberToObject(pro_obj, "healthScore", iot_data->health_score);
    // 电子围栏
    {
        float dist;
        float hlat, hlon;
        int status;
        extern int g_last_geofence_status;
        status = g_last_geofence_status;
        cJSON_AddNumberToObject(pro_obj, "geofenceStatus", status);
        if (geofence_get_home(&hlat, &hlon)) {
            cJSON_AddNumberToObject(pro_obj, "homeLat", hlat);
            cJSON_AddNumberToObject(pro_obj, "homeLon", hlon);
        }
    }

    cJSON_AddItemToArray(serv_arr, arr_item);

    char *palyload_str = cJSON_PrintUnformatted(root);
    if (palyload_str != NULL) {
      strncpy(payload, palyload_str, MAX_BUFFER_LENGTH - 1);
      payload[MAX_BUFFER_LENGTH - 1] = '\0';
      cJSON_free(palyload_str);
    } else {
      payload[0] = '\0';
    }
    cJSON_Delete(root);
  }

  message.qos = 0;
  message.retained = 0;
  message.payload = payload;
  message.payloadlen = strlen(payload);

  if ((rc = MQTTPublish(&client, publish_topic, &message)) != 0) {
    printf("Return code from MQTT publish is %d\n", rc);
    mqttConnectFlag = 0;
  } else {
    printf("mqtt publish success:%s\n", payload);
  }
}

/***************************************************************
* 函数名称: set_light_state
* 说    明: 设置灯状态
* 参    数: cJSON *root
* 返 回 值: 无
***************************************************************/
void set_light_state(cJSON *root) {
  cJSON *para_obj = NULL;
  cJSON *status_obj = NULL;
  char *value = NULL;

  event_info_t event={0};
  event.event=event_iot_cmd;

  para_obj = cJSON_GetObjectItem(root, "paras");
  status_obj = cJSON_GetObjectItem(para_obj, "onoff");
  if (status_obj != NULL) {
    value = cJSON_GetStringValue(status_obj);
    if (!strcmp(value, "ON")) {
      event.data.iot_data = IOT_CMD_LIGHT_ON;
    } else if (!strcmp(value, "OFF")) {
      event.data.iot_data = IOT_CMD_LIGHT_OFF;
    }
    smart_home_event_send(&event);
  }
}

/***************************************************************
* 函数名称: set_motor_state
* 说    明: 设置电机状态
* 参    数: cJSON *root
* 返 回 值: 无
***************************************************************/
void set_motor_state(cJSON *root) {
  cJSON *para_obj = NULL;
  cJSON *status_obj = NULL;
  char *value = NULL;

  event_info_t event={0};
  event.event=event_iot_cmd;

  para_obj = cJSON_GetObjectItem(root, "paras");
  status_obj = cJSON_GetObjectItem(para_obj, "onoff");
  if (status_obj != NULL) {
    value = cJSON_GetStringValue(status_obj);
    if (!strcmp(value, "ON")) {
      event.data.iot_data = IOT_CMD_MOTOR_ON;
    } else if (!strcmp(value, "OFF")) {
      event.data.iot_data = IOT_CMD_MOTOR_OFF;
    }
    smart_home_event_send(&event);
  }
}

/***************************************************************
* 函数名称: set_auto_state
* 说    明: 设置自动模式状态
* 参    数: cJSON *root
* 返 回 值: 无
***************************************************************/
void set_auto_state(cJSON *root) {
  cJSON *para_obj = NULL;
  cJSON *status_obj = NULL;
  char *value = NULL;

  para_obj = cJSON_GetObjectItem(root, "paras");
  status_obj = cJSON_GetObjectItem(para_obj, "onoff");
  if (status_obj != NULL) {
    value = cJSON_GetStringValue(status_obj);
    if (!strcmp(value, "ON")) {
      // auto_state = true;
    } else if (!strcmp(value, "OFF")) {
      // auto_state = false;
    }
  }
}

/***************************************************************
* 函数名称: mqtt_message_arrived
* 说    明: 接收mqtt数据
* 参    数: MessageData *data
* 返 回 值: 无
***************************************************************/
void mqtt_message_arrived(MessageData *data) {
  cJSON *root = NULL;
  cJSON *cmd_name = NULL;
  char *cmd_name_str = NULL;

  printf("Message arrived on topic %.*s: %.*s\n",
         data->topicName->lenstring.len, data->topicName->lenstring.data,
         data->message->payloadlen, data->message->payload);

  // 解析接收到的消息
  root =
      cJSON_ParseWithLength(data->message->payload, data->message->payloadlen);
  if (root != NULL) {
    // 新格式: {"cmd":"refresh"}
    cmd_name = cJSON_GetObjectItem(root, "cmd");
    if (cmd_name != NULL) {
      cmd_name_str = cJSON_GetStringValue(cmd_name);
      if (!strcmp(cmd_name_str, "refresh")) {
        // 发送刷新事件
        event_info_t event={0};
        event.event=event_iot_cmd;
        event.data.iot_data = IOT_CMD_REFRESH;
        smart_home_event_send(&event);
        printf("Refresh command received, triggering immediate publish\n");
      } else if (!strcmp(cmd_name_str, "comfort")) {
        // 远程一键安抚: {"cmd":"comfort","type":1|2,"audioSubType":1|2|3}
        cJSON *type_obj = cJSON_GetObjectItem(root, "type");
        cJSON *audio_obj = cJSON_GetObjectItem(root, "audioSubType");
        g_comfort_mode = (type_obj && type_obj->type == cJSON_Number)
                         ? type_obj->valueint : COMFORT_TYPE_LIGHT;
        if (audio_obj && audio_obj->type == cJSON_Number) {
            g_audio_sub_type = audio_obj->valueint;
        }
        event_info_t event={0};
        event.event=event_iot_cmd;
        event.data.iot_data = IOT_CMD_COMFORT;
        smart_home_event_send(&event);
        printf("Comfort command received, type=%d audioSubType=%d\n",
               g_comfort_mode, g_audio_sub_type);
      } else if (!strcmp(cmd_name_str, "feed")) {
        // 远程投喂
        cJSON *amount_obj = cJSON_GetObjectItem(root, "amount");
        g_feed_amount = (amount_obj && amount_obj->type == cJSON_Number)
                        ? amount_obj->valueint : 50;
        event_info_t event={0};
        event.event=event_iot_cmd;
        event.data.iot_data = IOT_CMD_FEED;
        smart_home_event_send(&event);
        printf("Feed command received, %dg\n", g_feed_amount);
      } else if (!strcmp(cmd_name_str, "setHome")) {
        event_info_t event={0};
        event.event=event_iot_cmd;
        event.data.iot_data = IOT_CMD_SET_HOME;
        smart_home_event_send(&event);
        printf("SetHome command received\n");
      } else if (!strcmp(cmd_name_str, "getPath")) {
        event_info_t event={0};
        event.event=event_iot_cmd;
        event.data.iot_data = IOT_CMD_GET_PATH;
        smart_home_event_send(&event);
        printf("GetPath command received\n");
      } else if (!strcmp(cmd_name_str, "scheduleSync")) {
        char *raw = cJSON_PrintUnformatted(root);
        if (raw) {
            int n = feed_scheduler_parse_json(raw);
            printf("ScheduleSync: %d entries parsed\n", n);
            cJSON_free(raw);
        }
      } else if (!strcmp(cmd_name_str, "timeSync")) {
        cJSON *ts_obj = cJSON_GetObjectItem(root, "ts");
        if (ts_obj && ts_obj->type == cJSON_Number) {
            feed_scheduler_sync_time((uint32_t)ts_obj->valueint);
            printf("TimeSync: ts=%u\n", (uint32_t)ts_obj->valueint);
        }
      } else if (!strcmp(cmd_name_str, "playSound")) {
        /* App互动: {"cmd":"playSound","intent":"happy","species":"dog"} */
        cJSON *int_obj = cJSON_GetObjectItem(root, "intent");
        cJSON *sp_obj  = cJSON_GetObjectItem(root, "species");
        if (int_obj && int_obj->valuestring) {
            strncpy(g_play_sound_intent, int_obj->valuestring,
                    sizeof(g_play_sound_intent) - 1);
            g_play_sound_intent[sizeof(g_play_sound_intent) - 1] = '\0';
        } else {
            strncpy(g_play_sound_intent, "happy", sizeof(g_play_sound_intent) - 1);
        }
        if (sp_obj && sp_obj->valuestring && !strcmp(sp_obj->valuestring, "dog")) {
            g_play_sound_species = PET_SPECIES_DOG;
        } else {
            g_play_sound_species = PET_SPECIES_CAT;
        }
        event_info_t event={0};
        event.event=event_iot_cmd;
        event.data.iot_data = IOT_CMD_PLAY_SOUND;
        smart_home_event_send(&event);
        printf("PlaySound: species=%s intent=%s\n",
               g_play_sound_species == PET_SPECIES_DOG ? "dog" : "cat",
               g_play_sound_intent);
      }
    }

    // 旧格式: {"command_name":"light_control", ...}
    cmd_name = cJSON_GetObjectItem(root, "command_name");
    if (cmd_name != NULL) {
      cmd_name_str = cJSON_GetStringValue(cmd_name);
      if (!strcmp(cmd_name_str, "light_control")) {
        set_light_state(root);
      } else if (!strcmp(cmd_name_str, "motor_control")) {
        set_motor_state(root);
      } else if (!strcmp(cmd_name_str, "auto_control")) {
        set_auto_state(root);
      }
    }
  }

  // Response deferred to main loop (avoid sync publish in callback)
  printf("Command processed\n");
  cJSON_Delete(root);
}

/***************************************************************
* 函数名称: wait_message
* 说    明: 等待信息
* 参    数: 无
* 返 回 值: 无
***************************************************************/
int wait_message() {
  uint8_t rec = MQTTYield(&client, 1000);
  if (rec != 0) {
    mqttConnectFlag = 0;
  }
  if (mqttConnectFlag == 0) {
    return 0;
  }
  return 1;
}

/***************************************************************
* 函数名称: mqtt_init
* 说    明: mqtt初始化 (HiveMQ 公共 Broker)
* 参    数: 无
* 返 回 值: 无
***************************************************************/
void mqtt_init() {
  int rc;

  printf("Starting MQTT (HiveMQ public broker)...\n");

  /* Close previous connection to prevent sock/mem leak */
  NetworkDisconnect(&network);
  MQTTDisconnect(&client);

begin:
  /*网络初始化*/
  NetworkInit(&network);
  /* 连接网络*/
  printf("NetworkConnect ...\n");
  NetworkConnect(&network, HOST_ADDR, 1883);
  printf("MQTTClientInit ...\n");
  /*MQTT客户端初始化*/
  MQTTClientInit(&client, &network, 2000, sendBuf, sizeof(sendBuf), readBuf,
                 sizeof(readBuf));

  MQTTString clientId = MQTTString_initializer;
  clientId.cstring = mqtt_devid;

  MQTTString userName = MQTTString_initializer;
  userName.cstring = mqtt_username;

  MQTTString password = MQTTString_initializer;
  password.cstring = mqtt_pwd;

  MQTTPacket_connectData data = MQTTPacket_connectData_initializer;
  data.clientID = clientId;
  data.username = userName;
  data.password = password;
  data.willFlag = 0;
  data.MQTTVersion = 4;
  data.keepAliveInterval = 60;
  data.cleansession = 1;

  printf("MQTTConnect (HiveMQ) ...\n");
  rc = MQTTConnect(&client, &data);
  if (rc != 0) {
    printf("MQTTConnect: %d\n", rc);
    NetworkDisconnect(&network);
    MQTTDisconnect(&client);
    osDelay(200);
    goto begin;
  }

  printf("MQTTSubscribe ...\n");
  rc = MQTTSubscribe(&client, subcribe_topic, 0, mqtt_message_arrived);
  if (rc != 0) {
    printf("MQTTSubscribe: %d\n", rc);
    osDelay(200);
    goto begin;
  }

  /* 订阅 ESP32 叫声感知节点的特征上报 */
  rc = MQTTSubscribe(&client, VOICE_FEAT_TOPIC, 0, mqtt_voice_feat_arrived);
  if (rc != 0) {
    printf("MQTTSubscribe(voice): %d\n", rc);
    /* 非致命: 叫声功能降级, 主链路继续 */
  }

    /* 订阅 ESP32 穿戴设备数据 */
    rc = MQTTSubscribe(&client, WEARABLE_TOPIC, 0, mqtt_wearable_arrived);
    if (rc != 0) {
        printf("MQTTSubscribe(wearable): %d\n", rc);
        /* 非致命: 穿戴功能降级, 回退本地传感器 */
    }

  mqttConnectFlag = 1;
  printf("MQTT connected to HiveMQ!\n");
}

/***************************************************************
* 函数名称: mqtt_voice_feat_arrived
* 说    明: 接收ESP32叫声特征 -> 主控端分类 -> 置待发布标志
*           (仅解析+推理, 发布延迟到主循环, 避免回调内同步publish)
***************************************************************/
void mqtt_voice_feat_arrived(MessageData *data) {
  cJSON *root = cJSON_ParseWithLength(data->message->payload,
                                      data->message->payloadlen);
  if (root == NULL) return;

  cJSON *feat_arr = cJSON_GetObjectItem(root, "feat");
  if (feat_arr && cJSON_IsArray(feat_arr) &&
      cJSON_GetArraySize(feat_arr) >= VOICE_FEAT_DIM) {
    float feat[VOICE_FEAT_DIM];
    for (int i = 0; i < VOICE_FEAT_DIM; i++) {
      cJSON *v = cJSON_GetArrayItem(feat_arr, i);
      feat[i] = (v && cJSON_IsNumber(v)) ? (float)v->valuedouble : 0.0f;
    }
    cJSON *seq_obj = cJSON_GetObjectItem(root, "seq");
    unsigned int seq = (seq_obj && cJSON_IsNumber(seq_obj))
                       ? (unsigned int)seq_obj->valueint : 0;
    voice_intent_process(feat, seq);
  }
  cJSON_Delete(root);
}

/***************************************************************
* 函数名称: mqtt_wearable_arrived
* 说    明: 接收ESP32穿戴设备数据 (心率/血氧/活动量)
*           存储到全局变量, 主循环优先使用远程数据
***************************************************************/
void mqtt_wearable_arrived(MessageData *data) {
    cJSON *root = cJSON_ParseWithLength(data->message->payload,
                                        data->message->payloadlen);
    if (root == NULL) return;

    cJSON *hr_obj = cJSON_GetObjectItem(root, "heartRate");
    if (hr_obj && cJSON_IsNumber(hr_obj)) {
        g_wearable_hr = (float)hr_obj->valuedouble;
    }

    cJSON *spo2_obj = cJSON_GetObjectItem(root, "spo2");
    if (spo2_obj && cJSON_IsNumber(spo2_obj)) {
        g_wearable_spo2 = (float)spo2_obj->valuedouble;
    }

    cJSON *act_obj = cJSON_GetObjectItem(root, "activity");
    if (act_obj && cJSON_IsNumber(act_obj)) {
        g_wearable_activity = act_obj->valueint;
    }

    g_wearable_fresh = 1;

    printf("Wearable: HR=%.1f SpO2=%.1f Act=%d\n",
           g_wearable_hr, g_wearable_spo2, g_wearable_activity);

    cJSON_Delete(root);
}

/***************************************************************
* 函数名称: publish_voice_intent
* 说    明: 主循环轮询调用: 有待发布的叫声意图则发布到 App
***************************************************************/
void publish_voice_intent(void) {
  voice_result_t r;
  if (!voice_intent_take_pending(&r)) return;
  if (mqttConnectFlag == 0) return;

  char payload[192];
  snprintf(payload, sizeof(payload),
           "{\"cmd\":\"petVoice\",\"intent\":\"%s\",\"text\":\"%s\","
           "\"conf\":%.2f,\"seq\":%u}",
           voice_intent_name(r.intent), voice_intent_text(r.intent),
           r.confidence, r.seq);

  MQTTMessage message;
  message.qos = QOS0;
  message.retained = 0;
  message.payload = payload;
  message.payloadlen = strlen(payload);
  if (MQTTPublish(&client, VOICE_INTENT_TOPIC, &message) != 0) {
    printf("VoiceIntent publish failed\n");
  } else {
    printf("VoiceIntent published: %s\n", payload);
    /* 自动触发 SU-03T 播放对应安抚/回应叫声 (仅已配置音频的意图) */
    {
      const char *intent_name = voice_intent_name(r.intent);
      /* 只有 happy 有音频文件 (index 11=dog, 12=cat), 其他意图跳过 */
      if (!strcmp(intent_name, "happy")) {
        su03t_play_pet_sound(
            g_play_sound_species == 1 ? "dog" : "cat",
            intent_name);
      }
    }
  }
}

/***************************************************************
* 函数名称: mqtt_is_connected
* 说    明: mqtt连接状态
* 参    数: 无
* 返 回 值: unsigned int 状态
***************************************************************/
unsigned int mqtt_is_connected() { return mqttConnectFlag; }

/***************************************************************
* 函数名称: send_path_to_mqtt
* 说    明: 上传离线记录的 GPS 路径到 MQTT
* 参    数: 无
* 返 回 值: 无
***************************************************************/
void send_path_to_mqtt(void)
{
    if (mqttConnectFlag == 0) { printf("Path upload blocked: MQTT not connected\n"); return; }

    int count = geofence_get_path_count();
    if (count == 0) { printf("Path upload blocked: no path points\n"); return; }

    static gps_point_t points[256];

    /* Chunked upload: PATH_CHUNK_SIZE points per message to avoid
     * overflowing the 1024-byte MQTT send buffer. */
    int remaining = count;
    int offset = 0;
    int uploaded = 0;

    while (remaining > 0) {
        int chunk = (remaining > PATH_CHUNK_SIZE) ? PATH_CHUNK_SIZE : remaining;
        geofence_get_path_range(points, offset, chunk);

        cJSON *root = cJSON_CreateObject();
        cJSON_AddStringToObject(root, "cmd", "pathData");
        cJSON *arr = cJSON_AddArrayToObject(root, "points");

        for (int i = 0; i < chunk; i++) {
            cJSON *pt = cJSON_CreateObject();
            cJSON_AddNumberToObject(pt, "lat", points[i].lat);
            cJSON_AddNumberToObject(pt, "lon", points[i].lon);
            cJSON_AddNumberToObject(pt, "ts",  points[i].timestamp);
            cJSON_AddItemToArray(arr, pt);
        }

        char *payload = cJSON_PrintUnformatted(root);
        if (payload == NULL) {
            printf("Path chunk: cJSON_PrintUnformatted failed\n");
            cJSON_Delete(root);
            break;
        }
        int payload_len = strlen(payload);
        printf("Path chunk: %d points, %d bytes\n", chunk, payload_len);

        MQTTMessage message;
        message.qos = 0;
        message.retained = 0;
        message.payload = payload;
        message.payloadlen = payload_len;

        int rc = MQTTPublish(&client, publish_topic, &message);
        if (rc == 0) {
            uploaded += chunk;
        } else {
            printf("Path chunk upload failed: %d\n", rc);
            cJSON_free(payload);
            cJSON_Delete(root);
            break;
        }

        cJSON_free(payload);
        cJSON_Delete(root);

        remaining -= chunk;
        offset += chunk;
        LOS_Msleep(100);  /* brief pause between chunks */
    }

    if (uploaded > 0) {
        printf("Path upload done: %d/%d points\n", uploaded, count);
        geofence_clear_path();
    }
}

/***************************************************************
* 函数名称: iot_wearable_data_available
* 说    明: 主循环调用: 检查是否有来自ESP32的新鲜穿戴数据
***************************************************************/
int iot_wearable_data_available(void) {
    return g_wearable_fresh;
}

/***************************************************************
* 函数名称: iot_get_wearable_data
* 说    明: 获取穿戴设备远程数据, 并清除新鲜标志
***************************************************************/
void iot_get_wearable_data(float *hr, float *spo2, int *activity) {
    if (hr)       *hr       = g_wearable_hr;
    if (spo2)     *spo2     = g_wearable_spo2;
    if (activity) *activity = g_wearable_activity;
    g_wearable_fresh = 0;
}
