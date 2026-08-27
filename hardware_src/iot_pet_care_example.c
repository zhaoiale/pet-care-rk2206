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

#include <math.h>
#include <stdio.h>
#include <stdbool.h>

#include "los_task.h"
#include "ohos_init.h"
#include "cmsis_os.h"
#include "config_network.h"
#include "smart_home.h"
#include "smart_home_event.h"
#include "su_03t.h"
#include "iot.h"
#include "lcd.h"
#include "picture.h"
#include "adc_key.h"
#include "anxiety_engine.h"
#include "hrv_analyzer.h"
#include "health_monitor.h"
#include "baseline_learner.h"
#include "drv_body_induction.h"
#include "drv_rgb_led.h"
#include "drv_beep.h"
#include "drv_hx711.h"
#include "drv_feeder.h"
#include "feed_scheduler.h"
#include "mpu6050.h"
#include "activity_monitor.h"
#include "max30102.h"
#include "atgm336h.h"
#include "geofence.h"
#include "cli.h"
#include "voice_intent.h"
#include "voice_adc.h"
#include "voice_feature.h"
#include "drv_mlx90614.h"

#define ROUTE_SSID      "MY_SW"          // WiFi账号
#define ROUTE_PASSWORD "12345678"       // WiFi密码

#define HX711_ENABLED        1
#define FEEDER_ENABLED         1
#define FEEDER_GPIO           GPIO0_PA5  // 投喂继电器GPIO (复用报警灯引脚，代码中未使用报警灯)
#define AUTO_COMFORT_ENABLED 1

#define MSG_QUEUE_LENGTH                                16
#define BUFFER_LEN                                      50

static bool g_sound_detected = false;

int g_hr_sim_enabled = 0;  // toggled by CLI: hrsim on/off

// 强制上报标志（由 App 刷新指令触发）
bool g_force_publish = false;

// 围栏标志（由 App setHome/getPath 指令触发）
bool g_pending_set_home = false;
bool g_pending_path_upload = false;

// 离线越界状态（用于回连后补发）
int g_last_geofence_status = GEOFENCE_INSIDE;
static bool g_was_offline_outside = false;

// 安抚超时计数，由主线程倒计时，音乐任务读取
uint64_t g_comfort_timeout = 0;  // absolute tick when comfort ends (LOS_TickCountGet, 1ms unit)


/***************************************************************
 * 函数名称: iot_thread
 * 说    明: iot线程
 * 参    数: 无
 * 返 回 值: 无
 ***************************************************************/
void iot_thread(void *args) {
  uint8_t mac_address[12] = {0x00, 0xdc, 0xb6, 0x90, 0x01, 0x00,0};

  char ssid[32]=ROUTE_SSID;
  char password[32]=ROUTE_PASSWORD;
  char mac_addr[32]={0};

  FlashDeinit();
  FlashInit();

  VendorSet(VENDOR_ID_WIFI_MODE, "STA", 3); // 配置为Wifi STA模式
  VendorSet(VENDOR_ID_MAC, mac_address, 6); // 多人同时做该实验，请修改各自不同的WiFi MAC地址
  VendorSet(VENDOR_ID_WIFI_ROUTE_SSID, ssid, sizeof(ssid));
  VendorSet(VENDOR_ID_WIFI_ROUTE_PASSWD, password,sizeof(password));

reconnect:
  SetWifiModeOff();
  int ret = SetWifiModeOn();
  if(ret != 0){
    printf("wifi connect failed,please check wifi config and the AP!\n");
    return;
  }
  mqtt_init();

  while (1) {
    if (!wait_message()) {
      goto reconnect;
    }
    LOS_Msleep(1);
  }
}


/***************************************************************
 * 函数名称: smart_home_thread
 * 说    明: 智慧家居主线程
 * 参    数: 无
 * 返 回 值: 无
 ***************************************************************/
void smart_home_thread(void *arg)
{
    e_iot_data iot_data = {0};

    /* Simulation auto-comfort state machine */
    static int  g_sim_comfort_phase = 0;  // 0=idle, 1=alarm, 2=comforting, 3+=recovered
    static int  g_sim_comfort_count = 0;
    static int  g_sim_breath_val = 10;
    static int  g_sim_breath_dir = 1;
    static int  g_sim_melody_idx = 0;

    i2c_dev_init();
    lcd_dev_init();
    motor_dev_init();
    light_dev_init();
    su03t_init();
    body_induction_dev_init();
    rgb_led_init();
    beep_dev_init();
    anxiety_engine_init();
    baseline_load_from_flash();
#if HX711_ENABLED
    hx711_init();
#endif
#if FEEDER_ENABLED
    feeder_dev_init(FEEDER_GPIO);
#endif
    feed_scheduler_init();
    feed_scheduler_load_from_flash();
    activity_monitor_init();
    max30102_init();
    mlx90614_init();
    atgm336h_init();
    geofence_init();
    geofence_load_from_flash();
    voice_adc_init();
    voice_feature_init();
    voice_adc_start();
    cli_register_commands();

    lcd_show_ui();

    int mqtt_send_counter = 0;
    uint32_t loop_ticks = 0;

    while(1)
    {
        event_info_t event_info = {0};
        //等待事件触发,如有触发,则立即处理对应事件,如未等到,则执行默认的代码逻辑,更新屏幕
        int ret = smart_home_event_wait(&event_info,1000);
        if(ret == LOS_OK){
            //收到指令
            printf("event recv %d ,%d\n",event_info.event,event_info.data.iot_data);
            switch (event_info.event)
            {
                case event_key_press:
                    smart_home_key_process(event_info.data.key_no);
                    break;
                case event_iot_cmd:
                    smart_home_iot_cmd_process(event_info.data.iot_data);
                    break;
                case event_su03t:
                    smart_home_su03t_cmd_process(event_info.data.su03t_data);
                    g_sound_detected = true;
                    break;
               default:break;
            }

        }

        double temp = 25.0, humi = 50.0, lum = 100.0;
        bool pir_state;

        sht30_read_data(&temp,&humi);
        bh1750_read_data(&lum);
        body_induction_get_state(&pir_state);
        activity_monitor_update();

        /* MLX90614 红外体温 */
        float body_temp = mlx90614_read_body_temp();

        // ---- MAX30102 心率血氧 ----
        float hr = 0, spo2 = 0;
        max30102_get_heart_rate(&hr, &spo2);

        // Periodic re-init when LED dies (power supply issue workaround)
        {
            static int stale_ticks = 0;
            static uint32_t last_reinit_at = 0;
            if (hr <= 0 && spo2 <= 0) {
                stale_ticks++;
            } else {
                stale_ticks = 0;
            }
            if (stale_ticks >= 60 && (loop_ticks - last_reinit_at) >= 60) {
                printf("MAX30102: stale for %ds, re-initializing...\n", stale_ticks);
                max30102_init();
                stale_ticks = 0;
                last_reinit_at = loop_ticks;
            }
        }

        // Simulation mode (CLI: hrsim on/off) — for demo when sensor absent
        if (g_hr_sim_enabled) {
            static int sim_seed = 0;
            sim_seed++;
            hr = 80.0f + 8.0f * sinf((float)sim_seed * 0.17f)
                 + 4.0f * sinf((float)sim_seed * 0.053f);
            spo2 = 97.5f + 1.2f * sinf((float)sim_seed * 0.091f);
        }

        // Wearable: prefer ESP32 remote data over local MAX30102
        if (iot_wearable_data_available()) {
            float whr, wspo2;
            int wact;
            iot_get_wearable_data(&whr, &wspo2, &wact);
            if (whr > 0)   hr   = whr;
            if (wspo2 > 0) spo2 = wspo2;
            iot_data.activity_level = wact;
        }

        // ---- ATGM336H GPS ----
        gps_data_t gps;
        atgm336h_get_data(&gps);

        // ---- Geofence check ----
        float geofence_dist = 0.0f;
        int geofence_status = geofence_check(gps.latitude, gps.longitude, &geofence_dist);
        g_last_geofence_status = geofence_status;

        // Periodic flash save: every 50 path points, skip on first iteration
        {
            static int last_saved_count = -1;
            int cur_count = geofence_get_path_count();
            if (last_saved_count < 0) last_saved_count = cur_count;
            if (cur_count - last_saved_count >= 50) {
                geofence_save_to_flash();
                last_saved_count = cur_count;
            }
        }

        // Handle pending setHome: use latest GPS fix
        if (g_pending_set_home && gps.latitude != 0.0f) {
            geofence_set_home(gps.latitude, gps.longitude);
            g_pending_set_home = false;
        }

        // Local alert when outside fence and offline
        if (geofence_status == GEOFENCE_OUTSIDE) {
            if (!mqtt_is_connected()) {
                g_was_offline_outside = true;
                // Local alert: red blink + buzzer chirp
                rgb_led_set(99, 0, 0);
                beep_set_state(true);
                LOS_Msleep(50);
                beep_set_state(false);
                rgb_led_off();
            }
        }

#if HX711_ENABLED
        // ---- HX711 食盆称重 ----
        static double g_food_weight = 0;
        static int g_hx711_log_counter = 0;
        g_food_weight = hx711_get_grams();
        lcd_set_food_weight(g_food_weight);

        g_hx711_log_counter++;
        if (g_hx711_log_counter >= 5) {
            g_hx711_log_counter = 0;
            printf("HX711: weight=%.1fg\n", g_food_weight);
        }
#endif

#if FEEDER_ENABLED
        feed_scheduler_tick(loop_ticks);
        feed_scheduler_check();
#endif

        // 焦虑引擎处理
        pet_env_data_t pet_env = {0};
        pet_env.temperature = temp;
        pet_env.humidity = humi;
        pet_env.illumination = lum;
        pet_env.body_detected = pir_state;
        pet_env.sound_detected = g_sound_detected || voice_intent_recent(60);
        pet_env.hour_of_day = (int)((loop_ticks / 1200) % 24);
        pet_env.activity_level = activity_get_level();
        pet_env.heart_rate = hr;
        pet_env.spo2 = spo2;
        pet_env.body_temp = body_temp;

        anxiety_result_t anxiety_result = {0};
        anxiety_engine_process(&pet_env, &anxiety_result);

        // ★ Anxiety simulation override (CLI: anxiety <0-100>)
        // Must run BEFORE comfort check so auto-comfort can trigger
        if (g_anxiety_sim) {
            int L = g_anxiety_sim_level;
            anxiety_result.anxiety_level = L;
            if (L >= 61)      anxiety_result.emotion = EMOTION_ANXIOUS;
            else if (L >= 36) anxiety_result.emotion = EMOTION_ALERT;
            else if (L >= 16) anxiety_result.emotion = EMOTION_CALM;
            else              anxiety_result.emotion = EMOTION_HAPPY;
            if (L >= 61) {
                anxiety_result.comfort_type = 3;
                anxiety_result.exceed_count = 3;
                anxiety_result.need_comfort = true;
            } else if (L >= 36) {
                anxiety_result.comfort_type = 1;
                anxiety_result.exceed_count = 1;
                anxiety_result.need_comfort = false;
            } else {
                anxiety_result.comfort_type = 0;
                anxiety_result.exceed_count = 0;
                anxiety_result.need_comfort = false;
            }
            // Heart-rate: 85 (happy) → 130 (anxious), linear interp
            hr = 80.0f + (float)L * 0.55f;
            // SpO2: 99 (happy) → 93 (anxious)
            spo2 = 99.0f - (float)L * 0.065f;
            g_sim_hr = hr;
            g_sim_spo2 = spo2;
            // Activity: 8 (happy) → 55 (anxious)
            anxiety_result.activity_level = (int)(8 + L * 0.50f);
            // HRV stress index: 12 (happy) → 72 (anxious)
            iot_data.hrv_stress = (int)(10 + L * 0.65f);
            if (iot_data.hrv_stress > 85) iot_data.hrv_stress = 85;

            // LED + beep: alarm→comfort→recovery state machine
            if (L >= 61) {
                if (g_sim_comfort_phase == 0) {
                    g_sim_comfort_phase = 1;
                } else if (g_sim_comfort_phase == 1) {
                    // Phase 1: brief alarm — 3 quick beeps (~0.8s total)
                    rgb_led_set(99, 1, 1);
                    for (int b = 0; b < 3; b++) {
                        beep_set_state(true);
                        beep_set_freq(660, 2);
                        LOS_Msleep(120);
                        beep_set_state(false);
                        LOS_Msleep(80);
                    }
                    g_sim_comfort_phase = 2;
                    g_sim_breath_val = 10;
                    g_sim_breath_dir = 1;

                } else if (g_sim_comfort_phase == 2) {
                    // Phase 2: continuous soothing Canon melody (~15s non-stop)
                    static const int notes[] = {
                        523, 659, 784,   // C chord ↑
                        440, 523, 659,   // Am chord ↑
                        392, 494, 587,   // G chord ↑
                        349, 440, 523,   // F chord ↑
                        392, 494, 587,   // G chord ↑
                        262, 330, 392,   // C chord ↓
                        330, 392, 440,   // Am (1st inv)
                        294, 370, 440,   // D (sus)
                    };
                    static const int durs[] = {
                        120, 120, 240,   // C: short-short-long
                        120, 120, 240,   // Am
                        120, 120, 240,   // G
                        120, 120, 240,   // F
                        120, 120, 240,   // G
                        120, 120, 240,   // C
                        120, 120, 240,   // Am
                        180, 180, 400,   // D sus → resolution
                    };
                    int n = sizeof(notes) / sizeof(notes[0]);

                    // Play 3 full cycles of the melody with LED breathing
                    for (int cyc = 0; cyc < 3; cyc++) {
                        beep_set_state(true);
                        for (int i = 0; i < n; i++) {
                            beep_set_freq(notes[i], 1);
                            LOS_Msleep(durs[i]);
                        }
                        // LED breath update between cycles
                        rgb_led_set(g_sim_breath_val, g_sim_breath_val / 3, 1);
                        g_sim_breath_val += g_sim_breath_dir * 20;
                        if (g_sim_breath_val >= 80) { g_sim_breath_val = 80; g_sim_breath_dir = -1; }
                        if (g_sim_breath_val <= 10) { g_sim_breath_val = 10; g_sim_breath_dir = 1; }
                    }
                    g_sim_comfort_phase = 3;   // → recovery
                } else {
                    // Phase 3+: recovery — anxiety drops, LED back to calm warm
                    rgb_led_set(99, 31, 1);
                    beep_set_state(false);
                    int recovered = L - (g_sim_comfort_phase - 2) * 35;
                    if (recovered < 15) recovered = 15;
                    anxiety_result.anxiety_level = recovered;
                    if (recovered >= 61)      anxiety_result.emotion = EMOTION_ANXIOUS;
                    else if (recovered >= 36) anxiety_result.emotion = EMOTION_ALERT;
                    else if (recovered >= 16) anxiety_result.emotion = EMOTION_CALM;
                    else                      anxiety_result.emotion = EMOTION_HAPPY;
                    g_sim_comfort_phase++;
                    if (g_sim_comfort_phase > 5) g_sim_comfort_phase = 5;
                }
                anxiety_result.need_comfort = (g_sim_comfort_phase == 2);
                anxiety_result.comfort_type = 3;
            } else {
                // L < 61: reset state machine, normal LED mapping
                g_sim_comfort_phase = 0;
                g_sim_comfort_count = 0;
                if (L >= 36) {
                    rgb_led_set(2, 2, 25);
                    beep_set_state(false);
                } else if (L >= 16) {
                    beep_set_state(false);
                } else {
                    rgb_led_set(99, 31, 1);
                    beep_set_state(false);
                }
            }
        }

        printf("[DEBUG] post-anxiety Lv=%d Cmf=%d\n", anxiety_result.anxiety_level, anxiety_result.comfort_type);

        // ---- Comfort feedback tracking ----
        static int  comfort_active = 0;
        static int  comfort_start_anxiety = 0;
        static int  comfort_start_type = 0;

        int comfort_on_now = anxiety_result.need_comfort
                          || (g_comfort_mode > 0 && LOS_TickCountGet() < g_comfort_timeout);
        int effective_type = (g_comfort_mode > 0)
                             ? g_comfort_mode : anxiety_result.comfort_type;

        if (comfort_on_now && !comfort_active) {
            comfort_start_anxiety = anxiety_result.anxiety_level;
            comfort_start_type = effective_type;
            comfort_active = 1;
        } else if (!comfort_on_now && comfort_active) {
            anxiety_engine_feedback(comfort_start_type,
                                    comfort_start_anxiety);
            comfort_active = 0;
        }

        // remote comfort override
        if (g_remote_comfort) {
            g_comfort_timeout = LOS_TickCountGet() + 20000;  // 20s real-time, independent of loop speed
            g_remote_comfort = false;
            // type 2: 触发 SU-03T 语音播报安抚语
            if (g_comfort_mode == COMFORT_TYPE_VOICE) {
                su03t_send_u8_msg(SU03T_VOICE_COMFORT, 1);
                printf("SU-03T comfort voice triggered (index %d)\n", SU03T_VOICE_COMFORT);
            }
            printf("Remote comfort started: type=%d, end_tick=%llu\n", g_comfort_mode, g_comfort_timeout);
        }

        // 安抚执行
        if (g_comfort_mode > 0 && LOS_TickCountGet() < g_comfort_timeout) {
            // 远程安抚进行中（覆盖焦虑引擎的安抚决策）
            static int breath_val = 10;
            static int breath_dir = 1;
            static int noise_idx = 0;
            int noise_freqs[] = {440, 480, 520, 560, 520, 480};
            int noise_duties[] = {  8,   9,  10,  11,  10,   9};

            static int voice_idx = 0;
            // 主人语音安抚旋律 (五声音阶, 舒缓不刺耳)
            int voice_melody[] = {523, 587, 659, 523, 659, 784, 659, 523};
            int voice_duties[] = {  8,   9,  10,   8,  10,  12,  10,   8};

            anxiety_result.need_comfort = true;
            anxiety_result.comfort_type = g_comfort_mode;

            switch (g_comfort_mode) {
                case 1:  // 灯光安抚 — RGB暖橙色缓慢明灭
                    beep_set_state(false);
                    rgb_led_set(breath_val, breath_val / 3, 1);
                    breath_val += breath_dir * 20;
                    if (breath_val >= 90) { breath_val = 90; breath_dir = -1; }
                    if (breath_val <= 10) { breath_val = 10; breath_dir = 1; }
                    break;
                case 2:  // 语音安抚 — 根据 audioSubType 细分
                    switch (g_audio_sub_type) {
                        case AUDIO_SUBTYPE_NOISE: {  // 舒缓音乐 — 由独立任务 comfort_melody_task 播放
                            static int noise_led_idx = 0;
                            int bright = 20 + (noise_led_idx % 8) * 6;
                            rgb_led_set(bright, bright / 4, 1);
                            noise_led_idx++;
                            break;
                        }
                        case AUDIO_SUBTYPE_MUSIC:   // 音乐
                            beep_set_state(true);
                            rgb_led_set(99, 31, 1);
                            beep_set_freq(voice_melody[voice_idx], voice_duties[voice_idx]);
                            voice_idx = (voice_idx + 1) % 8;
                            break;
                        case AUDIO_SUBTYPE_RECORD:  // 录音
                            beep_set_state(true);
                            rgb_led_set(99, 31, 1);
                            beep_set_freq(523, 8);
                            break;
                        default:
                            beep_set_state(true);
                            rgb_led_set(99, 31, 1);
                            beep_set_freq(voice_melody[voice_idx], voice_duties[voice_idx]);
                            voice_idx = (voice_idx + 1) % 8;
                            break;
                    }
                    break;
                case 3:  // 旧 type=3 (向后兼容) -> 等同白噪音
                    rgb_led_set(2, 2, 25);
                    beep_set_state(true);
                    beep_set_freq(noise_freqs[noise_idx], noise_duties[noise_idx]);
                    noise_idx = (noise_idx + 1) % 6;
                    break;
                default:
                    break;
            }

            if (LOS_TickCountGet() >= g_comfort_timeout) {
                g_comfort_mode = 0;
                rgb_led_off();
                beep_set_state(false);
                printf("Remote comfort finished\n");
            }
        }
#if AUTO_COMFORT_ENABLED
        else if (anxiety_result.need_comfort && !g_anxiety_sim) {
            // 焦虑引擎自动安抚
            switch (anxiety_result.comfort_type) {
                case 1:  // 灯光安抚 — 暖橙色柔光
                    rgb_led_set(99, 31, 1);
                    beep_set_state(false);
                    break;
                case 2:  // 语音安抚 (默认播音乐)
                    rgb_led_set(99, 31, 1);
                    beep_set_state(true);
                    break;
                case 3:  // 旧类型 -> 白噪音
                    rgb_led_set(2, 2, 25);
                    beep_set_state(true);
                    break;
                default:
                    break;
            }
        }
#endif
        else if (!g_anxiety_sim) {
            if (!get_light_state()) {
                rgb_led_off();
            }
            beep_set_state(false);
        }

        g_sound_detected = false;

        lcd_set_illumination(lum);
        lcd_set_temperature(temp);
        lcd_set_humidity(humi);
        lcd_set_anxiety(anxiety_result.anxiety_level, anxiety_result.comfort_type);
        lcd_set_activity(pir_state, g_sound_detected);
        if (mqtt_is_connected())
        {
            // 填充iot数据（每次循环都更新，但仅每5分钟上报一次，或由 App 刷新指令触发）
            iot_data.illumination = lum;
            iot_data.temperature = temp;
            iot_data.humidity = humi;
            iot_data.light_state = get_light_state();
            iot_data.motor_state = get_motor_state();

            iot_data.anxiety_level = anxiety_result.anxiety_level;
            iot_data.comfort_type = anxiety_result.comfort_type;
            iot_data.activity_level = anxiety_result.activity_level;
            iot_data.exceed_count = anxiety_result.exceed_count;
            {
                const char *emo_labels[] = {"高兴", "平静", "警觉", "焦虑"};
                snprintf(iot_data.emotion, sizeof(iot_data.emotion),
                         "%s", emo_labels[anxiety_result.emotion]);
            }
#if HX711_ENABLED
            iot_data.food_weight = g_food_weight;
#else
            iot_data.food_weight = 0;
#endif
            iot_data.food_eaten = 0;
            iot_data.heart_rate = hr;
            iot_data.spo2 = spo2;
            iot_data.gps_lat = gps.latitude;
            iot_data.gps_lon = gps.longitude;

            // Geofence status + path upload
            static bool first_connect = true;
            if (g_was_offline_outside || first_connect) {
                first_connect = false;
                if (geofence_get_path_count() > 0) {
                    g_pending_path_upload = true;
                }
                g_was_offline_outside = false;
            }
            // HRV stress index (from anxiety engine internals)
            // Skip when simulating — value already set by override block above
            if (!g_anxiety_sim) {
                hrv_result_t hrv_mqtt;
                hrv_analyzer_get_result(&hrv_mqtt);
                iot_data.hrv_stress = hrv_mqtt.valid
                                      ? hrv_mqtt.stress_index : 0;
            }

            // Health score evaluation
            {
                extern int g_play_sound_species;
                health_monitor_set_species(g_play_sound_species);
                iot_data.health_score = health_monitor_evaluate(
                    hr, spo2, iot_data.temperature, body_temp, iot_data.activity_level);
                iot_data.body_temp = body_temp;
            }

            // Path upload on demand
            if (g_pending_path_upload) {
                send_path_to_mqtt();
                g_pending_path_upload = false;
            }

            // 叫声意图: 有待发布的分类结果则推给 App
            publish_voice_intent();

            // 强制上报（App 刷新指令触发）
            if (g_force_publish) {
                send_msg_to_mqtt(&iot_data);
                mqtt_send_counter = 0;
                g_force_publish = false;
                printf("Force publish triggered by refresh command\n");
            } else {
                mqtt_send_counter++;
                if (mqtt_send_counter >= 5) {
                    send_msg_to_mqtt(&iot_data);
                    mqtt_send_counter = 0;
                }
            }

            lcd_set_network_state(true);
        }else{
            lcd_set_network_state(false);
        }

        lcd_show_ui();
	loop_ticks++;
    }
}

/***************************************************************
 * 函数名称: iot_pet_care_example
 * 说    明: 开机自启动调用函数
 * 参    数: 无
 * 返 回 值: 无
 ***************************************************************/
/***************************************************************
 * 函数名称: comfort_melody_task
 * 说    明: 独立蜂鸣器旋律任务，不受主循环打断，音乐连续无空窗
 * 参    数: 无
 * 返 回 值: 无
 ***************************************************************/
void comfort_melody_task(void *arg)
{
    (void)arg;

    /* Pachelbel Canon in D — 五声音阶 G A B D E */
    int melody[] = {
        659, 587, 659, 587, 659, 494, 392, 440,
        659, 587, 659, 587, 659, 494, 392, 440,
        587, 659, 587, 659, 440, 494, 392, 587,
        494, 587, 392, 440, 494, 392, 440, 392
    };
    int rhythm[] = {
        130, 130, 130, 130, 130, 130, 200, 200,
        130, 130, 130, 130, 130, 130, 200, 200,
        130, 130, 130, 130, 130, 130, 200, 200,
        130, 130, 130, 130, 150, 150, 200, 300
    };
    int melody_len = sizeof(melody) / sizeof(melody[0]);
    int note_idx = 0;

    while (1) {
        if (g_comfort_mode == COMFORT_TYPE_AUDIO &&
            g_audio_sub_type == AUDIO_SUBTYPE_NOISE &&
            LOS_TickCountGet() < g_comfort_timeout) {

            int dur = rhythm[note_idx];
            beep_set_state(true);
            beep_set_freq(melody[note_idx], 10);
            LOS_Msleep(dur);
            beep_set_state(false);
            LOS_Msleep(15);
            note_idx = (note_idx + 1) % melody_len;
        } else {
            note_idx = 0;
            LOS_Msleep(200);
        }
    }
}

void iot_pet_care_example()
{
    unsigned int thread_id_1;
    unsigned int thread_id_2;
    unsigned int thread_id_3;
    unsigned int thread_id_4;
    TSK_INIT_PARAM_S task_1 = {0};
    TSK_INIT_PARAM_S task_2 = {0};
    TSK_INIT_PARAM_S task_3 = {0};
    TSK_INIT_PARAM_S task_4 = {0};
    unsigned int ret = LOS_OK;

    smart_home_event_init();

    task_1.pfnTaskEntry = (TSK_ENTRY_FUNC)smart_home_thread;
    task_1.uwStackSize = 40960;
    task_1.pcName = "smart home thread";
    task_1.usTaskPrio = 24;

    ret = LOS_TaskCreate(&thread_id_1, &task_1);
    if (ret != LOS_OK)
    {
        printf("Falied to create task ret:0x%x\n", ret);
        return;
    }

    task_2.pfnTaskEntry = (TSK_ENTRY_FUNC)adc_key_thread;
    task_2.uwStackSize = 8192;
    task_2.pcName = "key thread";
    task_2.usTaskPrio = 24;
    ret = LOS_TaskCreate(&thread_id_2, &task_2);
    if (ret != LOS_OK)
    {
        printf("Falied to create task ret:0x%x\n", ret);
        return;
    }

    task_3.pfnTaskEntry = (TSK_ENTRY_FUNC)iot_thread;
    task_3.uwStackSize = 20480*5;
    task_3.pcName = "iot thread";
    task_3.usTaskPrio = 24;
    ret = LOS_TaskCreate(&thread_id_3, &task_3);
    if (ret != LOS_OK)
    {
        printf("Falied to create task ret:0x%x\n", ret);
        return;
    }

    task_4.pfnTaskEntry = (TSK_ENTRY_FUNC)comfort_melody_task;
    task_4.uwStackSize = 4096;
    task_4.pcName = "comfort melody";
    task_4.usTaskPrio = 20;  // 高于主线程(24)，确保旋律准时切换
    ret = LOS_TaskCreate(&thread_id_4, &task_4);
    if (ret != LOS_OK)
    {
        printf("Falied to create task ret:0x%x\n", ret);
        return;
    }
}

APP_FEATURE_INIT(iot_pet_care_example);
