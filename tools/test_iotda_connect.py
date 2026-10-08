# -*- coding: utf-8 -*-
"""
test_iotda_connect.py — 验证 IoTDA 一机一密凭证能否成功连接（纯 socket，无三方依赖）

用法:
    python test_iotda_connect.py <device_id> <device_secret> [host] [port]

说明:
    与 App 端 IotdaConfig.buildIotdaAuth() 使用完全相同的算法:
      timestamp = YYYYMMDDHH（当前小时）
      clientId  = device_id_0_0_timestamp
      username  = device_id
      password  = hex(HMAC-SHA256(timestamp, secret))
    发送 MQTT CONNECT 并读取 CONNACK，返回码 0 表示连接成功。
"""
import hashlib
import hmac
import socket
import struct
import sys
import time


def encode_mqtt_str(s: str) -> bytes:
    b = s.encode("utf-8")
    return struct.pack(">H", len(b)) + b


def encode_remaining_length(length: int) -> bytes:
    """MQTT 剩余长度变长编码（1~4 字节）"""
    out = bytearray()
    while True:
        digit = length % 128
        length //= 128
        if length > 0:
            digit |= 0x80
        out.append(digit)
        if length == 0:
            return bytes(out)


def build_connect_pkt(client_id: str, username: str, password: str) -> bytes:
    # 可变头部: 协议名 MQTT + 级别4 + 连接标志(用户名+密码+清会话) + 保活60
    flags = 0x00
    flags |= 0x02        # clean session
    flags |= 0x80        # username flag
    flags |= 0x40        # password flag
    var_header = encode_mqtt_str("MQTT") + bytes([4, flags]) + struct.pack(">H", 60)
    payload = encode_mqtt_str(client_id) + encode_mqtt_str(username) + encode_mqtt_str(password)
    body = var_header + payload
    # 固定头部: 0x10 CONNECT + 剩余长度（变长编码）
    return bytes([0x10]) + encode_remaining_length(len(body)) + body


def test(device_id: str, secret: str, host: str, port: int) -> int:
    ts = time.strftime("%Y%m%d%H", time.localtime())
    client_id = "%s_0_0_%s" % (device_id, ts)
    password = hmac.new(ts.encode("utf-8"), secret.encode("utf-8"),
                        hashlib.sha256).hexdigest()
    print("timestamp : %s" % ts)
    print("clientId  : %s" % client_id)
    print("username  : %s" % device_id)
    print("password  : %s" % password)

    pkt = build_connect_pkt(client_id, device_id, password)
    s = socket.create_connection((host, port), timeout=15)
    s.sendall(pkt)
    resp = s.recv(4)
    s.close()
    if len(resp) < 4:
        print("ERROR: 未收到 CONNACK")
        return -1
    # 固定头 0x20, 剩余长度2, 第4字节 = 返回码
    code = resp[3]
    reasons = {
        0: "连接成功（CONNACK=0）✅",
        1: "拒绝：协议版本不支持",
        2: "拒绝：标识符不可用",
        3: "拒绝：服务器不可用",
        4: "拒绝：用户名或密码错误（设备ID/密钥/时间戳问题）",
        5: "拒绝：未授权",
    }
    print("CONNACK=%d -> %s" % (code, reasons.get(code, "未知返回码")))
    return code


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    dev = sys.argv[1]
    sec = sys.argv[2]
    h = sys.argv[3] if len(sys.argv) > 3 else "5256547599.st1.iotda-device.cn-north-4.myhuaweicloud.com"
    p = int(sys.argv[4]) if len(sys.argv) > 4 else 1883
    code = test(dev, sec, h, p)
    sys.exit(0 if code == 0 else 1)
