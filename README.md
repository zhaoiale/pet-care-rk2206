# 智宠管家 · pet-care-rk2206（RK2206 + OpenHarmony 全栈智能宠物系统）

> 2024 全国大学生嵌入式芯片与系统设计竞赛作品 · 基于 OpenHarmony RK2206 的宠物异常行为感知与主动关怀系统

通过 **称重 / 心率血氧 / 红外测温 / 六轴姿态 / 离线语音 / GPS 定位** 等多传感器融合，实现宠物**异常行为感知、情绪安抚、定量投喂、电子围栏与远程关怀**；配套 HarmonyOS App 提供实时数据看板与远程控制。

本仓库同时包含**硬件固件（南向）**与**软件 App（北向）**两部分完整源码。

---

## 功能特性

| 能力 | 说明 |
|---|---|
| 异常行为感知 | 焦虑引擎（Z-score + 马氏距离 + HRV 分析），输出 0-100 焦虑指数与情绪标签 |
| 主动安抚 | 24h 分桶自适应基线学习，RGB 灯光 / 蜂鸣 / 语音 分级安抚 |
| 定量投喂 | HX711 称重闭环克数控制 + 每日定时投喂计划 |
| 电子围栏 | GPS 轨迹记录，100m 半径越界检测，离线轨迹 Flash 存储 |
| 远程控制 | HiveMQ MQTT 通信，App 远程投喂 / 安抚 / 查看轨迹 |
| 健康监测 | MAX30102 心率血氧、MLX90614 红外体温、MPU6050 活动量 |
| 语音交互 | SU-03T 中文离线语音识别 |
| App 全栈 | HarmonyOS ArkTS，登录/看板/投喂/历史/领养等 16+ 页面 |

---

## 目录结构

```
pet-care-rk2206/
├── hardware_src/            # 南向：RK2206 固件源码（OpenHarmony LiteOS-M）
│   ├── BUILD.gn             # GN 构建配置（static_library: pet_care_example）
│   ├── iot_pet_care_example.c  # 主程序：任务创建 / 主循环 / MQTT 打包
│   ├── include/             # 模块头文件（33 个）
│   ├── src/                 # 模块源码（33 个）：驱动 / 算法 / 业务
│   └── README.md            # 固件说明（依赖 SDK 集成）
└── app/                     # 北向：HarmonyOS App 源码（ArkTS/ArkUI）
    ├── AppScope/            # 应用级配置
    ├── entry/               # entry 模块（pages / services / database / utils / model）
    ├── hvigor/              # 构建配置
    ├── build-profile.json5  # 工程构建配置
    ├── oh-package.json5     # 依赖声明
    ├── *.py                 # 辅助脚本（焦虑模拟 / 演示数据）
    ├── *.md                 # 项目文档（README / demo_script / DEVELOPMENT_LOG）
    └── README.md            # 详细项目文档（硬件设计 + 固件架构 + App + MQTT 协议）
```

---

## 硬件部分（hardware_src/）

- **主控**：RK2206（Cortex-M4 @ 200MHz）+ OpenHarmony LiteOS-M
- **传感器**：SHT30 温湿度、BH1750 光照、MAX30102 心率血氧、MPU6050 六轴、ATGM336H GPS、HX711 称重、HC-SR501 人体感应、SU-03T 离线语音
- **执行器**：2.8" TFT LCD（ILI9341）、WS2812 RGB LED、有源蜂鸣器、投喂电机（继电器隔离）

固件需集成到 `txsmartropenharmony` SDK 中编译：

```bash
# 将 hardware_src 放置到 SDK 的 vendor/isoftstone/rk2206/samples/pet_care
# 在 SDK 根目录执行
python3 build/lite/hb/__main__.py build -f
```

> 详细引脚分配、接线图、电源要求与算法参数见 `hardware_src/README.md`。

---

## 软件部分（app/）

HarmonyOS ArkUI（ArkTS）应用，DevEco Studio 直接打开 `app/` 即可编译打包 HAP。

- **页面**：登录/注册、宠物看板、投喂控制、历史曲线、舒适安抚、虚拟宠物、领养管理等 16+ 页面
- **服务**：MQTT 通信（`MqttService`）、本地通知、DeepSeek 智能问答
- **数据**：RelationalStore 本地库（宠物档案 / 投喂计划 / 传感器记录）

MQTT 协议：`broker.hivemq.com:1883`，发布 `petcare/device/data`，订阅 `petcare/device/command`。

> 详细功能、页面说明与命令协议见 `app/README.md`。

---

## 编译与烧录

| 部分 | 工具 | 步骤 |
|---|---|---|
| 固件 | DevEco Studio（设备开发版）/ hb | 集成到 SDK 后 `hb build`，产物 `liteos.bin` + `Firmware.img` 烧录 |
| App | DevEco Studio（应用开发版） | 打开 `app/` → Build → Build Hap(s) → 签名安装到 HarmonyOS 手机 |

---

## License

工程源码基于 [Apache License 2.0](LICENSE)。
固件驱动/样例版权归 iSoftStone Education Co., Ltd.（中软国际）所有，本仓库仅作学习与二次开发归档。
