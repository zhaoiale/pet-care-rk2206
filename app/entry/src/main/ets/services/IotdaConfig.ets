/**
 * IotdaConfig.ets — 华为云 IoTDA（设备接入服务）配置与一机一密认证
 *
 * 【改造说明 2026-10-08】
 * 原项目使用 HiveMQ 公共 broker（broker.hivemq.com:1883），自由主题互发。
 * 现按 HarmonyOS_Life/water（hydromate）的华为云 IoTDA 方案改造：
 *   - 平台地址：https://console.huaweicloud.com/iotdm（IoTDA 设备接入服务）
 *   - 接入方式：MQTT 一机一密（1883 明文）
 *       clientId = {device_id}_0_0_{timestamp}   （timestamp = YYYYMMDDHH，小时级）
 *       username = {device_id}
 *       password = hex( HMAC-SHA256(timestamp, 设备密钥) )
 *   - 主题：$oc/devices/{device_id}/sys/... 系统主题（带设备归属校验）
 *
 * 【南北向角色】
 *   - 南向板子（RK2206 主控）：注册设备 A（复用饮水项目的 rk2206_water01）
 *       上报属性 -> $oc/devices/A/sys/properties/report
 *       订阅下行 -> $oc/devices/A/sys/messages/down
 *   - 北向 App（本应用）：注册独立设备 B（pet_app01，必须新建！
 *       IoTDA 一机一密同一 device_id 只允许一个在线连接，App 与板子不能共用）
 *       订阅下行 -> $oc/devices/B/sys/messages/down（收平台消息）
 *       发布上行 -> $oc/devices/B/sys/messages/up  （指令经平台转发）
 *
 * 【注意】
 *   - App 端密码由 buildIotdaAuth() 运行时动态计算，永不过期；
 *   - 板子端固件是 C 语言、无 mbedtls，采用"预计算凭证写死"方式
 *     （见 hardware_src/src/iot.c 与 tools/gen_iotda_credential.py，按小时生成）。
 */
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';

export class IotdaConfig {
  /** IoTDA 实例接入地址（华北-北京四，复用饮水项目的实例） */
  static readonly HOST: string = '5256547599.st1.iotda-device.cn-north-4.myhuaweicloud.com';
  /** MQTT 端口：1883 明文 */
  static readonly PORT: number = 1883;

  /**
   * App 设备 ID（北向独立设备，已注册）
   * 已在 IoTDA 控制台注册：设备标识码 pet_app01 -> 设备ID 6aa9198b7f2e6c302f999974_pet_app01
   */
  static readonly APP_DEVICE_ID: string = '6aa9198b7f2e6c302f999974_pet_app01';
  /**
   * App 设备密钥（设备接入 IoTDA 控制台注册时平台自动生成）
   * 仓库内为占位，演示前请填入真实密钥（控制台 设备详情 -> 设备密钥）。
   * 用于运行时动态计算 HMAC-SHA256 密码，请勿泄露。
   */
  static readonly APP_DEVICE_SECRET: string = '请填入App设备密钥';

  /** 物模型服务 ID（控制台 产品 -> 模型定义 中创建的服务名，需一致） */
  static readonly SERVICE_ID: string = 'petCare';

  // ============ $oc 主题（App 设备 B） ============
  /** 上行：消息上报（App 指令 -> 平台，可配置规则转发/手动下发给板子） */
  static readonly TOPIC_MSG_UP: string = '$oc/devices/' + IotdaConfig.APP_DEVICE_ID + '/sys/messages/up';
  /** 下行：平台消息下发（App 订阅） */
  static readonly TOPIC_MSG_DOWN: string = '$oc/devices/' + IotdaConfig.APP_DEVICE_ID + '/sys/messages/down';

  /** 保活间隔（秒） */
  static readonly KEEP_ALIVE: number = 60;
}

/**
 * 一机一密认证结果
 */
export interface IotdaAuth {
  clientId: string;
  username: string;
  password: string;
  timestamp: string;
}

/**
 * 生成 IoTDA 一机一密连接参数（动态计算，随当前小时有效，无需手动维护）
 *   clientId = deviceId_0_0_YYYYMMDDHH
 *   username = deviceId
 *   password = hex( HMAC-SHA256(YYYYMMDDHH, secret) )
 */
export async function buildIotdaAuth(): Promise<IotdaAuth> {
  const ts: string = iotdaTimestamp(new Date());
  // IoTDA 一机一密：Password = HMAC-SHA256(密钥=时间戳, 内容=设备密钥)
  // 官方定义：Password = hmacsha256("secret", "时间戳")，即 key=时间戳, message=设备密钥
  const password: string = await hmacSha256Hex(IotdaConfig.APP_DEVICE_SECRET, ts);
  return {
    clientId: IotdaConfig.APP_DEVICE_ID + '_0_0_' + ts,
    username: IotdaConfig.APP_DEVICE_ID,
    password: password,
    timestamp: ts
  };
}

/** 当前时间 -> YYYYMMDDHH（IoTDA 一机一密时间戳格式，10 位） */
function iotdaTimestamp(d: Date): string {
  const y: string = d.getFullYear().toString();
  const mo: string = pad2(d.getMonth() + 1);
  const da: string = pad2(d.getDate());
  const h: string = pad2(d.getHours());
  return y + mo + da + h;
}

function pad2(n: number): string {
  return n < 10 ? '0' + n.toString() : n.toString();
}

/** HMAC-SHA256 计算并返回小写 hex 字符串 */
async function hmacSha256Hex(message: string, key: string): Promise<string> {
  const mac = cryptoFramework.createMac('HMAC|SHA256');
  const encoder = new util.TextEncoder();
  const keyBlob: cryptoFramework.DataBlob = { data: encoder.encodeInto(key) };
  await mac.init(keyBlob);
  const msgBlob: cryptoFramework.DataBlob = { data: encoder.encodeInto(message) };
  await mac.update(msgBlob);
  const out: cryptoFramework.DataBlob = await mac.doFinal();
  return bytesToHex(out.data);
}

/** Uint8Array -> 小写 hex 字符串 */
function bytesToHex(bytes: Uint8Array): string {
  let hex: string = '';
  for (let i = 0; i < bytes.length; i++) {
    hex += bytes[i].toString(16).padStart(2, '0');
  }
  return hex;
}
