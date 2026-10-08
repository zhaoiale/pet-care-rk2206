/**
 * DeepSeekService.ets — 云端语义增强: 宠物叫声 + 传感器上下文 → 自然语言解读
 *
 * 【2026-10-08 接入修复记录】
 * 原实现直接调用 DeepSeek 官方 API（https://api.deepseek.com/v1/chat/completions），
 * 但硬编码在文件里的 API Key（sk-76d1ea05...）经实测返回 HTTP 401 Unauthorized，
 * 属于无效 Key（过期 / 被删除 / 非本人账号），导致请求永远走不到成功分支，
 * 页面只能显示兜底文案 "AI暂时无法分析"。
 *
 * 现参照 HarmonyOS_Life 项目的成功接入方案（Moonshot Kimi，OpenAI 兼容协议）：
 *   - 接口地址：https://api.moonshot.cn/v1/chat/completions
 *   - 模型    ：kimi-k2.6（在 HarmonyOS_Life 项目中实测可用，本次也已实测通过）
 *   - 认证    ：Authorization: Bearer {KEY}
 *   - 请求格式：OpenAI 兼容（model / messages / stream），stream: false
 *
 * 若之后拿到有效的 DeepSeek Key，只需把下方三行 AI_* 常量换回 DeepSeek 配置即可，
 * 协议完全兼容（DeepSeek 同样是 OpenAI 兼容格式）：
 *   AI_API_URL = 'https://api.deepseek.com/v1/chat/completions'
 *   AI_MODEL   = 'deepseek-chat'
 *   AI_API_KEY = 'sk-你的有效Key'
 * 注意：kimi-k2.6 不允许传 max_tokens / temperature（会报 400），故请求体只保留
 * model/messages/stream 三字段，与 HarmonyOS_Life 的 KimiApi 保持一致。
 * 切回 DeepSeek 时可自行按需加回这两个参数。
 *
 * 相对原实现的其他加固（参考 HarmonyOS_Life 的 KimiApi）：
 *   1. expectDataType 显式声明为 STRING，避免 result 类型不确定导致解析失败
 *   2. 超时放大：连接 30s / 读取 300s（大模型生成回复可能超过 15s，原 10~15s 极易超时）
 *   3. 非 200 时把 HTTP 状态码 + 响应体记录到 lastAiError，便于页面/日志直接定位
 *   4. 请求结束后 destroy() 释放实例，防止内存泄漏
 *   5. 全局 30s 最小调用间隔（保留），避免高频 MQTT 消息打爆额度
 */
import { http } from '@kit.NetworkKit';

// ============================================================
// AI 服务配置（切换供应商只需改这三行）
// ============================================================
const AI_API_URL: string = 'https://api.moonshot.cn/v1/chat/completions';
const AI_MODEL: string = 'kimi-k2.6';
const AI_API_KEY: string = 'sk-bjd0VJ5VSbALFvtQQwsaYgWTQzc28GE5CVxlH35x93MMst53';

// 连接 / 读取超时（毫秒）。AI 生成较慢，读取超时必须给足。
const CONNECT_TIMEOUT_MS: number = 30000;
const READ_TIMEOUT_MS: number = 300000;

/** 最小调用间隔（毫秒），防止 MQTT 高频消息触发连续请求 */
const MIN_INTERVAL_MS: number = 30000;

// ============================================================
// 对外数据结构（页面 / MQTT 层调用保持不变）
// ============================================================
export interface PetStateContext {
  species: string;
  voiceIntent: string;
  voiceConfidence: number;
  heartRate: number;
  spo2: number;
  activityLevel: number;
  anxietyLevel: number;
  healthScore: number;
  emotion: string;
  lastFeedHours: number;
  timeOfDay: string;
}

interface ChatMessage {
  role: string;
  content: string;
}

interface AiRequest {
  model: string;
  messages: ChatMessage[];
  stream: boolean;
}

interface AiChoice {
  message: ChatMessage;
}

interface AiResponse {
  choices: AiChoice[];
}

// ============================================================
// 全局状态
// ============================================================
let lastResult: string = '';
let lastCallTime: number = 0;
let lastAiError: string = '';

/** 获取最近一次 AI 分析结果 */
export function getLastAiResult(): string {
  return lastResult;
}

/** 获取最近一次 AI 调用错误（便于页面展示 / 排查） */
export function getLastAiError(): string {
  return lastAiError;
}

/** 清空 AI 结果与错误 */
export function clearLastAiResult(): void {
  lastResult = '';
  lastAiError = '';
}

// ============================================================
// 通用请求封装：POST OpenAI 兼容接口，返回 choices[0].message.content
// ============================================================
async function requestAi(messages: ChatMessage[]): Promise<string> {
  const reqBody: AiRequest = {
    model: AI_MODEL,
    messages: messages,
    stream: false // 非流式，一次性返回完整回复
  };

  const req: http.HttpRequest = http.createHttp();
  try {
    const resp = await req.request(AI_API_URL, {
      method: http.RequestMethod.POST,
      header: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${AI_API_KEY}`
      },
      extraData: JSON.stringify(reqBody),
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: CONNECT_TIMEOUT_MS,
      readTimeout: READ_TIMEOUT_MS
    });

    if (resp.responseCode === 200) {
      // result 声明为 STRING 后可直接按字符串解析
      const respData: AiResponse = JSON.parse(resp.result as string) as AiResponse;
      if (respData.choices && respData.choices.length > 0 && respData.choices[0].message) {
        const content: string = respData.choices[0].message.content;
        if (content.length > 0) {
          return content;
        }
      }
      lastAiError = 'AI响应为空';
      return '';
    }

    // 非 200：把状态码和响应体记录下来，便于排查（如 401 Key 无效、429 限流、402 余额不足）
    lastAiError = 'HTTP ' + resp.responseCode.toString() + ': ' + (resp.result as string).substring(0, 200);
    console.error('[Ai] HTTP ' + resp.responseCode.toString() + ' body=' + lastAiError);
    return '';
  } catch (e) {
    lastAiError = '请求异常: ' + JSON.stringify(e);
    console.error('[Ai] Request failed: ' + lastAiError);
    return '';
  } finally {
    // 释放 HTTP 实例，防止内存泄漏
    req.destroy();
  }
}

// ============================================================
// 功能一：主人说话 → 宠物叫声意图（枚举归一下）
// ============================================================
export async function translateToPetSound(text: string, species: string): Promise<string> {
  const speciesCn: string = species === 'dog' ? '狗' : '猫';
  const prompt: string = `你是一个智能宠物翻译器。主人说了以下话："${text}"。
宠物是一只${speciesCn}。
请把主人的话翻译成宠物的叫声意图，从以下选项中选最合适的一个：hungry(饿了讨食)、happy(开心撒娇)、warning(警戒)、lonely(孤独呼唤)、play(想玩耍)、calm(安抚回应)。
只返回一个英文单词，不要任何解释。`;

  const content: string = await requestAi(
    [
      { role: 'system', content: '你是宠物翻译专家，只返回一个英文单词。' } as ChatMessage,
      { role: 'user', content: prompt } as ChatMessage
    ]
  );

  const lower: string = content.trim().toLowerCase();
  if (lower.includes('hungry')) return 'hungry';
  if (lower.includes('happy')) return 'happy';
  if (lower.includes('warning')) return 'warning';
  if (lower.includes('lonely')) return 'lonely';
  if (lower.includes('play')) return 'play';
  if (lower.includes('calm')) return 'calm';
  return 'happy'; // 兜底
}

// ============================================================
// 功能二：传感器上下文 → 宠物状态自然语言解读（MQTT 主链路）
// ============================================================
export async function analyzePetState(ctx: PetStateContext): Promise<string> {
  const now: number = Date.now();
  if (now - lastCallTime < MIN_INTERVAL_MS) {
    return lastResult; // 30 秒内的重复请求直接返回上次结果
  }
  lastCallTime = now;

  const speciesCn: string = ctx.species === 'dog' ? '狗' : '猫';
  const intentCn: string = ctx.voiceIntent === 'hungry' ? '饥饿讨食' :
                            ctx.voiceIntent === 'warning' ? '警戒吠叫' :
                            ctx.voiceIntent === 'lonely' ? '低声呜咽(可能孤独)' : '未识别叫声';
  const emotionCn: string =
    ctx.anxietyLevel >= 70 ? '高度焦虑' :
    ctx.anxietyLevel >= 45 ? '轻度紧张' :
    ctx.anxietyLevel >= 25 ? '警觉' : '平静';

  const prompt: string = `你是宠物行为分析专家。根据以下传感器数据，用一两句通俗易懂的话告诉主人宠物当前的感受和想表达的意思。

数据：
- 物种: ${speciesCn}
- 叫声类型: ${intentCn} (置信度${Math.round(ctx.voiceConfidence * 100)}%)
- 当前心率: ${ctx.heartRate}bpm
- 血氧: ${ctx.spo2}%
- 活动量: ${ctx.activityLevel}/100
- 情绪等级: ${emotionCn}(${ctx.anxietyLevel}/100)
- 健康评分: ${ctx.healthScore}/100${ctx.lastFeedHours > 0 ? `\n- 距上次进食: ${ctx.lastFeedHours.toFixed(1)}小时` : ''}
- 时间: ${ctx.timeOfDay}

请直接给出分析，不要重复数据，不要加前缀如"分析："，就用一两句大白话。`;

  const content: string = await requestAi(
    [
      { role: 'system', content: '你是宠物行为分析专家，回答简洁、通俗、有温度。' } as ChatMessage,
      { role: 'user', content: prompt } as ChatMessage
    ]
  );

  if (content.length > 0) {
    lastResult = content;
    lastAiError = '';
    console.info('[Ai] result: ' + content);
    return content;
  }

  // 失败时返回兜底文案，同时保留 lastAiError 供排查
  return lastResult || 'AI暂时无法分析，请检查网络和API Key';
}
