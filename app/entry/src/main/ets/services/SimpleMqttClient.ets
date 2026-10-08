// SimpleMqttClient.ets — MQTT-over-TCP 客户端
// 使用 @ohos.net.socket 直连 MQTT broker TCP 端口 1883
// 【2026-10-08 改造】broker 由 HiveMQ 公共改为华为云 IoTDA（一机一密认证）
import socket from '@ohos.net.socket';
import connection from '@ohos.net.connection';
import { IotdaConfig } from './IotdaConfig';

const BROKER_HOST: string = IotdaConfig.HOST;
const BROKER_PORT: number = IotdaConfig.PORT;

interface TcpMessageEvent {
  message: ArrayBuffer;
  remoteInfo: socket.SocketRemoteInfo;
}

let tcp: socket.TCPSocket | null = null;
let onMessageCallback: ((topic: string, payload: string) => void) | null = null;
let savedClientId: string = '';
let savedUsername: string = '';
let savedPassword: string = '';
let subscribedTopics: string[] = [];
let reconnectTimer: number = -1;
let reconnectAttempts: number = 0;
let heartbeatTimer: number = -1;

// 接收缓冲区
let rxBuffer: Uint8Array = new Uint8Array(0);

// ---- MQTT 编码 ----

function encodeRemainingLength(length: number): number[] {
  const bytes: number[] = [];
  let l: number = length;
  do {
    let digit: number = l % 128;
    l = Math.floor(l / 128);
    if (l > 0) {
      digit = digit | 0x80;
    }
    bytes.push(digit);
  } while (l > 0);
  return bytes;
}

function encodeMqttStr(s: string): number[] {
  const bytes: number[] = [];
  for (let i: number = 0; i < s.length; i++) {
    bytes.push(s.charCodeAt(i));
  }
  return [(bytes.length >> 8) & 0xFF, bytes.length & 0xFF, ...bytes];
}

function buildConnectPacket(clientId: string, username?: string, password?: string): ArrayBuffer {
  const protocolName: number[] = [0x00, 0x04, 0x4D, 0x51, 0x54, 0x54];
  const protocolLevel: number = 0x04;
  let connectFlags: number = 0x02;
  const keepAlive: number[] = [0x00, 0x3C];

  const payloadParts: number[] = [...encodeMqttStr(clientId)];

  if (username !== undefined && username.length > 0) {
    connectFlags |= 0x80;
    payloadParts.push(...encodeMqttStr(username));
  }
  if (password !== undefined && password.length > 0) {
    connectFlags |= 0x40;
    payloadParts.push(...encodeMqttStr(password));
  }

  const variableHeader: number[] = [
    ...protocolName, protocolLevel, connectFlags, ...keepAlive
  ];
  const payload: number[] = payloadParts;
  const remainingLen: number = variableHeader.length + payload.length;

  const packet: number[] = [0x10, ...encodeRemainingLength(remainingLen), ...variableHeader, ...payload];
  const buf: ArrayBuffer = new ArrayBuffer(packet.length);
  const view: Uint8Array = new Uint8Array(buf);
  for (let i: number = 0; i < packet.length; i++) {
    view[i] = packet[i];
  }
  return buf;
}

function buildSubscribePacket(topic: string, packetId: number): ArrayBuffer {
  const topicBytes: number[] = [];
  for (let i: number = 0; i < topic.length; i++) {
    topicBytes.push(topic.charCodeAt(i));
  }
  const topicLen: number[] = [(topicBytes.length >> 8) & 0xFF, topicBytes.length & 0xFF];
  const qos: number = 0x00;

  const variableHeader: number[] = [(packetId >> 8) & 0xFF, packetId & 0xFF];
  const payload: number[] = [...topicLen, ...topicBytes, qos];
  const remainingLen: number = variableHeader.length + payload.length;

  const packet: number[] = [0x82, ...encodeRemainingLength(remainingLen), ...variableHeader, ...payload];
  const buf: ArrayBuffer = new ArrayBuffer(packet.length);
  const view: Uint8Array = new Uint8Array(buf);
  for (let i: number = 0; i < packet.length; i++) {
    view[i] = packet[i];
  }
  return buf;
}

function buildPublishPacket(topic: string, payload: string): ArrayBuffer {
  const topicBytes: number[] = [];
  for (let i: number = 0; i < topic.length; i++) {
    topicBytes.push(topic.charCodeAt(i));
  }
  const topicLen: number[] = [(topicBytes.length >> 8) & 0xFF, topicBytes.length & 0xFF];

  const payloadBytes: number[] = [];
  for (let i: number = 0; i < payload.length; i++) {
    payloadBytes.push(payload.charCodeAt(i));
  }

  const remainingLen: number = topicLen.length + topicBytes.length + payloadBytes.length;
  const packet: number[] = [0x30, ...encodeRemainingLength(remainingLen), ...topicLen, ...topicBytes, ...payloadBytes];
  const buf: ArrayBuffer = new ArrayBuffer(packet.length);
  const view: Uint8Array = new Uint8Array(buf);
  for (let i: number = 0; i < packet.length; i++) {
    view[i] = packet[i];
  }
  return buf;
}

function buildPingreqPacket(): ArrayBuffer {
  const packet: number[] = [0xC0, 0x00];
  const buf: ArrayBuffer = new ArrayBuffer(packet.length);
  const view: Uint8Array = new Uint8Array(buf);
  view[0] = 0xC0;
  view[1] = 0x00;
  return buf;
}

// ---- MQTT 解码 ----

interface MqttPublishResult {
  topic: string;
  payload: string;
}

// 解析剩余长度，返回 [value, bytesConsumed]
function decodeRemainingLength(bytes: Uint8Array, offset: number): [number, number] {
  let value: number = 0;
  let multiplier: number = 1;
  let pos: number = offset;
  while (pos < bytes.length) {
    const digit: number = bytes[pos];
    pos++;
    value += (digit & 0x7F) * multiplier;
    if ((digit & 0x80) === 0) {
      break;
    }
    multiplier *= 128;
    if (multiplier > 128 * 128 * 128) {
      break; // 防止畸形报文
    }
  }
  return [value, pos - offset];
}

function parsePublishPacket(data: Uint8Array): MqttPublishResult | null {
  if (data.length < 4 || (data[0] & 0xF0) !== 0x30) {
    return null;
  }

  const decoded = decodeRemainingLength(data, 1);
  const remainingLen: number = decoded[0];
  const rlBytes: number = decoded[1];
  let pos: number = 1 + rlBytes;

  if (pos + 2 > data.length) return null;
  const topicLen: number = (data[pos] << 8) | data[pos + 1];
  pos += 2;

  if (pos + topicLen > data.length) return null;
  let topic: string = '';
  for (let i: number = 0; i < topicLen; i++) {
    topic += String.fromCharCode(data[pos + i]);
  }
  pos += topicLen;

  const headerSize: number = 1 + rlBytes + 2 + topicLen;
  const payloadLen: number = remainingLen - 2 - topicLen;
  let payloadStr: string = '';
  for (let i: number = 0; i < payloadLen; i++) {
    payloadStr += String.fromCharCode(data[pos + i]);
  }

  return { topic: topic, payload: payloadStr };
}

// 从接收缓冲区中提取一个完整的 MQTT 报文
function extractPacket(): Uint8Array | null {
  if (rxBuffer.length < 2) {
    return null;
  }

  const decoded = decodeRemainingLength(rxBuffer, 1);
  const remainingLen: number = decoded[0];
  const rlBytes: number = decoded[1];
  const totalLen: number = 1 + rlBytes + remainingLen;

  if (rxBuffer.length < totalLen) {
    return null;
  }

  const packet: Uint8Array = rxBuffer.slice(0, totalLen);
  rxBuffer = rxBuffer.slice(totalLen);
  return packet;
}

// ---- 连接状态 ----

let mqttConnected: boolean = false;

export function isMqttReady(): boolean {
  return mqttConnected;
}

// ---- 公开接口 ----

export async function mqttConnect(clientId: string, username?: string, password?: string): Promise<boolean> {
  try {
    savedClientId = clientId;
    if (username !== undefined && username !== null) {
      savedUsername = username;
    }
    if (password !== undefined && password !== null) {
      savedPassword = password;
    }
    tcp = socket.constructTCPSocketInstance();

    // 注册消息接收回调
    tcp.on('message', (value: TcpMessageEvent) => {
      const msg: ArrayBuffer = value.message;
      if (msg === undefined || msg === null) {
        return;
      }

      // 追加到接收缓冲区
      const newBytes: Uint8Array = new Uint8Array(msg);
      const merged: Uint8Array = new Uint8Array(rxBuffer.length + newBytes.length);
      merged.set(rxBuffer, 0);
      merged.set(newBytes, rxBuffer.length);
      rxBuffer = merged;

      // 循环提取完整报文
      let packet: Uint8Array | null = extractPacket();
      while (packet !== null) {
        const pktType: number = packet[0] & 0xF0;

        if (pktType === 0x20) {
          // CONNACK
          const code: number = packet.length >= 4 ? packet[3] : -1;
          if (code === 0) {
            mqttConnected = true;
            reconnectAttempts = 0;
            console.info('[MQTT-TCP] CONNACK accepted');
          } else {
            console.error('[MQTT-TCP] CONNACK rejected, code=' + code.toString());
          }
        } else if (pktType === 0x30) {
          // PUBLISH
          const pub: MqttPublishResult | null = parsePublishPacket(packet);
          if (pub !== null && onMessageCallback !== null) {
            onMessageCallback(pub.topic, pub.payload);
          }
        } else if (pktType === 0x90) {
          console.info('[MQTT-TCP] SUBACK received');
        } else if (pktType === 0xD0) {
          console.info('[MQTT-TCP] PINGRESP received');
        } else {
          let hex = '';
          for (let j = 0; j < Math.min(packet.length, 16); j++) {
            hex += packet[j].toString(16).padStart(2, '0') + ' ';
          }
          console.info('[MQTT-TCP] Unknown packet type=0x' + pktType.toString(16) + ' len=' + packet.length.toString() + ': ' + hex);
        }

        packet = extractPacket();
      }
    });

    tcp.on('close', () => {
      console.info('[MQTT-TCP] Connection closed');
      mqttConnected = false;
      tcp = null;
      rxBuffer = new Uint8Array(0);
      if (heartbeatTimer !== -1) {
        clearInterval(heartbeatTimer);
        heartbeatTimer = -1;
      }
      // 自动重连
      if (reconnectTimer === -1) {
        scheduleReconnect();
      }
    });

    tcp.on('error', (err: Error) => {
      console.error('[MQTT-TCP] Error: ' + JSON.stringify(err));
    });

    // DNS 预解析诊断
    try {
      const addrList = await connection.getAddressesByName(BROKER_HOST);
      let ipList: string = '';
      for (let i: number = 0; i < addrList.length; i++) {
        if (i > 0) ipList += ', ';
        ipList += addrList[i].address;
      }
      console.info('[MQTT-TCP] DNS resolved ' + BROKER_HOST + ' → [' + ipList + ']');
    } catch (dnsErr) {
      console.error('[MQTT-TCP] DNS resolution failed for ' + BROKER_HOST + ': ' + JSON.stringify(dnsErr));
    }

    // 连接到 broker
    console.info('[MQTT-TCP] Connecting to ' + BROKER_HOST + ':' + BROKER_PORT.toString());
    const connectOpt: socket.TCPConnectOptions = {
      address: {
        address: BROKER_HOST,
        port: BROKER_PORT,
        family: 1
      },
      timeout: 10000
    };
    await tcp.connect(connectOpt);
    console.info('[MQTT-TCP] TCP connected');

    // 发送 MQTT CONNECT（IoTDA 一机一密：clientId + username + password）
    const connectPkt: ArrayBuffer = buildConnectPacket(clientId, username, password);
    const dbg: Uint8Array = new Uint8Array(connectPkt);
    let hex: string = '';
    for (let j: number = 0; j < Math.min(20, dbg.length); j++) {
      hex += dbg[j].toString(16).padStart(2, '0') + ' ';
    }
    console.info('[MQTT-TCP] CONNECT packet(' + dbg.length.toString() + 'b): ' + hex);
    await tcp.send({ data: connectPkt });
    console.info('[MQTT-TCP] CONNECT packet sent');

    // 等待 CONNACK（最多 10 秒）
    for (let i: number = 0; i < 100; i++) {
      if (mqttConnected) break;
      await new Promise<void>((r) => setTimeout(r, 100));
    }

    if (!mqttConnected) {
      console.error('[MQTT-TCP] No CONNACK in 10s');
      return false;
    }

    // 启动心跳（每 50 秒发送 PINGREQ），先清除旧定时器
    if (heartbeatTimer !== -1) {
      clearInterval(heartbeatTimer);
      heartbeatTimer = -1;
    }
    heartbeatTimer = setInterval(() => {
      if (tcp !== null && mqttConnected) {
        try {
          tcp.send({ data: buildPingreqPacket() });
        } catch (e) {
          // ignore
        }
      }
    }, 50000);

    return true;
  } catch (err) {
    console.error('[MQTT-TCP] Setup failed: ' + JSON.stringify(err));
    return false;
  }
}

export async function mqttSubscribe(topic: string): Promise<void> {
  if (tcp === null || !mqttConnected) {
    console.error('[MQTT-TCP] Not connected');
    return;
  }

  const packetId: number = Math.floor(Math.random() * 65535) + 1;
  const subscribePkt: ArrayBuffer = buildSubscribePacket(topic, packetId);
  await tcp.send({ data: subscribePkt });
  if (subscribedTopics.indexOf(topic) === -1) {
    subscribedTopics.push(topic);
  }
  console.info('[MQTT-TCP] Subscribed to: ' + topic);
}

export async function mqttPublish(topic: string, payload: string): Promise<void> {
  if (tcp === null || !mqttConnected) {
    console.error('[MQTT-TCP] Cannot publish — not connected');
    return;
  }

  try {
    const publishPkt: ArrayBuffer = buildPublishPacket(topic, payload);
    await tcp.send({ data: publishPkt });
    console.info('[MQTT-TCP] Published to ' + topic + ': ' + payload);
  } catch (err) {
    console.error('[MQTT-TCP] Publish failed, triggering reconnect: ' + JSON.stringify(err));
    mqttConnected = false;
    if (tcp !== null) {
      try { tcp.close(); } catch (_e) { /* ignore */ }
      tcp = null;
    }
    if (reconnectTimer === -1) {
      scheduleReconnect();
    }
  }
}

export function onMqttMessage(callback: (topic: string, payload: string) => void): void {
  onMessageCallback = callback;
}

function scheduleReconnect(): void {
  if (reconnectTimer !== -1) {
    return;
  }
  const delay: number = Math.min(5000 * (1 << Math.min(reconnectAttempts, 4)), 60000);
  reconnectAttempts++;
  console.info('[MQTT-TCP] Reconnect #' + reconnectAttempts.toString() + ' in ' + (delay / 1000).toString() + 's');
  reconnectTimer = setTimeout(() => {
    reconnectTimer = -1;
    doReconnect();
  }, delay);
}

async function doReconnect(): Promise<void> {
  try {
    // 重连沿用保存的 IoTDA 一机一密认证参数（注意：密码随小时有效，
    // 若断线跨越整点，重新调用 mqttConnect 前请由调用方刷新 auth）
    const ok: boolean = await mqttConnect(savedClientId, savedUsername, savedPassword);
    if (!ok) {
      scheduleReconnect();
      return;
    }
    for (let i: number = 0; i < subscribedTopics.length; i++) {
      await mqttSubscribe(subscribedTopics[i]);
    }
    console.info('[MQTT-TCP] Reconnected & re-subscribed');
  } catch (err) {
    console.error('[MQTT-TCP] Reconnect failed: ' + JSON.stringify(err));
    scheduleReconnect();
  }
}

export function disconnect(): void {
  if (reconnectTimer !== -1) {
    clearTimeout(reconnectTimer);
    reconnectTimer = -1;
  }
  reconnectAttempts = 0;
  subscribedTopics = [];
  if (heartbeatTimer !== -1) {
    clearInterval(heartbeatTimer);
    heartbeatTimer = -1;
  }
  if (tcp !== null) {
    tcp.close();
    tcp = null;
  }
  mqttConnected = false;
  rxBuffer = new Uint8Array(0);
}
