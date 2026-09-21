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

#ifndef __SMART_HOME_H__
#define __SMART_HOME_H__

#include <stdint.h>
#include <stdbool.h>

extern bool g_force_publish;
extern bool g_remote_comfort;
extern int  g_comfort_mode;
extern int  g_feed_amount;
extern int  g_anxiety_level;
extern int  g_audio_sub_type;
extern int  g_play_sound_id;
extern int  g_play_sound_species;
extern char g_play_sound_intent[16];  /* "hungry"/"happy"/"warning"/"lonely"/"play"/"calm" */
extern int  g_anxiety_sim;
extern int  g_anxiety_sim_level;
extern float g_sim_hr;
extern float g_sim_spo2;

void i2c_dev_init(void);
void bh1750_read_data(double *dat);
void sht30_read_data(double *temp, double *humi);

void lcd_dev_init(void);
void lcd_show_ui(void);
void lcd_set_temperature(double temperature);
void lcd_set_humidity(double humidity);
void lcd_set_illumination(double illumination);
void lcd_set_light_state(bool state);
void lcd_set_motor_state(bool state);
void lcd_set_auto_state(bool state);
void lcd_set_anxiety(int level, int comfort_type);
void lcd_set_activity(bool pir_active, bool sound_detected);
void lcd_set_food_weight(double weight_grams);

void smart_home_su03t_cmd_process(int su03t_cmd);
void smart_home_iot_cmd_process(int iot_cmd);
void smart_home_key_press_process(uint8_t key_no);

#endif
