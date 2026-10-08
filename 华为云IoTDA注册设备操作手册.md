# 华为云 IoTDA：注册 App 设备与凭证获取操作手册（PET 专用）

> 适用对象：PET 北向 App（HarmonyOS）在华为云 IoTDA 上注册**独立设备** `pet_app01`，
> 以及南向板子凭证的生成与更新。
> 说明：本手册无法提供你账号内的真实界面截图（需登录你的华为云），
> 但每一步都精确到**菜单位置、按钮名称、字段填写值**，照做即可。官方界面如有细微差异，以界面文字为准。

---

## 〇、前置准备（一次性的）

1. 注册华为云账号：https://www.huaweicloud.com 右上角"注册"，手机号即可。
2. 完成实名认证：控制台右上角头像 →「实名认证」，个人认证即可（学生认证更好，有免费额度）。
3. 确认已开通 IoTDA 实例（饮水项目已开通过，**直接复用**，跳过"开通实例"）。

---

## 一、登录并进入 IoTDA 控制台

1. 打开浏览器访问：**https://console.huaweicloud.com/iotdm**
2. 华为云账号登录（建议用与饮水项目相同的账号，保证实例可见）。
3. 进入 **设备接入 IoTDA** 控制台后，页面中部会列出你的实例卡片
   （标准版/企业版），**单击实例卡片**进入实例内。
   > 饮水项目实例接入地址：`5256547599.st1.iotda-device.cn-north-4.myhuaweicloud.com`
   > 对应区域：**华北-北京四（cn-north-4）**，接入协议：**MQTT**。
4. 进入后左侧导航栏依次有：总览、产品、设备、规则、监控运维 等。

---

## 二、注册 App 独立设备（核心步骤）

> 为什么必须新建设备：IoTDA 一机一密同一 `device_id` **只允许一个在线连接**。
> 板子已经占用 `6aa9198b7f2e6c302f999974_rk2206_water01`，App 必须再建一个。

1. 左侧导航栏选择 **「设备 > 所有设备」**。
2. 页面右上角单击 **「注册设备」**，弹出注册窗口，按如下填写：

| 表单字段 | 填写内容 | 说明 |
|----------|----------|------|
| 所属资源空间 | 与饮水设备相同的资源空间（默认 default 即可） | 必须在同一个资源空间，否则产品/设备互相不可见 |
| 所属产品 | 选择饮水项目用的产品（或 PET 新建的产品，见"附：创建产品"） | 同一产品便于统一管理 |
| 设备标识码（nodeID） | `pet_app01` | 设备唯一物理标识，英文字母+数字+下划线 |
| 设备名称 | `PET手机端App` | 可选，仅用于控制台显示 |
| 认证方式 | **密钥** | 一机一密用密钥认证 |
| 设备密钥（Secret） | **留空** | 留空则平台自动生成（推荐），点确定后一次性展示 |

3. 单击 **「确定」**。
4. 注册成功弹窗会**一次性显示并提示保存**：
   - **设备 ID（device_id）**：形如 `6aa9198b7f2e6c302f999974_pet_app01`
     （自动生成规则 = 产品ID + `_` + 设备标识码）
   - **设备密钥（Secret）**：一串随机字符串（如 `e7a3c9f2...`），**只在此时完整展示**
   - ⚠️ 立刻复制保存这两个值到记事本；关掉窗口就再也看不到密钥（只能重置）。

5. 若当时没保存密钥：进入 **「设备 > 所有设备」** → 单击该设备进入详情页 →
   **「设备详情」标签页 → 设备密钥右侧「重置密钥」**（重置后生成新密钥，旧连接会失效）。

---

## 三、把凭证填入 App 代码

打开（两个位置都要改，内容相同）：
- `entry/src/main/ets/services/IotdaConfig.ets`
- `app/entry/src/main/ets/services/IotdaConfig.ets`

把第 41、46 行的占位替换为刚才保存的真实值：

```typescript
static readonly APP_DEVICE_ID: string = '6aa9198b7f2e6c302f999974_pet_app01';   // 控制台看到的设备ID
static readonly APP_DEVICE_SECRET: string = 'e7a3c9f2xxxxxxxxxxxxxxxxxxxxxxxx';  // 注册时保存的设备密钥
```

改完保存，DevEco Studio 重新构建运行。App 启动后会自动：
1. 取当前时间生成时间戳 `YYYYMMDDHH`
2. 用密钥计算 `HMAC-SHA256(时间戳, 密钥)` 得到密码
3. 以 `设备ID_0_0_时间戳 / 设备ID / 密码` 连接 IoTDA，订阅自己的 `messages/down`

---

## 四、验证 App 是否连上（控制台看）

1. 回到 IoTDA 控制台 **「设备 > 所有设备」**。
2. 找到 `pet_app01` 这一行，看 **「状态」** 列：
   - **在线**（绿色）→ App 接入成功 ✅
   - **未激活/离线** → 检查设备 ID、密钥是否填错，或 App 日志 `[MQTT]` 标签报错。
3. App 侧 HiLog 应能看到：
   ```
   [MQTT] IoTDA auth: device=6aa9198b7f2e6c302f999974_pet_app01 ts=2026100814
   [MQTT] Connected & subscribed to Huawei IoTDA: $oc/devices/.../sys/messages/down
   ```

---

## 五、南向板子凭证（复用饮水设备，按小时生成）

板子用的是饮水设备 `6aa9198b7f2e6c302f999974_rk2206_water01`，设备密钥去 IoTDA 控制台
**设备详情页 → 设备密钥** 查看（若没有，点「重置密钥」并保存新值）。

在本机命令行执行（用真实的设备密钥替换 `<饮水设备密钥>`）：

```
python tools/gen_iotda_credential.py 6aa9198b7f2e6c302f999974_rk2206_water01 <饮水设备密钥>
```

把输出的三行宏（`DEVICE_ID` / `CLIENT_ID` / `MQTT_DEVICES_PWD`）替换到
`hardware_src/src/iot.c` 顶部，重新编译烧录。
**注意**：时间戳小时级有效，每次演示前重新生成一次（耗时 1 秒）。

---

## 六、演示数据流：控制台给 App 下发消息（App 实时显示）

App 已订阅 `$oc/devices/{app}/sys/messages/down`，控制台随时可给 App 推消息：

1. IoTDA 控制台 **「设备 > 所有设备」** → 单击 `pet_app01` 进入详情页。
2. 切换到 **「云端下发 > 消息下发」** 标签页。
3. 单击 **「下发消息」**，在弹窗中填消息内容（二选一）：

   **A. 模拟板子传感器数据（App 会解析入库、刷新 Dashboard）：**
   ```json
   {
     "services": [
       {
         "service_id": "petCare",
         "properties": {
           "temperature": "26.5",
           "humidity": "45",
           "illumination": "320",
           "anxietyLevel": 68,
           "activityLevel": 55,
           "heartRate": 135,
           "spo2": 97,
           "healthScore": 72,
           "emotion": "焦虑",
           "foodWeight": 150,
           "foodEaten": 60,
           "gpsLat": 34.25,
           "gpsLon": 108.94,
           "bodyTemp": 38.6,
           "hrvStress": 0.62,
           "geofenceStatus": 1,
           "homeLat": 34.25,
           "homeLon": 108.94,
           "comfortType": 1,
           "audioSubType": 2,
           "lightStatus": "1",
           "motorStatus": "0",
           "autoStatus": "1",
           "exceedCount": 1
         }
       }
     ]
   }
   ```

   **B. 模拟板子叫声意图（App 会触发 Kimi AI 解读）：**
   ```json
   {
     "cmd": "petVoice",
     "intent": "hungry"
   }
   ```

4. 单击 **「确定」**。App 端收到后按 `content/message` 多层解包自动识别并处理；
   Dashboard / 虚拟宠物页应立即刷新，AI 解读卡显示 Kimi 的分析结果。

> 同理，给**板子**（rk2206_water01）下发指令（如 `{"cmd":"refresh"}`、`{"cmd":"comfort","type":1}`、
> `{"cmd":"feed","amount":50}`、`{"cmd":"playSound","intent":"happy","species":"cat"}`），
> 板子从自己的 `messages/down` 收到后执行对应动作（刷新上报/灯光安抚/投喂/播放猫叫）。

---

## 七、（可选）规则引擎：板子数据自动转发给 App

不想每次手动下发？配一条数据转发规则，板子每次上报的消息会自动转发给 App 设备。
> 注意：IoTDA 数据转发目标支持 消息队列(AMQP/Kafka)、OBS、FunctionGraph、第三方 HTTP 等，
> **不能直接转发给另一台 MQTT 设备**。要让 App 实时收到，常用做法：

**方案 A（推荐，轻量）：转发到 FunctionGraph，用函数把消息下发给 App 设备**
1. 控制台 **「规则 > 数据转发」** → 右上角 **「创建规则」**。
2. 数据来源：选择「设备消息」，触发产品选板子所在产品。
3. 转发目标：选「函数工作流 FunctionGraph」（首次需授权），新建函数：
   - 函数代码调用 IoTDA API `MessageDevice`（消息下发），把收到的板子消息原样下发给 `pet_app01`。
4. 单击「启动规则」。此后板子 `messages/up` → 平台 → 函数 → 自动下发 App → App 实时显示。

**方案 B（最简单，适合演示）：手动下发**（见第六节），或把板子数据转发到 **OBS 存储**，
演示时打开 OBS 桶看历史数据（`规则 > 数据转发` → 转发目标选 OBS）。

---

## 附：创建产品与模型定义（可选）

当前 PET 走**消息上报**，**不需要**物模型即可跑通。若想让控制台"最新上报数据"直接展示结构化属性：

1. 控制台 **「产品」→「创建产品」**：
   - 产品名称：`PET宠物管家`；协议类型：**MQTT**；数据格式：**JSON**；所属资源空间：default。
2. 产品详情 → **「模型定义」** → 单击 **「添加服务」**：服务ID填 `petCare`。
3. 在 `petCare` 服务下添加属性（属性名/数据类型/访问权限）：
   `temperature(Float/只读)`、`humidity(Float/只读)`、`illumination(Float/只读)`、
   `heartRate(Int/只读)`、`spo2(Int/只读)`、`anxietyLevel(Int/只读)`、
   `healthScore(Int/只读)`、`emotion(String/只读)`、`activityLevel(Int/只读)` 等。
4. 板子 `iot.c` 顶部把 `PUBLISH_TOPIC` 从 `messages/up` 改为 `PROP_REPORT_TOPIC`
   （宏已预留 `properties/report`），重新编译即可升级为属性上报。
   （注意：属性上报会校验物模型，未定义的属性会被平台忽略，需保证属性名与模型完全一致。）

---

## 常见问题速查

| 现象 | 原因 | 处理 |
|------|------|------|
| App 连不上，日志 CONNACK rejected | 设备ID/密钥填错，或设备未注册 | 核对控制台值；注册后重试 |
| 板子连不上 rc≠0 | 预计算凭证过期（跨小时） | 重新运行 gen_iotda_credential.py 并烧录 |
| App 收不到数据 | 平台未向 App 设备下发 | 按第六节手动下发测试；或配置第七节转发 |
| 设备显示"未激活" | 首次连接需要设备真正连上平台 | 检查 App/板子是否启动并连接 |
| 上报的数据控制台看不到 | 用了消息上报（消息在"设备消息"页） | 设备详情→「设备消息」查看；或升级属性上报 |
