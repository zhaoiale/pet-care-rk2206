# pet-care-rk2206 · 智宠管家（RK2206 / OpenHarmony 轻量系统）

基于 **RK2206 + OpenHarmony LiteOS-M** 的智能宠物管家示例工程，运行在小凌派 RK2206 开发板上。
通过称重、心率/血氧、红外测温、六轴姿态、语音识别、GPS 等多传感器融合，实现**自动投喂、健康监测、语音交互、定位追踪、远程联网**等能力。

> 本目录是 `txsmartropenharmony`（中软国际 RK2206 OpenHarmony SDK）中
> `vendor/isoftstone/rk2206/samples/pet_care` 样例的独立备份仓库，
> 供项目归档与后续（如 HydroMate 智能饮水管家）复用南向驱动代码。

---

## 功能特性

| 模块 | 功能 | 主要器件 |
|---|---|---|
| 自动投喂 | 定时/按键/语音触发投喂，称重感知食量 | 投喂电机/继电器、HX711 称重 |
| 健康监测 | 心率、血氧、红外体温、活动量统计 | MAX30102、MLX90614、MPU6050 |
| 语音交互 | 离线语音识别控制（喂食、查询等） | SU-03T 语音模块 |
| 定位追踪 | 宠物位置获取与围栏告警 | ATGM336H GPS、Geofence |
| 环境感知 | 光照、温湿度监测 | 光照/温湿度传感器 |
| 联网上报 | MQTT 连接云端，数据上报 | paho-mqtt |
| 交互反馈 | LCD 显示、RGB 灯、蜂鸣器 | 0.96" OLED/LCD、RGB、蜂鸣器 |

---

## 目录结构

```
pet_care/
├── BUILD.gn                  # 构建脚本（static_library: pet_care_example）
├── iot_pet_care_example.c    # 主程序：任务创建 / 消息队列 / 业务编排
├── include/                  # 全部模块头文件
│   ├── drv_*.h               # 各传感器/执行器驱动（hx711/max30102/mpu6050/...）
│   ├── health_monitor.h      # 健康监测逻辑
│   ├── feed_scheduler.h      # 投喂调度
│   ├── voice_*.h             # 语音识别与意图解析
│   ├── smart_home*.h         # 智能家居事件总线
│   └── ...
└── src/                      # 全部模块实现
    ├── drv_*.c               # 驱动实现
    ├── health_monitor.c
    ├── feed_scheduler.c
    ├── voice_*.c
    ├── smart_home.c / smart_home_event.c
    └── ...
```

---

## 环境要求

- **SDK**：`txsmartropenharmony`（RK2206 OpenHarmony 轻量系统源码），需将本目录放置到
  `vendor/isoftstone/rk2206/samples/pet_care`
- **编译工具**：DevEco Studio（设备开发版）/ hb 编译环境，LiteOS-M 内核，产品 `isoftstone-rk2206`
- **开发板**：小凌派 RK2206（板载 WiFi + 多种外设接口）

---

## 编译步骤

```bash
# 1. 在 SDK 根目录确认 ohos_config.json 配置（board: rk2206, kernel: liteos_m）
# 2. 全量构建
python3 build/lite/hb/__main__.py build -f
# 或
./pet_build.sh
# 3. 产物
#    out/.../liteos.bin  +  Firmware.img → 使用烧录工具烧写
```

> 本样例通过 `vendor/isoftstone/rk2206/samples/BUILD.gn` 引用 `pet_care_example` 库，
> 编译宏在 `iot_pet_care_example.c` 顶部可开关各功能模块。

---

## 关键配置

WiFi 与功能开关集中在主程序头部：

```c
#define ROUTE_SSID      "MY_SW"          // WiFi 账号（修改为你自己的）
#define ROUTE_PASSWORD "12345678"        // WiFi 密码
#define HX711_ENABLED       1            // 称重模块开关
#define FEEDER_ENABLED      1            // 投喂模块开关
#define FEEDER_GPIO         GPIO0_PA5    // 投喂继电器 GPIO
#define AUTO_COMFORT_ENABLED 1           // 智能舒适环境控制
```

MQTT 服务器地址、设备 ID 等在 `src/iot.c` 中配置。

---

## 硬件接线（BOM 参考）

- 主控：小凌派 RK2206
- 称重：HX711 + 5kg 悬臂梁传感器（SCK/DT 接 GPIO，3.3V 供电）
- 心率血氧：MAX30102（I2C）
- 红外测温：MLX90614（I2C）
- 姿态：MPU6050（I2C）
- 语音：SU-03T（串口）
- 定位：ATGM336H（串口）
- 显示：0.96" SSD1306 OLED / LCD
- 执行器：投喂电机/继电器、RGB LED、蜂鸣器

---

## License

工程源码基于 [Apache License 2.0](LICENSE)。
驱动/样例版权归 iSoftStone Education Co., Ltd.（中软国际）所有，本仓库仅作学习与二次开发归档。
