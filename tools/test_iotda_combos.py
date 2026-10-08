# -*- coding: utf-8 -*-
"""穷尽测试：IoTDA 一机一密 8 种组合（时间戳×签名类型×HMAC顺序）

用法: python test_iotda_combos.py <device_id> <device_secret> [host] [port]
"""
import hashlib, hmac, socket, struct, sys, time

HOST = "5256547599.st1.iotda-device.cn-north-4.myhuaweicloud.com"
PORT = 1883

def enc_len(n):
    out = bytearray()
    while True:
        d = n % 128; n //= 128
        if n: d |= 0x80
        out.append(d)
        if n == 0: return bytes(out)

def mstr(s):
    b = s.encode(); return struct.pack(">H", len(b)) + b

def pwd(ts, sec, order):
    if order == "ts_key":     # key=时间戳, msg=设备密钥 (官方Java Demo)
        return hmac.new(ts.encode(), sec.encode(), hashlib.sha256).hexdigest()
    else:                     # key=设备密钥, msg=时间戳 (早期实现)
        return hmac.new(sec.encode(), ts.encode(), hashlib.sha256).hexdigest()

def try_connect(sig, ts, sec, order):
    cid = "%s_0_%d_%s" % (DEV, sig, ts)
    body = mstr("MQTT") + bytes([4, 0xC2]) + struct.pack(">H", 60) + mstr(cid) + mstr(DEV) + mstr(pwd(ts, sec, order))
    pkt = bytes([0x10]) + enc_len(len(body)) + body
    s = socket.create_connection((HOST, PORT), timeout=10)
    s.sendall(pkt)
    r = s.recv(4)
    s.close()
    return r[3] if len(r) == 4 else -1

loc_ts = time.strftime("%Y%m%d%H", time.localtime())
utc_ts = time.strftime("%Y%m%d%H", time.gmtime())
print("本地ts=%s  UTC ts=%s" % (loc_ts, utc_ts))

if len(sys.argv) < 3:
    print(__doc__)
    sys.exit(1)
DEV = sys.argv[1]
SEC = sys.argv[2]
if len(sys.argv) > 3:
    HOST = sys.argv[3]
if len(sys.argv) > 4:
    PORT = int(sys.argv[4])

results = []
for ts_name, ts in [("本地", loc_ts), ("UTC ", utc_ts)]:
    for sig in (0, 1):
        for order_name, order in [("key=ts ", "ts_key"), ("key=sec", "sec_key")]:
            code = try_connect(sig, ts, SEC, order)
            mark = "✅ 成功" if code == 0 else ""
            results.append((code, "%s ts %s _0_%d_ hmac(%s)" % (ts_name, ts, sig, order_name)))
            print("%s -> CONNACK=%d %s" % (results[-1][1], code, mark))
print("---")
ok = [r for r in results if r[0] == 0]
print("成功组合: %d 个 %s" % (len(ok), [r[1] for r in ok]))
