# PET 接入华为云 IoTDA 改造说明（2026-10-08）

> 参考项目：`D:\code\OpenHarmony\HM\water`（WSL 中 `/root/openharmony_project/txsmartropenharmony/vendor/isoftstone/rk2206/samples/hydromate` 为华为云 IoTDA 接入版）。
> 本次将 PET 的 MQTT 接入从 **HiveMQ 公共 broker** 整体切换到 **华为云 IoTDA（设备接入服务）**。

---

## 一、改造前后对比

| 项目 | 改造前 | 改造后 |
|------|--------|--------|
| Broker | `broker.hivemq.com:1883` | `5256547599.st1.iotda-device.cn-north-4.myhuaweicloud.com:1883`（复用饮水项目实例） |
| 认证 | 匿名 / public | 一机一密：`clientId=设备ID_0_0_YYYYMMDDHH`、`username=设备ID`、`password=HMAC-SHA256(时间戳,设备密钥)` |
| 主题 | 自由主题 `petcare/device/data` 等 | IoTDA 系统主题 `$oc/devices/{设备ID}/sys/...`（带设备归属校验） |
| App 收数据 | 直接订阅板子上报主题 | 订阅自己设备的 `messages/down`（经平台转发/下发） |
| App 发指令 | 直接发布到 `petcare/device/command` | 发布到自己设备的 `messages/up`（经平台转发给板子） |

## 二、架构（IoTDA 是中心化架构）

```
┌────────────┐  属性/消息上报   ┌──────────────┐  messages/down   ┌────────────┐
│ RK2206 板子 ├───────────────► │  华为云 IoTDA │◄────────────────┤  App（鸿蒙）│
│ (设备A)     │  messages/up   │  (平台/控制台) │  messages/up    │ (设备B)    │
└────────────┘                └──────────────┘                   └────────────┘
       ▲                              │ 规则引擎/数据转发/手动消息下发
       │        messages/down（平台下发指令）│
       └────────────────────────────────┘
```

**重要限制**：IoTDA 的 `$oc` 主题带设备归属校验，两个设备之间**不能**像 HiveMQ 那样通过自由主题互发。板子 → App 的数据必须经平台（控制台手动下发 / 规则引擎转发）。

## 三、已修改/新增文件（两套工程已同步）

### 北向 App（entry 与 app/entry 各一份，内容一致）
| 文件 | 修改 |
|------|------|
| `services/IotdaConfig.ets`（新增） | IoTDA 配置 + 一机一密认证生成（运行时动态计算 HMAC-SHA256 密码，**永不过期**） |
| `services/SimpleMqttClient.ets` | broker 指向 IoTDA；`mqttConnect` 增加 username/password 参数 |
| `services/MqttService.ets` | 订阅/发布主题改为 `$oc`；接入一机一密；新增平台消息下发解包（兼容 content/message 多层包装）；板子 `services[]` 数据与 `petVoice` 意图解析 |

### 南向固件（hardware_src，RK2206 主控）
| 文件 | 修改 |
|------|------|
| `hardware_src/src/iot.c` | 一机一密连接（ClientId/Username/Password）；上报改 `messages/up`（零配置，不依赖物模型）；订阅改 `messages/down`；指令解析兼容 IoTDA 消息下发多层包装 |

### 工具
| 文件 | 说明 |
|------|------|
| `tools/gen_iotda_credential.py` | 生成南向固件预计算凭证（板子侧 C 代码无 mbedtls，采用写死方式，按小时生成） |

## 四、你还需要做的（3 步）

### 1. 注册 App 独立设备
IoTDA 一机一密**同一设备 ID 只允许一个在线连接**，App 必须新建设备：
1. 登录 [华为云 IoTDA 控制台](https://console.huaweicloud.com/iotdm)（复用饮水项目的实例/产品）
2. 产品 → 设备列表 → **注册设备**，设备名称如 `pet_app01`
3. 记录 **设备 ID**（形如 `6aa9198b7f2e6c302f999974_pet_app01`）和**设备密钥（secret）**

### 2. 填入 App 凭证
打开 `entry/src/main/ets/services/IotdaConfig.ets`（app 副本同位置），替换：
```typescript
static readonly APP_DEVICE_ID: string = '你新建的设备ID';
static readonly APP_DEVICE_SECRET: string = '你的设备密钥';
```

### 3. 生成南向板子凭证（当前小时的）
```bash
python tools/gen_iotda_credential.py 6aa9198b7f2e6c302f999974_rk2206_water01 <饮水设备的密钥>
```
把输出替换到 `hardware_src/src/iot.c` 顶部的 `CLIENT_ID` / `MQTT_DEVICES_PWD` 宏。
> 时间戳小时级有效：**每次演示前重新生成一次**即可（工具一键输出）。

## 五、数据流（演示步骤）

1. **板子 → 平台**：板子上电后以 IoTDA 设备身份连接，传感器数据（`services[]` 格式）上报到 `$oc/devices/{板子}/sys/messages/up`。可在控制台「设备调试」→「设备消息」看到。
2. **平台 → App**：控制台向 App 设备下发消息（或配置规则引擎把板子消息转发给 App），App 从 `messages/down` 收到后解析入库、刷新 Dashboard。
3. **App → 板子指令**：App 界面发指令 → 发布到 `$oc/devices/{App}/sys/messages/up` → 平台侧（控制台手动下发 / 规则引擎）把指令下发给板子 `messages/down` → 板子执行（安抚/投喂/刷新等原有命令全部兼容）。

## 六、ESP32 感知节点说明

原 HiveMQ 下 ESP32 通过 `petcare/voice/features`、`pet/wearable/data` 直发主控；IoTDA 下设备间不能互发，该链路已移除（保留函数，注释说明）。可选处理：
- ESP32 注册独立 IoTDA 设备，数据经平台规则转发给主控；
- 或改为主控本地 UART/局域网直连。

主控本地传感器（心率/血氧/焦虑/投喂/安抚/围栏/路径）不受影响，全部走 IoTDA 上报。

## 七、物模型说明

默认使用**消息上报（messages/up）**，不校验物模型、零配置可跑。若希望控制台「最新上报数据」里直接看结构化属性，可升级为属性上报：
1. 控制台 产品 → 模型定义 → 添加服务（如 `petCare`）及属性（heartRate、spo2、anxietyLevel 等）
2. 板子 `iot.c` 顶部把 `PUBLISH_TOPIC` 改为 `PROP_REPORT_TOPIC`（宏已预留），`service_id` 与模型服务名一致

## 八、连接失败排查

| 现象 | 原因 | 处理 |
|------|------|------|
| 板子连接失败 rc≠0 | 预计算凭证过期（时间戳超小时） | 重新运行 `gen_iotda_credential.py` 并烧录 |
| App 连接失败 CONNACK rejected | 设备密钥填错 / 设备未注册 | 核对控制台设备 ID 与密钥 |
| App 收不到数据 | 平台未向 App 设备下发消息 | 控制台手动下发 / 配置数据转发 |
| 401/设备未激活 | 设备未在控制台注册 | 完成注册后再连 |
