# 智宠管家 — 宠物异常行为感知与主动关怀系统

> 2024 全国大学生嵌入式芯片与系统设计竞赛 | 基于 OpenHarmony RK2206

## 项目结构

```
PET/
├── hardware_src/         # 硬件固件源码 (RK2206)
│   ├── iot_pet_care_example.c  # 主程序入口
│   ├── BUILD.gn           # GN 构建配置
│   ├── src/               # 模块源码 (20个)
│   └── include/           # 模块头文件 (27个)
├── entry/                 # HarmonyOS App 源码
├── build/                 # App 构建产物
└── README.md
```

---

## 一、硬件部分

### 1.1 主控芯片

| 项目 | 参数 |
|---|---|
| 芯片型号 | **RK2206** (瑞芯微) |
| 内核 | Cortex-M4 @ 200MHz |
| 操作系统 | OpenHarmony LiteOS-M |
| Flash | 8MB SPI NOR Flash |
| RAM | 内置 SRAM |

### 1.2 传感器与执行器清单

| 序号 | 模块 | 型号 | 通信接口 | 功能 |
|---|---|---|---|---|
| 1 | 温湿度 | SHT30 | I2C (0x44) | 环境温湿度采集 |
| 2 | 光照 | BH1750 | I2C (0x23) | 环境光照强度 |
| 3 | 心率血氧 | MAX30102 | I2C (0x57) | PPG 脉搏波心率/血氧 |
| 4 | 六轴姿态 | MPU6050 | I2C (0x68) | 加速度计+陀螺仪 |
| 5 | GPS+北斗 | ATGM336H | UART0 (9600bps) | 定位+轨迹记录 |
| 6 | 称重 | HX711 | GPIO (PB0/PB1) | 24bit ADC 食盆称重 |
| 7 | 人体感应 | HC-SR501 | GPIO (PA3) | 宠物靠近检测 |
| 8 | 离线语音 | SU-03T | UART2 (115200bps) | 中文离线语音识别 |
| 9 | LCD 显示屏 | 2.8" TFT | SPI (ESPI0_M1) | 320×240 数据展示 |
| 10 | RGB LED | WS2812 | GPIO | 情绪状态氛围灯 |
| 11 | 蜂鸣器 | 有源蜂鸣器 | GPIO | 声音安抚/告警 |
| 12 | 投喂电机 | 直流减速电机 | GPIO (PA5) + 继电器 | 定量投喂 |

### 1.3 引脚分配表

| GPIO | 功能 | 方向 | 说明 |
|---|---|---|---|
| PA3 | 人体感应 PIR | IN | HC-SR501 数字输出 |
| PA4 | LCD DC | OUT | 数据/命令切换 |
| PA5 | 投喂继电器 | OUT | 低电平吸合电机 |
| PB0 | HX711 DOUT | IN | 称重数据输入 |
| PB1 | HX711 SCK | OUT | 称重时钟输出 |
| PB6 | GPS RX | IN | UART0 接收 |
| PB7 | GPS TX | OUT | UART0 发送 |
| B2 | SU-03T RX | IN | UART2 接收语音指令 |
| B3 | SU-03T TX | OUT | UART2 发送语音播报 |
| PC0 | LCD CS | OUT | SPI 片选 |
| PC1 | LCD CLK | OUT | SPI 时钟 |
| PC2 | LCD MOSI | OUT | SPI 数据 |
| PC3 | LCD RES | OUT | 复位 |

### 1.4 接线图速查

```
RK2206 开发板                  外接模块
═══════════════                ════════════
I2C0 (共用总线)  ├─ SHT30  (VCC/GND/SCL/SDA)
                 ├─ BH1750 (VCC/GND/SCL/SDA)
                 ├─ MAX30102 (VIN/GND/SCL/SDA/INT/RD)
                 └─ MPU6050 (VCC/GND/SCL/SDA)

SPI0 (ESPI0_M1)  ─── LCD     (CS/CLK/MOSI/RES/DC + VCC/GND)
UART0 (EUART0_M0) ─── GPS     (TX/RX + VCC/GND)
UART2 (EUART2_M1) ─── SU-03T  (RX/TX + VCC/GND)
PB0/PB1          ─── HX711   (DOUT/SCK + VCC/GND)
PA5              ─── 继电器   (IN + 电机电源)
PA3              ─── HC-SR501 (OUT + VCC/GND)
```

### 1.5 电源要求

| 模块 | 电压 |
|---|---|
| RK2206 开发板 | 5V (USB) |
| HX711 + 称重传感器 | 3.3V |
| GPS ATGM336H | 3.3V |
| SU-03T 语音模块 | 5V |
| 投喂电机 | 12V (独立电源，继电器隔离) |

---

## 二、软件部分

### 2.1 固件架构 (hardware_src/)

```
主循环 (~3s/周期)
  │
  ├── 传感器采集层
  │   ├── sht30_read_data()      温湿度
  │   ├── bh1750_read_data()     光照
  │   ├── max30102_get_heart_rate()  心率血氧
  │   ├── atgm336h_get_data()    GPS 定位
  │   ├── hx711_get_grams()      称重
  │   ├── body_induction_get_state()  人体感应
  │   └── activity_monitor_update()  活动量 (MPU6050)
  │
  ├── 焦虑引擎
  │   ├── baseline_learner      24h 分桶自适应基线
  │   ├── hrv_analyzer          HRV 压力指数 (SD2/SD1)
  │   ├── anxiety_engine        六维 Z-score + 马氏距离融合
  │   └── 输出: 0-100 焦虑指数 + 情绪标签
  │
  ├── 安抚执行
  │   ├── RGB LED 灯光安抚
  │   ├── 蜂鸣器 声音安抚
  │   └── SU-03T 语音安抚
  │
  ├── GPS 电子围栏
  │   ├── geofence_check()      100m 半径越界检测
  │   ├── geofence_save_to_flash()  离线轨迹存储
  │   └── send_path_to_mqtt()   轨迹分批上传
  │
  ├── 定量投喂
  │   ├── feed_scheduler        每日定时投喂计划
  │   └── feeder_feed_grams()   HX711 闭环克数控制
  │
  ├── MQTT 通信 (HiveMQ 公共 Broker)
  │   ├── send_msg_to_mqtt()    每5分钟上报传感器数据
  │   └── mqtt_message_arrived()  接收 App 远程指令
  │
  └── Flash 持久化
      ├── 0x7F0000 GPS 路径 (256 点环形缓冲)
      ├── 0x7F1000 投喂计划 (8 条定时任务)
      └── 0x7F2000 基线数据 (24 桶 × 6 维 + 协方差矩阵)
```

### 2.2 核心源码文件说明

| 文件 | 功能 |
|---|---|
| `iot_pet_care_example.c` | 主程序: 线程创建、主循环、MQTT 数据打包 |
| `src/anxiety_engine.c` | 焦虑引擎: Z-score + 马氏距离 + Sigmoid 映射 |
| `src/baseline_learner.c` | 基线学习: 24h 分桶 EWMA 在线学习 |
| `src/hrv_analyzer.c` | HRV 分析: 基于 IBI 的心率变异性分析 |
| `src/max30102.c` | MAX30102: PPG 心率血氧采集与峰值检测 |
| `src/drv_hx711.c` | HX711: 24bit ADC 称重 + 中值滤波 |
| `src/drv_feeder.c` | 投喂电机: 继电器控制 + HX711 闭环克数 |
| `src/feed_scheduler.c` | 投喂计划: 定时触发 + Flash 持久化 |
| `src/geofence.c` | 电子围栏: Haversine 距离 + 轨迹记录 |
| `src/atgm336h.c` | GPS 解析: NMEA 0183 协议 (GPRMC/GPGGA) |
| `src/su_03t.c` | SU-03T: 离线语音识别驱动 |
| `src/iot.c` | MQTT 客户端: HiveMQ 连接/订阅/发布 |
| `src/smart_home.c` | 智能家居: LCD 显示、语音播报、事件处理 |
| `src/cli.c` | 串口命令: hr/焦虑/投喂/路径/GPS 调试 |
| `src/lcd.c` | LCD 驱动: SPI ILI9341 320×240 |
| `src/mpu6050.c` | MPU6050: 加速度计初始化 |
| `src/activity_monitor.c` | 活动量: 加速度模长积分 + EMA 滤波 |
| `src/drv_sensors.c` | SHT30 + BH1750 驱动 |
| `src/drv_rgb_led.c` | WS2812 RGB LED 驱动 |
| `src/drv_beep.c` | 蜂鸣器驱动 |
| `src/drv_body_induction.c` | HC-SR501 人体感应 |

### 2.3 关键算法参数

| 参数 | 数值 |
|---|---|
| 基线分桶 | 24 小时独立 EWMA (α=0.05) |
| 异常阈值 | Z-score > 2.5 |
| 情绪分级 | 高兴 0-15 / 平静 16-35 / 警觉 36-60 / 焦虑 61-100 |
| 安抚策略 | ε-greedy (探索率 10%, α=0.1) |
| 投喂默认量 | 50g/餐 |

### 2.4 App 源码 (entry/)

- 框架: HarmonyOS ArkUI (ArkTS)
- MQTT 通信: `entry/src/main/ets/mqtt/MqttService.ets`
- 主页面: `entry/src/main/ets/pages/DashboardPage.ets`
- GPS 轨迹: `entry/src/main/ets/pages/PathMapPage.ets`

### 2.5 MQTT 协议

| 项目 | 参数 |
|---|---|
| Broker | broker.hivemq.com:1883 |
| 发布 Topic | `petcare/device/data` |
| 订阅 Topic | `petcare/device/command` |
| 上报周期 | ~5 分钟 (每 100 次主循环) |
| QoS | 0 (至多一次) |

**App 下发命令格式:**

```json
{"cmd":"feed","amount":50}         // 远程投喂
{"cmd":"comfort","type":1}        // 远程安抚 (1=灯光 2=音频 3=组合)
{"cmd":"setHome"}                 // 设置家位置
{"cmd":"getPath"}                 // 请求 GPS 路径
{"cmd":"scheduleSync","plans":[...]}  // 同步投喂计划
{"cmd":"timeSync","ts":1234567890}    // 时间同步
{"cmd":"refresh"}                 // 强制上报
```

### 2.6 串口调试命令 (CLI)

```
hrsim on|off       心率模拟开关 (MAX30102 离线时使用)
anxiety 0-100      焦虑指数模拟
feed 50            手动投喂 50g
sethome            将当前 GPS 坐标设为家
geohome            查看家位置
simpath            注入模拟 GPS 行走路径
path               查看路径点数
pathsave           手动保存路径到 Flash
status             查看系统状态
```

---

## 三、编译与烧录

### 固件编译 (WSL 环境)

```bash
cd /root/openharmony_project/txsmartropenharmony
hb set          # 选择 rk2206 pet_care
hb build
```

### App 编译 (DevEco Studio)

1. 打开 `D:\PET` 目录
2. Build → Build Hap(s)
3. 签名后安装到 HarmonyOS 手机

