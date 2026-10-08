# -*- coding: utf-8 -*-
"""
gen_iotda_credential.py — 华为云 IoTDA 一机一密凭证生成工具（南向固件用）

用法:
    python gen_iotda_credential.py <device_id> <device_secret>

说明:
    IoTDA 一机一密连接参数为:
      clientId = {device_id}_0_0_{timestamp}
      username = {device_id}
      password = hex( HMAC-SHA256(timestamp, device_secret) )
    timestamp = YYYYMMDDHH（小时级有效，过期后连接被拒，需重新生成并烧录）

示例:
    python gen_iotda_credential.py 6aa9198b7f2e6c302f999974_rk2206_water01 <你的设备密钥>

输出:
    - 可直接替换 hardware_src/src/iot.c 顶部三个宏的代码段
"""
import hashlib
import hmac
import sys
import time


def gen(device_id: str, secret: str):
    # timestamp: YYYYMMDDHH（本地时间，小时级）
    ts = time.strftime("%Y%m%d%H", time.localtime())
    client_id = "%s_0_0_%s" % (device_id, ts)
    password = hmac.new(ts.encode("utf-8"), secret.encode("utf-8"),
                        hashlib.sha256).hexdigest()

    print("=" * 60)
    print("IoTDA 一机一密凭证（生成时间: %s）" % time.strftime("%Y-%m-%d %H:%M:%S"))
    print("=" * 60)
    print("device_id : %s" % device_id)
    print("timestamp : %s  (本小时有效，过期需重新生成)" % ts)
    print("clientId  : %s" % client_id)
    print("username  : %s" % device_id)
    print("password  : %s" % password)
    print("=" * 60)
    print("替换 hardware_src/src/iot.c 顶部宏（DEVICE_ID / CLIENT_ID / MQTT_DEVICES_PWD）:")
    print("")
    print('    #define DEVICE_ID "%s"' % device_id)
    print('    #define CLIENT_ID  "%s"' % client_id)
    print('    #define MQTT_DEVICES_PWD "%s"  /* HMAC-SHA256(%s, 设备密钥) */'
          % (password, ts))
    print("=" * 60)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    gen(sys.argv[1], sys.argv[2])
