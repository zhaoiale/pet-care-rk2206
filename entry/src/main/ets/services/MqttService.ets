// MqttService.ets — MQTT 数据收发服务
// 通过 TCP 连接 HiveMQ 公共 Broker
// 订阅 petcare/device/data 接收硬件上报
// 发布 petcare/device/command 下发指令

import { insertSensorRecord } from '../database/DatabaseService';
import { SensorRecord, GpsPathPoint } from '../model/SensorRecord';
import { mqttConnect, mqttSubscribe, mqttPublish, onMqttMessage, isMqttReady } from './SimpleMqttClient';
import { checkAndNotifyAnxiety } from './NotificationService';
import { analyzePetState, PetStateContext, getLastAiResult } from './DeepSeekService';

const CLIENT_ID: string = 'petcare_app_' + Date.now().toString();
const SUBSCRIBE_TOPIC: string = 'petcare/device/data';
const VOICE_INTENT_TOPIC: string = 'petcare/voice/intent';
const COMMAND_TOPIC: string = 'petcare/device/command';

interface MqttPropertyBag {
  illumination: string;
  temperature: string;
  humidity: string;
  motorStatus: string;
  lightStatus: string;
  autoStatus: string;
  anxietyLevel: number;
  comfortType: number;
  audioSubType: number;
  activityLevel: number;
  exceedCount: number;
  emotion: string;
  foodWeight: number;
  foodEaten: number;
  heartRate: number;
  spo2: number;
  gpsLat: number;
  gpsLon: number;
  hrvStress: number;
  geofenceStatus: number;
  homeLat: number;
  homeLon: number;
  healthScore: number;
  bodyTemp: number;
}

interface MqttServiceItem {
  service_id: string;
  properties: MqttPropertyBag;
}

interface MqttPayload {
  services: MqttServiceItem[];
}

// pathData 消息格式: {"cmd":"pathData","points":[...]}
interface PathDataPayload {
  cmd: string;
  points: GpsPathPoint[];
}

interface VoiceIntentPayload {
  intent: string;
}

// 全局围栏 + 路径状态
export let gpsPathPoints: GpsPathPoint[] = [];
export let gpsPathVersion: number = 0;

export function clearGpsPathPoints(): void {
  gpsPathPoints = [];
  gpsPathVersion = 0;
}

export function appendGpsPathPoints(points: GpsPathPoint[]): void {
  gpsPathPoints = [...gpsPathPoints, ...points];
  gpsPathVersion++;
}
export let lastGeofenceStatus: number = 0;
export let lastHomeLat: number = 0;
export let lastHomeLon: number = 0;
export let lastGpsLat: number = 0;
export let lastGpsLon: number = 0;
export let lastVoiceIntent: string = '';
export let lastAiInterpretation: string = '';

// 缓存的传感器上下文（用于喂给 DeepSeek）
let lastHeartRate: number = 0;
let lastSpo2: number = 0;
let lastActivity: number = 0;
export let lastAnxiety: number = 0;
let lastHealthScore: number = 0;
export let lastEmotion: string = 'CALM';
export let mqttDataReceived: boolean = false;
let lastFeedWeight: number = 0;

async function parseAndStore(payload: string): Promise<void> {
  try {
    // 尝试解析为 pathData 消息
    const possiblePath: PathDataPayload = JSON.parse(payload) as PathDataPayload;
    if (possiblePath.cmd === 'pathData' && possiblePath.points) {
      gpsPathPoints = [...gpsPathPoints, ...possiblePath.points];
      gpsPathVersion++;
      const key = AppStorage.Get<number>('dataUpdateKey') ?? 0;
      AppStorage.SetOrCreate('dataUpdateKey', key + 1);
      console.info('[MQTT] Path data received: ' + gpsPathPoints.length.toString() + ' points');
      return;
    }
  } catch (_err) {
    // 不是 pathData，继续解析标准格式
  }

  try {
    const root: MqttPayload = JSON.parse(payload) as MqttPayload;
    const services: MqttServiceItem[] = root.services;
    if (!services || services.length === 0) {
      return;
    }

    for (let i: number = 0; i < services.length; i++) {
      const props: MqttPropertyBag = services[i].properties;
      if (!props) {
        continue;
      }

      // 固件MQTT发送中文情绪标签，映射为App使用的英文标识
      let rawEmotion: string = props.emotion || 'CALM';
      const cnToEn: Record<string, string> = {
        '高兴': 'HAPPY', '平静': 'CALM', '警觉': 'ALERT', '焦虑': 'ANXIOUS'
      };
      const emotion: string = cnToEn[rawEmotion] || rawEmotion;

      const record: SensorRecord = {
        id: 0,
        temperature: parseFloat(props.temperature) || 0,
        humidity: parseFloat(props.humidity) || 0,
        illumination: parseFloat(props.illumination) || 0,
        anxietyLevel: props.anxietyLevel || 0,
        comfortType: props.comfortType || 0,
        audioSubType: props.audioSubType || 0,
        activityLevel: props.activityLevel || 0,
        emotion: emotion,
        foodWeight: props.foodWeight || 0,
        foodEaten: props.foodEaten || 0,
        heartRate: props.heartRate || 0,
        spo2: props.spo2 || 0,
        gpsLat: props.gpsLat || 0,
        gpsLon: props.gpsLon || 0,
        geofenceStatus: props.geofenceStatus || 0,
        hrvStress: props.hrvStress || 0,
        healthScore: props.healthScore || 0,
        bodyTemp: props.bodyTemp || 0,
        timestamp: Date.now()
      };

      // 更新全局围栏状态
      lastGeofenceStatus = record.geofenceStatus;
      lastGpsLat = record.gpsLat;
      lastGpsLon = record.gpsLon;
      if (props.homeLat && props.homeLon) {
        lastHomeLat = props.homeLat;
        lastHomeLon = props.homeLon;
      }

      // 缓存传感器上下文供 DeepSeek 使用
      lastHeartRate = record.heartRate;
      lastSpo2 = record.spo2;
      lastActivity = record.activityLevel;
      lastAnxiety = record.anxietyLevel;
      lastHealthScore = record.healthScore || 0;
      lastEmotion = record.emotion || 'CALM';
      mqttDataReceived = true;
      if (record.foodWeight > 0) lastFeedWeight = record.foodWeight;

      // 跳过传感器未正常工作的记录（MAX30102 未检测到手指时 HR/SpO2/anxiety 全为 0）
      const hasHealthData: boolean = record.heartRate > 0 || record.spo2 > 30 || record.anxietyLevel > 0;
      if (hasHealthData) {
        await insertSensorRecord(record);
        console.info('[MQTT] Stored: Lv=' + record.anxietyLevel.toString() +
          ' HR=' + record.heartRate.toString() +
          ' SpO2=' + record.spo2.toString() +
          ' GPS=(' + record.gpsLat.toFixed(4) + ',' + record.gpsLon.toFixed(4) + ')' +
          ' Geo=' + record.geofenceStatus.toString());
      } else {
        console.info('[MQTT] Skipped zero-health record (sensor not ready)');
      }
      checkAndNotifyAnxiety(record.anxietyLevel);
    }
    const key = AppStorage.Get<number>('dataUpdateKey') ?? 0;
    AppStorage.SetOrCreate('dataUpdateKey', key + 1);
  } catch (_err) {
    console.error('[MQTT] parse error');
  }
}

export async function startMqttService(): Promise<void> {
  if (isMqttReady()) {
    console.info('[MQTT] Already connected, skipping');
    return;
  }

  console.info('[MQTT] Connecting to HiveMQ via TCP...');

  onMqttMessage((topic: string, payload: string) => {
    console.info('[MQTT] Received topic=' + topic + ' len=' + payload.length.toString());
    if (topic === VOICE_INTENT_TOPIC) {
      try {
        const data = JSON.parse(payload) as VoiceIntentPayload;
        const intent = data.intent || payload;
        lastVoiceIntent = intent;
        console.info('[MQTT] Voice intent received: ' + intent);

        // 触发 DeepSeek AI 分析
        const ctx: PetStateContext = {
          species: 'cat',  // 默认猫，后续可从设置获取
          voiceIntent: intent,
          voiceConfidence: 0.85,
          heartRate: lastHeartRate,
          spo2: lastSpo2,
          activityLevel: lastActivity,
          anxietyLevel: lastAnxiety,
          healthScore: lastHealthScore,
          emotion: lastEmotion,
          lastFeedHours: 0,
          timeOfDay: new Date().getHours().toString() + '点'
        };
        analyzePetState(ctx).then((result: string) => {
          lastAiInterpretation = result;
          const key = AppStorage.Get<number>('dataUpdateKey') ?? 0;
          AppStorage.SetOrCreate('dataUpdateKey', key + 1);
        });
      } catch (_e) {
        lastVoiceIntent = payload;
      }
      return;
    }
    parseAndStore(payload);
  });

  const connected: boolean = await mqttConnect(CLIENT_ID);
  if (connected) {
    await mqttSubscribe(SUBSCRIBE_TOPIC);
    await mqttSubscribe(VOICE_INTENT_TOPIC);
    console.info('[MQTT] Connected & subscribed to HiveMQ');
  } else {
    console.error('[MQTT] Connection failed — no data will be received');
  }
}

export async function sendRefreshCommand(): Promise<void> {
  if (!isMqttReady()) {
    console.error('[MQTT] Cannot send refresh — not connected');
    return;
  }
  await mqttPublish(COMMAND_TOPIC, '{"cmd":"refresh"}');
}

export async function sendComfortCommand(
  comfortType: number = 1,
  audioSubType: number = 0
): Promise<void> {
  if (!isMqttReady()) {
    console.error('[MQTT] Cannot send comfort — not connected');
    return;
  }
  let cmd: string;
  if (comfortType === 2 && audioSubType > 0) {
    cmd = '{"cmd":"comfort","type":2,"audioSubType":' + audioSubType.toString() + '}';
  } else {
    cmd = '{"cmd":"comfort","type":' + comfortType.toString() + '}';
  }
  await mqttPublish(COMMAND_TOPIC, cmd);
  console.info('[MQTT] Comfort sent: type=' + comfortType.toString() +
    ' audioSubType=' + audioSubType.toString());
}

export async function sendFeedCommand(amount: number): Promise<void> {
  if (!isMqttReady()) {
    console.error('[MQTT] Cannot send feed — not connected');
    return;
  }
  const cmd: string = '{"cmd":"feed","amount":' + amount.toString() + '}';
  await mqttPublish(COMMAND_TOPIC, cmd);
}

export async function sendSetHomeCommand(): Promise<void> {
  if (!isMqttReady()) {
    console.error('[MQTT] Cannot send setHome — not connected');
    return;
  }
  await mqttPublish(COMMAND_TOPIC, '{"cmd":"setHome"}');
  console.info('[MQTT] setHome command sent');
}

export async function sendGetPathCommand(): Promise<void> {
  if (!isMqttReady()) {
    console.error('[MQTT] Cannot send getPath — not connected');
    return;
  }
  await mqttPublish(COMMAND_TOPIC, '{"cmd":"getPath"}');
  console.info('[MQTT] getPath command sent');
}

export interface SchedulePlanItem {
  time: string;
  amount: number;
  enabled: boolean;
}

export async function sendScheduleSyncCommand(plans: SchedulePlanItem[]): Promise<void> {
  if (!isMqttReady()) {
    console.error('[MQTT] Cannot send scheduleSync — not connected');
    return;
  }
  const cmd = JSON.stringify({ cmd: 'scheduleSync', plans: plans });
  await mqttPublish(COMMAND_TOPIC, cmd);
  console.info('[MQTT] scheduleSync sent: ' + plans.length.toString() + ' plans');
}

export async function sendTimeSyncCommand(): Promise<void> {
  if (!isMqttReady()) {
    console.error('[MQTT] Cannot send timeSync — not connected');
    return;
  }
  const ts = Math.floor(Date.now() / 1000);
  const cmd = JSON.stringify({ cmd: 'timeSync', ts: ts });
  await mqttPublish(COMMAND_TOPIC, cmd);
  console.info('[MQTT] timeSync sent: ts=' + ts.toString());
}

export async function sendPetSoundCommand(species: string, intent: string): Promise<void> {
  if (!isMqttReady()) {
    console.error('[MQTT] Cannot send playSound — not connected');
    return;
  }
  const cmd: string = JSON.stringify({ cmd: 'playSound', species: species, intent: intent });
  await mqttPublish(COMMAND_TOPIC, cmd);
  console.info('[MQTT] playSound sent: ' + species + ' ' + intent);
}

export function getConnectionStatus(): boolean {
  return isMqttReady();
}
