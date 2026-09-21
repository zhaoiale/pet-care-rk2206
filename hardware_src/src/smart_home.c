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

#include "smart_home.h"

#include <stdio.h>
#include <stdbool.h>

#include "iot_errno.h"

#include "iot_pwm.h"
#include "iot_gpio.h"
#include "su_03t.h"
#include "iot.h"
#include "geofence.h"
#include "lcd.h"
#include "picture.h"
#include "adc_key.h"
#include "components.h"
#include "lcd.h"
#include "string.h"
#include "drv_feeder.h"
#include "max30102.h"
#include "voice_intent.h"
#include <math.h>

static bool auto_state = false;
static bool network_state = false;
int  g_anxiety_level = 0;
int  g_anxiety_sim = 0;        // 1 = simulation mode active
int  g_anxiety_sim_level = 0;  // target anxiety level for simulation
static int g_comfort_type = 0;
static bool g_pir_active = false;
static bool g_sound_active = false;
static double g_food_weight = 0;    // HX711 current weight (grams)
bool g_remote_comfort = false;
int  g_comfort_mode = 0;
int  g_feed_amount = 0;
int  g_audio_sub_type = 0;
int  g_play_sound_id = 0;
int  g_play_sound_species = PET_SPECIES_CAT;
char g_play_sound_intent[16] = "happy";
static double g_temperature = 25.5;
static double g_humidity = 60.0;
static double g_illumination = 1234.0;
float g_sim_hr = 0;      // simulated heart rate for LCD (set by anxiety sim)
float g_sim_spo2 = 0;    // simulated SpO2 for LCD

void light_menu_entry(lcd_menu_t *menu);
void comfort_menu_entry(lcd_menu_t *menu);

/* 安抚状态菜单 — 显示当前安抚模式 */
lcd_menu_t comfort_menu={
    .img={
        .img=img_sunny,
        .height=48,
        .width=48,
    },
    .is_selected=false,
    .text={
        .fc=LCD_GREEN,
        .bc=LCD_WHITE,
        .font_size=24,
        .name="Cmf:IDLE",
    },
    .enterFunc=comfort_menu_entry,
    .exitFunc=NULL,
    .base_x=100,
    .base_y=64,

};

/* 照明灯的菜单初始化数据*/
lcd_menu_t light_menu={
    .img={
        .img= img_light_off,
        .height=64,
        .width=64,
    },
    .is_selected=false,
    .text={
        .fc=LCD_MAGENTA,
        .bc=LCD_WHITE,
        .font_size=24,
        .name="Light:OFF",
    },
    .base_x=20,
    .base_y=64,
    .enterFunc=light_menu_entry,
    .exitFunc=NULL,
};

/* 温度面板的初始化数据*/
lcd_display_board_t temp_db={
    .img={
        .img= img_temp_normal,
        .height=48,
        .width=48,
    },
    .text={
        .fc=LCD_MAGENTA,
        .bc=LCD_WHITE,
        .font_size=24,
        .name="25.5°C",
    },
    .base_x=180,
    .base_y=64,
};

/* 湿度面板的初始化数据*/
lcd_display_board_t humi_db={
    .img={
        .img= img_humi,
        .height=48,
        .width=48,
    },
    .text={
        .fc=LCD_MAGENTA,
        .bc=LCD_WHITE,
        .font_size=24,
        .name="25.5°C",
    },
    .base_x=180,
    .base_y=120,
};

/* 亮度面板的初始化数据*/
lcd_display_board_t lum_db={
    .img={
        .img= img_lum,
        .height=48,
        .width=48,
    },
    .text={
        .fc=LCD_MAGENTA,
        .bc=LCD_WHITE,
        .font_size=24,
        .name="1234Lx",
    },
    .base_x=180,
    .base_y=174,
};
/* 所有的面板集合数组,方便遍历查询*/
lcd_display_board_t *lcd_dbs[] ={&temp_db,&humi_db,&lum_db};
/* 所有的菜单集合数组,方便遍历查询*/
lcd_menu_t *lcd_menus[] = {&light_menu, &comfort_menu};
/* 菜单的个数*/
static int lcd_menu_number =  sizeof(lcd_menus)/sizeof(lcd_menu_t *);
/* 菜单的当前选中索引,在数组中的位置*/
static int menu_select_index = 0;

//菜单左和右的处理,需要考虑菜单个数的边界
void lcd_menu_selected_move_left()
{
    if(menu_select_index > 0){
        menu_select_index--;
    }
}

void lcd_menu_selected_move_right()
{
    if(menu_select_index <lcd_menu_number-1){
        menu_select_index++;
    }
}

/**
 * @brief 照明灯菜单按下确认按键
 *
 * @param menu
 */
void light_menu_entry(lcd_menu_t *menu)
{
    int light_state = get_light_state();
    if(light_state)
    {
        light_set_state(false);
        lcd_set_light_state(false);
    }else{
        light_set_state(true);
        lcd_set_light_state(true);
    }
}
/**
 * @brief  安抚菜单按下确认按键 — 手动触发安抚
 *
 * @param menu
 */
void comfort_menu_entry(lcd_menu_t *menu)
{
    // 预留：手动安抚切换，后续可扩展为MQTT远程安抚触发
}


/***************************************************************
* 函数名称: lcd_dev_init
* 说    明: lcd初始化
* 参    数: 无
* 返 回 值: 无
***************************************************************/
void lcd_dev_init(void)
{
    lcd_init();
    lcd_fill(0, 0, LCD_W, LCD_H, LCD_WHITE);
}

/**
 * @brief 按键处理函数
 *
 * @param key_no 按键号
 */
void smart_home_key_process(int key_no)
{
    printf("smart_home_key_process:%d\n",key_no);
    if(key_no == KEY_UP){

    }else if(key_no == KEY_DOWN){
        lcd_menu_entry(lcd_menus[menu_select_index]);

    }else if(key_no == KEY_LEFT){

        lcd_menu_selected_move_left();
    }else if(key_no == KEY_RIGHT){
        lcd_menu_selected_move_right();
    }
}
/**
 * @brief 物联网的指令处理函数
 *
 * @param iot_cmd iot的指令
 */
void smart_home_iot_cmd_process(int iot_cmd)
{
    switch (iot_cmd)
    {
        case IOT_CMD_LIGHT_ON:
            light_set_state(true);
            lcd_set_light_state(true);
            g_force_publish = true;
            break;
        case IOT_CMD_LIGHT_OFF:
            light_set_state(false);
            lcd_set_light_state(false);
            g_force_publish = true;
            break;
        case IOT_CMD_MOTOR_ON:
            motor_set_state(true);
            lcd_set_motor_state(true);
            g_force_publish = true;
            break;
        case IOT_CMD_MOTOR_OFF:
            motor_set_state(false);
            lcd_set_motor_state(false);
            g_force_publish = true;
            break;
        case IOT_CMD_REFRESH:
            g_force_publish = true;
            printf("Refresh event: force publish flag set\n");
            break;
        case IOT_CMD_COMFORT:
            g_remote_comfort = true;
            g_force_publish = true;
            printf("Remote comfort: flag set, type=%d\n", g_comfort_mode);
            break;
        case IOT_CMD_FEED:
            if (g_feed_amount > 2000) g_feed_amount = 2000;  // 上限2000g
            if (g_feed_amount <= 0) g_feed_amount = 50;
            printf("Feed command: %dg\n", g_feed_amount);
            feeder_feed_grams((unsigned int)g_feed_amount);
            printf("[FEEDER] done, %dg\n", g_feed_amount);
            g_force_publish = true;
            break;
        case IOT_CMD_SET_HOME:
            printf("Geofence: set home command from App\n");
            {
                float lat, lon;
                geofence_get_home(&lat, &lon);
                extern bool g_pending_set_home;
                g_pending_set_home = true;
            }
            g_force_publish = true;
            break;
        case IOT_CMD_GET_PATH:
            printf("Geofence: get path command from App\n");
            {
                extern bool g_pending_path_upload;
                g_pending_path_upload = true;
            }
            g_force_publish = true;
            break;
        case IOT_CMD_PLAY_SOUND:
            printf("Play sound command: species=%s intent=%s\n",
                   g_play_sound_species == PET_SPECIES_DOG ? "dog" : "cat",
                   g_play_sound_intent);
            su03t_play_pet_sound(
                g_play_sound_species == PET_SPECIES_DOG ? "dog" : "cat",
                g_play_sound_intent);
            g_force_publish = true;
            break;
    }
}

/**
 * @brief 语音管家发出的指令
 *
 * @param su03t_cmd 语音管家的指令
 */
void smart_home_su03t_cmd_process(int su03t_cmd)
{
    switch (su03t_cmd)
    {
        case light_state_on:
            light_set_state(true);
            lcd_set_light_state(true);
            break;
        case light_state_off:
            light_set_state(false);
            lcd_set_light_state(false);
            break;
        case motor_state_on:
            motor_set_state(true);
            lcd_set_motor_state(true);
            break;
        case motor_state_off:
            motor_set_state(false);
            lcd_set_motor_state(false);
            break;
        case temperature_get:
        {
            double temp, humi;
            sht30_read_data(&temp, &humi);
            int32_t temp_tenths = (int32_t)(temp * 10);
            su03t_send_u8_msg(SU03T_VOICE_TEMP, temp_tenths);
            printf("[SU-03T] Temperature query -> %.1f C (%d)\n", temp, temp_tenths);
        }
            break;
        case humidity_get:
        {
            double temp, humi;
            sht30_read_data(&temp, &humi);
            int32_t humi_tenths = (int32_t)(humi * 10);
            su03t_send_u8_msg(SU03T_VOICE_HUMI, humi_tenths);
            printf("[SU-03T] Humidity query -> %.1f %% (%d)\n", humi, humi_tenths);
        }
            break;
        case illumination_get:
        {
            double lum;
            bh1750_read_data(&lum);
            su03t_send_u8_msg(SU03T_VOICE_LUM, (int32_t)lum);
            printf("[SU-03T] Illumination query -> %.0f Lx\n", lum);
        }
            break;
        case anxiety_get:
        {
            su03t_send_u8_msg(SU03T_VOICE_ANXIETY, g_anxiety_level);
            printf("[SU-03T] Anxiety query -> %d\n", g_anxiety_level);
        }
            break;
        case heart_rate_get:
        {
            float hr, spo2;
            max30102_get_heart_rate(&hr, &spo2);
            su03t_send_u8_msg(SU03T_VOICE_HEART, (int32_t)hr);
            printf("[SU-03T] Heart rate query -> %d BPM\n", (int)hr);
        }
            break;
        case feed_start:
        {
            feeder_feed_grams(50);
            su03t_send_u8_msg(SU03T_VOICE_FEED_DONE, 1);
            extern bool g_force_publish;
            g_force_publish = true;
            printf("[SU-03T] Voice feed triggered, 50g\n");
        }
            break;
        default:
            break;
    }
}


/***************************************************************
* 函数名称: lcd_show_ui
* 说    明: 智宠管家竞赛仪表盘 — 深色主题，核心数据突出
* 参    数: 无
* 返 回 值: 无
***************************************************************/
void lcd_show_ui(void)
{
    char buf[48];
    extern int g_last_geofence_status;

    // === Background: dark navy theme ===
    lcd_fill(0, 0, LCD_W - 1, LCD_H - 1, LCD_DARKBLUE);

    // === Title bar (y=0, h=28) ===
    lcd_fill(0, 0, LCD_W - 1, 28, LCD_BLACK);
    lcd_show_text(8, 4, "PetCare", LCD_WHITE, LCD_BLACK, 24, 0);
    lcd_show_picture(284, 0, 28, 28, network_state ? img_wifi_on : img_wifi_off);
    lcd_draw_line(0, 28, LCD_W - 1, 28, LCD_GRAY);

    // === Row 1: Core metrics (y=30, h=44) — Anxiety + Health, large numbers ===
    // Card A: Anxiety
    lcd_fill(4, 32, 156, 74, LCD_BLACK);
    lcd_draw_rectangle(4, 32, 156, 74, LCD_DARKBLUE);
    lcd_show_text(12, 34, "Anxiety", LCD_LIGHTBLUE, LCD_BLACK, 16, 0);
    sprintf(buf, "%d", g_anxiety_level);
    lcd_show_string(12, 52, (uint8_t *)buf, LCD_WHITE, LCD_BLACK, 24, 0);
    {
        char *anx_label;
        uint16_t anx_fc;
        if (g_anxiety_level >= 61)      { anx_label = "Anxious"; anx_fc = LCD_RED; }
        else if (g_anxiety_level >= 36) { anx_label = "Alert"; anx_fc = LCD_BRRED; }
        else if (g_anxiety_level >= 16) { anx_label = "Calm"; anx_fc = LCD_GREEN; }
        else                            { anx_label = "Happy"; anx_fc = LCD_GREEN; }
        lcd_show_text(52, 52, anx_label, anx_fc, LCD_BLACK, 16, 0);
    }

    // Card B: Health + HR
    {
        extern int g_hr_sim_enabled;
        float hr, spo2;
        if (g_hr_sim_enabled) {
            static int sim_seed = 0;
            sim_seed++;
            hr = 80.0f + 8.0f * sinf((float)sim_seed * 0.17f)
                 + 4.0f * sinf((float)sim_seed * 0.053f);
            spo2 = 97.5f + 1.2f * sinf((float)sim_seed * 0.091f);
        } else if (g_anxiety_sim) {
            hr   = g_sim_hr;
            spo2 = g_sim_spo2;
        } else {
            max30102_get_heart_rate(&hr, &spo2);
        }
        lcd_fill(164, 32, 316, 74, LCD_BLACK);
        lcd_draw_rectangle(164, 32, 316, 74, LCD_DARKBLUE);
        lcd_show_text(172, 34, "HR/SpO2", LCD_LIGHTBLUE, LCD_BLACK, 16, 0);
        if (hr > 0 && spo2 > 0) {
            sprintf(buf, "%d %d%%", (int)hr, (int)spo2);
        } else if (hr > 0) {
            sprintf(buf, "%d --%%", (int)hr);
        } else {
            sprintf(buf, "-- --%%");
        }
        lcd_show_string(172, 52, (uint8_t *)buf, LCD_WHITE, LCD_BLACK, 24, 0);
    }

    // === Row 2: Environment strip (y=78, h=26) ===
    lcd_fill(4, 78, 316, 102, LCD_BLACK);
    lcd_draw_rectangle(4, 78, 316, 102, LCD_DARKBLUE);
    lcd_show_text(12, 80, "Temp", LCD_LIGHTBLUE, LCD_BLACK, 16, 0);
    sprintf(buf, "%.1fC", g_temperature);
    lcd_show_text(48, 80, buf, LCD_WHITE, LCD_BLACK, 16, 0);

    lcd_show_text(108, 80, "Hum", LCD_LIGHTBLUE, LCD_BLACK, 16, 0);
    sprintf(buf, "%.1f%%", g_humidity);
    lcd_show_text(144, 80, buf, LCD_WHITE, LCD_BLACK, 16, 0);

    lcd_show_text(210, 80, "Lux", LCD_LIGHTBLUE, LCD_BLACK, 16, 0);
    sprintf(buf, "%.0fLx", g_illumination);
    lcd_show_text(246, 80, buf, LCD_WHITE, LCD_BLACK, 16, 0);

    // === Row 3: Voice intent + Geofence (y=106, h=28) ===
    lcd_fill(4, 106, 316, 132, LCD_BLACK);
    lcd_draw_rectangle(4, 106, 316, 132, LCD_DARKBLUE);
    lcd_show_text(12, 108, "Voice", LCD_LIGHTBLUE, LCD_BLACK, 16, 0);
    {
        voice_intent_t vi = voice_intent_last();
        if (vi != VOICE_INTENT_UNKNOWN) {
            lcd_show_text(80, 108, (char *)voice_intent_name(vi), LCD_YELLOW, LCD_BLACK, 16, 0);
        } else {
            lcd_show_text(80, 110, "--", LCD_GRAY, LCD_BLACK, 12, 0);
        }
    }

    lcd_show_text(220, 108, "Geo", LCD_LIGHTBLUE, LCD_BLACK, 16, 0);
    lcd_show_text(256, 108,
        (g_last_geofence_status == 1) ? "OUT!" : "Home",
        (g_last_geofence_status == 1) ? LCD_RED : LCD_GREEN,
        LCD_BLACK, 16, 0);

    // === Row 4: Comfort status + Food (y=136, h=28) ===
    lcd_fill(4, 136, 316, 162, LCD_BLACK);
    lcd_draw_rectangle(4, 136, 316, 162, LCD_DARKBLUE);
    lcd_show_text(12, 138, "Comfort", LCD_LIGHTBLUE, LCD_BLACK, 16, 0);
    {
        char *cmf;
        uint16_t cmf_c;
        switch (g_comfort_type) {
            case 1:  cmf = "Light";  cmf_c = LCD_BLUE; break;
            case 2:
                switch (g_audio_sub_type) {
                    case 1:  cmf = "WhiteN";   cmf_c = LCD_BLUE; break;
                    case 2:  cmf = "PetSnd";   cmf_c = LCD_MAGENTA; break;
                    default: cmf = "Voice";     cmf_c = LCD_BLUE; break;
                }
                break;
            default: cmf = "Idle"; cmf_c = LCD_GREEN; break;
        }
        lcd_show_text(76, 138, cmf, cmf_c, LCD_BLACK, 16, 0);
    }

    lcd_show_text(180, 138, "Food", LCD_LIGHTBLUE, LCD_BLACK, 16, 0);
    if (g_food_weight > 0) {
        sprintf(buf, "%.0fg", g_food_weight);
        lcd_show_text(216, 138, buf, LCD_WHITE, LCD_BLACK, 16, 0);
    } else {
        lcd_show_text(216, 140, "--", LCD_GRAY, LCD_BLACK, 12, 0);
    }

    // === Row 5: Activity indicators (y=166, h=24) ===
    lcd_fill(4, 166, 316, 188, LCD_BLACK);
    lcd_draw_rectangle(4, 166, 316, 188, LCD_DARKBLUE);
    lcd_show_text(12, 168, "PIR", LCD_LIGHTBLUE, LCD_BLACK, 16, 0);
    lcd_show_text(52, 168,
        g_pir_active ? "Y" : "N",
        g_pir_active ? LCD_RED : LCD_GREEN, LCD_BLACK, 16, 0);

    lcd_show_text(84, 168, "Sound", LCD_LIGHTBLUE, LCD_BLACK, 16, 0);
    lcd_show_text(140, 168,
        g_sound_active ? "Y" : "N",
        g_sound_active ? LCD_RED : LCD_GREEN, LCD_BLACK, 16, 0);

    lcd_show_text(180, 170, "WiFi", LCD_LIGHTBLUE, LCD_BLACK, 12, 0);
    lcd_show_text(210, 168,
        network_state ? "OK" : "OFF",
        network_state ? LCD_GREEN : LCD_RED, LCD_BLACK, 16, 0);

}

/***************************************************************
* 函数名称: lcd_set_temperature
* 说    明: 设置温度显示
* 参    数: double temperature 温度
* 返 回 值: 无
***************************************************************/
void lcd_set_temperature(double temperature)
{
    g_temperature = temperature;
    sprintf(temp_db.text.name, "%.01f℃ ", temperature);
    /* 对温度做高温和正常的区分*/
    if(temperature > 35)
    {
        temp_db.text.fc = LCD_RED;
        temp_db.img.img = img_temp_high;
    }
    else
    {
       temp_db.text.fc = LCD_MAGENTA;
       temp_db.img.img = img_temp_normal;
    }
}

/***************************************************************
* 函数名称: lcd_set_humidity
* 说    明: 设置湿度显示
* 参    数: double humidity 湿度
* 返 回 值: 无
***************************************************************/
void lcd_set_humidity(double humidity)
{
    g_humidity = humidity;
    sprintf(humi_db.text.name, "%.01f%% ", humidity);

}

/***************************************************************
* 函数名称: lcd_set_illumination
* 说    明: 设置光照强度显示
* 参    数: double illumination 光照强度
* 返 回 值: 无
***************************************************************/
void lcd_set_illumination(double illumination)
{
    g_illumination = illumination;
    sprintf(lum_db.text.name, "%.01fLx ", illumination);

}

void lcd_set_network_state(int state){
    network_state = state;
}

/***************************************************************
* 函数名称: lcd_set_light_state
* 说    明: 设置灯状态显示
* 参    数: bool state true：显示"打开" false：显示"关闭"
* 返 回 值: 无
***************************************************************/
void lcd_set_light_state(bool state)
{

    strcpy(light_menu.text.name,state? "Light:ON" :"Light:OFF");
    light_menu.img.img = state? img_light_on : img_light_off;
}

/***************************************************************
* 函数名称: lcd_set_motor_state
* 说    明: 设置电机状态显示
* 参    数: bool state true：显示"打开" false：显示"关闭"
* 返 回 值: 无
***************************************************************/
void lcd_set_motor_state(bool state)
{
    // 在宠物关怀系统中，电机可控制投喂/窗帘等
    strcpy(comfort_menu.text.name, state ? "Motor:ON" : "Motor:OFF");
}

/***************************************************************
* 函数名称: lcd_set_food_weight
* 说    明: 更新食盆重量和食量显示
* 参    数: weight_grams 当前重量(g), eaten_grams 宠物已食量(g)
* 返 回 值: 无
***************************************************************/
void lcd_set_food_weight(double weight_grams)
{
    g_food_weight = weight_grams;
}

/***************************************************************
* 函数名称: lcd_set_auto_state
* 说    明: 设置自动模式状态显示
* 参    数: bool state true：显示"打开" false：显示"关闭"
* 返 回 值: 无
***************************************************************/
void lcd_set_auto_state(bool state)
{



    // if (state)
    // {
    //     lcd_show_chinese(77, 204, "开启", LCD_RED, LCD_WHITE, 24, 0);
    // }
    // else
    // {
    //     lcd_show_chinese(77, 204, "关闭", LCD_RED, LCD_WHITE, 24, 0);
    // }
}

/***************************************************************
* 函数名称: lcd_set_anxiety
* 说    明: 更新焦虑等级和安抚类型显示
* 参    数: level 焦虑指数(0-100), comfort_type 安抚类型(0-3)
* 返 回 值: 无
***************************************************************/
void lcd_set_anxiety(int level, int comfort_type)
{
    g_anxiety_level = level;
    g_comfort_type = comfort_type;
}

/***************************************************************
* 函数名称: lcd_set_activity
* 说    明: 更新PIR活动和叫声检测状态
* 参    数: pir_active PIR检测到活动, sound_detected 检测到叫声
* 返 回 值: 无
***************************************************************/
void lcd_set_activity(bool pir_active, bool sound_detected)
{
    g_pir_active = pir_active;
    g_sound_active = sound_detected;
}
