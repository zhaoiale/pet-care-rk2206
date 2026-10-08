# PET 项目 AI 接入修复说明（2026-10-08）

> 本文件记录本次诊断结论、修复内容与验证结果，参考项目：`D:\code\OpenHarmony\HM\HarmonyOS_Life`（Kimi 接入，已实测可用）。

---

## 一、诊断结论：DeepSeek 接入失败的根本原因

对 PET 项目现有 AI 链路做了逐层排查，最终用最小请求实测接口，**根因如下**：

| 排查项 | 结果 |
|--------|------|
| 网络权限 `ohos.permission.INTERNET` | ✅ 已配置（`entry/src/main/module.json5`） |
| API 地址 `https://api.deepseek.com/v1/chat/completions` | ✅ 正确 |
| 模型名 `deepseek-chat` | ✅ 正确 |
| 请求格式（OpenAI 兼容） | ✅ 正确 |
| 硬编码的 API Key `sk-76d1ea05...` | ❌ **实测返回 HTTP 401 Unauthorized，Key 无效** |

**结论**：权限、地址、协议全部正常，唯一的问题是 API Key 无效（过期 / 被删除 / 非本人账号余额不足等）。请求发出后被 DeepSeek 拒绝，代码走到兜底分支，页面只显示 "AI暂时无法分析，请检查网络和API Key"。

## 二、参考 HarmonyOS_Life 的成功接入方案

HM 项目同样走 HTTP 直连方式，但它接入的是 **Moonshot Kimi**（OpenAI 兼容协议），Key 实测有效：

- 接口地址：`https://api.moonshot.cn/v1/chat/completions`
- 模型：`kimi-k2.6`
- 认证：`Authorization: Bearer {KEY}`
- 请求体只含 `model / messages / stream` 三个字段（**kimi-k2.6 不接受 `max_tokens` / `temperature`，传入会报 400**）
- 非流式 `stream: false`，一次性返回完整回复

HM 成功经验中值得抄的三点（已全部并入本次修复）：
1. **超时给足**：连接 30s / 读取 300s（原 PET 只有 10~15s，大模型生成慢时极易超时）
2. **`expectDataType: http.HttpDataType.STRING`**：避免 result 类型不确定导致解析失败
3. **错误可见**：非 200 时记录 HTTP 状态码 + 响应体，方便直接定位（原代码把错误吞掉，只打了一行日志）

## 三、已修改文件（4 处，两套工程同步）

| 文件 | 修改内容 |
|------|----------|
| `entry/src/main/ets/services/DeepSeekService.ets` | 核心修复：接入从 DeepSeek 改为 Kimi；保留全部导出函数签名（页面/MQTT 调用零改动）；超时放大；`expectDataType`；错误记录；`destroy()` 释放 |
| `app/entry/src/main/ets/services/DeepSeekService.ets` | 与上同步（注意：本项目存在**双工程**，根目录与 `app/` 各一套，需保持一致） |
| `entry/src/main/ets/pages/DashboardPage.ets` | UI 标签 "DeepSeek" → "Kimi" |
| `app/entry/src/main/ets/pages/DashboardPage.ets` | 同上 |
| `entry/src/main/ets/pages/VirtualPetPage.ets` | UI 标签 "DeepSeek" → "Kimi" |
| `app/entry/src/main/ets/pages/VirtualPetPage.ets` | 同上 |

> 说明：文件仍叫 `DeepSeekService.ets` 是为保证 import 链路零改动；如需改回 DeepSeek 品牌可自行重命名并同步 import。

## 四、验证结果（真实接口实测）

1. **Kimi Key 有效性**：`kimi-k2.6` 最小请求 → ✅ 正常返回（"Pong! 👋 I'm here and ready to help."）
2. **DeepSeek 旧 Key**：`deepseek-chat` 最小请求 → ❌ 401 Unauthorized（确认无效）
3. **PET 真实场景**（宠物行为分析完整 prompt，模拟"猫、低声呜咽、焦虑 78/100"）→ ✅ 正常返回：
   > "小家伙这会儿正又焦虑又想你呢，一个人待着心慌慌的，哼哼唧唧就是在喊你快来陪陪它呀。"

## 五、验证方法

- 在 DevEco Studio 中打开工程，构建 `entry` 模块（`entry@default`），确认 0 ERROR
- 真机/模拟器运行：硬件通过 MQTT 上报 `petcare/voice/intent` 主题后，Dashboard / 虚拟宠物页应显示 AI 解读
- 若仍失败，查看 HiLog 中 `[Ai]` 标签日志（新代码会把 HTTP 状态码和响应体写入日志，直接可见原因）

## 六、以后想切回 DeepSeek

拿到有效 DeepSeek Key 后，只改 `DeepSeekService.ets` 顶部三行常量即可：

```typescript
const AI_API_URL: string = 'https://api.deepseek.com/v1/chat/completions';
const AI_MODEL: string = 'deepseek-chat';
const AI_API_KEY: string = 'sk-你的有效Key';   // platform.deepseek.com 申请
```

DeepSeek 是同样的 OpenAI 兼容协议，可自行按需在 `requestAi()` 的请求体里加回 `max_tokens` / `temperature`（DeepSeek 支持这两个参数；Kimi k2.6 不支持，切回前别忘恢复）。
