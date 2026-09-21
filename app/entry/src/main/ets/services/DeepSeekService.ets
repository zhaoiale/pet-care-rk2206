// DeepSeekService.ets — 云端语义增强: 宠物叫声+传感器上下文 → 自然语言解读
import { http } from '@kit.NetworkKit';

const DEEPSEEK_API_URL: string = 'https://api.deepseek.com/v1/chat/completions';
const DEEPSEEK_API_KEY: string = 'sk-76d1ea0556384820a5d4335d4ecc5a18';

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

interface DeepSeekRequest {
  model: string;
  messages: ChatMessage[];
  max_tokens: number;
  temperature: number;
}

interface DeepSeekChoice {
  message: ChatMessage;
}

interface DeepSeekResponse {
  choices: DeepSeekChoice[];
}

let lastResult: string = '';
let lastCallTime: number = 0;
const MIN_INTERVAL_MS: number = 30000;

export function getLastAiResult(): string {
  return lastResult;
}

export function clearLastAiResult(): void {
  lastResult = '';
}

export async function translateToPetSound(text: string, species: string): Promise<string> {
  const speciesCn: string = species === 'dog' ? '狗' : '猫';
  const prompt: string = `你是一个智能宠物翻译器。主人说了以下话："${text}"。
宠物是一只${speciesCn}。
请把主人的话翻译成宠物的叫声意图，从以下选项中选最合适的一个：hungry(饿了讨食)、happy(开心撒娇)、warning(警戒)、lonely(孤独呼唤)、play(想玩耍)、calm(安抚回应)。
只返回一个英文单词，不要任何解释。`;

  const reqBody: DeepSeekRequest = {
    model: 'deepseek-chat',
    messages: [
      { role: 'system', content: '你是宠物翻译专家，只返回一个英文单词。' } as ChatMessage,
      { role: 'user', content: prompt } as ChatMessage
    ],
    max_tokens: 10,
    temperature: 0.5
  };

  try {
    const req: http.HttpRequest = http.createHttp();
    const resp = await req.request(DEEPSEEK_API_URL, {
      method: http.RequestMethod.POST,
      header: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${DEEPSEEK_API_KEY}`
      },
      extraData: JSON.stringify(reqBody),
      connectTimeout: 10000,
      readTimeout: 10000
    });

    if (resp.responseCode === 200) {
      const respData: DeepSeekResponse = JSON.parse(resp.result as string) as DeepSeekResponse;
      const content: string = (respData.choices.length > 0 && respData.choices[0].message)
        ? respData.choices[0].message.content.trim().toLowerCase() : '';
      if (content.includes('hungry')) return 'hungry';
      if (content.includes('happy')) return 'happy';
      if (content.includes('warning')) return 'warning';
      if (content.includes('lonely')) return 'lonely';
      if (content.includes('play')) return 'play';
      if (content.includes('calm')) return 'calm';
      return 'happy'; // default fallback
    }
  } catch (e) {
    console.error('[DeepSeek] translateToPetSound failed: ' + JSON.stringify(e));
  }
  return 'happy';
}

export async function analyzePetState(ctx: PetStateContext): Promise<string> {
  const now: number = Date.now();
  if (now - lastCallTime < MIN_INTERVAL_MS) {
    return lastResult;
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

  const reqBody: DeepSeekRequest = {
    model: 'deepseek-chat',
    messages: [
      { role: 'system', content: '你是宠物行为分析专家，回答简洁、通俗、有温度。' } as ChatMessage,
      { role: 'user', content: prompt } as ChatMessage
    ],
    max_tokens: 200,
    temperature: 0.7
  };
  const body: string = JSON.stringify(reqBody);

  try {
    const req: http.HttpRequest = http.createHttp();
    const resp = await req.request(DEEPSEEK_API_URL, {
      method: http.RequestMethod.POST,
      header: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${DEEPSEEK_API_KEY}`
      },
      extraData: body,
      connectTimeout: 15000,
      readTimeout: 15000
    });

    if (resp.responseCode === 200) {
      const respData: DeepSeekResponse = JSON.parse(resp.result as string) as DeepSeekResponse;
      const content: string = (respData.choices.length > 0 && respData.choices[0].message)
        ? respData.choices[0].message.content : '';
      if (content.length > 0) {
        lastResult = content;
        console.info('[DeepSeek] AI result: ' + content);
        return content;
      }
    }
    console.error('[DeepSeek] HTTP ' + resp.responseCode.toString());
  } catch (e) {
    console.error('[DeepSeek] Request failed: ' + JSON.stringify(e));
  }

  return lastResult || 'AI暂时无法分析，请检查网络和API Key';
}
