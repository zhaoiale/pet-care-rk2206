"""
情绪识别线上仿真 — 通过 MQTT 向 App 发送模拟情绪数据
用法: python anxiety_simulator.py
依赖: pip install paho-mqtt
"""

import paho.mqtt.client as mqtt
import json
import time
import random

BROKER = "broker.hivemq.com"
PORT = 1883
TOPIC = "petcare/device/data"

# 情绪标签: 高兴/平静/警觉/焦虑
# 阈值:    0-15 / 16-35 / 36-60 / 61-100

SCENARIO = [
    # 阶段1: 宠物高兴在家 (0-5s)
    (5,   8,  "HAPPY",   0, "宠物在家中开心玩耍"),
    # 阶段2: 听到门外动静，转为平静观察 (5-10s)
    (5,  25,  "CALM",    0, "检测到门外异响，宠物平静观察"),
    # 阶段3: 持续异常，警觉状态 (10-20s)
    (10, 48,  "ALERT",   1, "异常行为持续，宠物警觉抬头"),
    # 阶段4: 触发安抚，焦虑上升 (20-25s)
    (5,  72,  "ANXIOUS", 3, "触发主动安抚：灯光+语音安慰"),
    # 阶段5: 安抚生效，焦虑下降 (25-35s)
    (10, 40,  "ALERT",   2, "安抚生效中，焦虑逐渐降低"),
    # 阶段6: 恢复平静 (35-42s)
    (7,  20,  "CALM",    0, "宠物恢复平静，系统回到监测模式"),
    # 阶段7: 恢复开心 (42-48s)
    (6,   8,  "HAPPY",   0, "宠物恢复开心，演示结束"),
]

def build_payload(anxiety, emotion, comfort, activity=0, hr=0, spo2=0,
                  temp=25.5, humi=60.0, lum=1234.0, food=150.0, eaten=0,
                  lat=34.1084, lon=109.0030, geofence=0):
    """构造与固件一致的 MQTT JSON"""
    return json.dumps({
        "services": [{
            "service_id": "petCare",
            "properties": {
                "illumination": f"{lum:.2f}Lux",
                "temperature": f"{temp:.2f}",
                "humidity": f"{humi:.2f}",
                "motorStatus": "OFF",
                "lightStatus": "OFF",
                "autoStatus": "ON",
                "anxietyLevel": anxiety,
                "comfortType": comfort,
                "audioSubType": 0,
                "activityLevel": activity,
                "exceedCount": 0,
                "emotion": emotion,
                "foodWeight": food,
                "foodEaten": eaten,
                "heartRate": hr,
                "spo2": spo2,
                "gpsLat": lat,
                "gpsLon": lon,
                "hrvStress": 0,
                "geofenceStatus": geofence,
                "homeLat": 34.1084,
                "homeLon": 109.0030
            }
        }]
    })


def main():
    client = mqtt.Client(client_id="petcare_simulator")
    client.connect(BROKER, PORT, 60)
    client.loop_start()

    print("=" * 55)
    print("  智宠管家 · 情绪识别线上仿真")
    print("  请确保 App 已打开并连接同一 MQTT Broker")
    print("=" * 55)

    for duration, anxiety, emotion, comfort, desc in SCENARIO:
        print(f"\n>>> {desc}")
        print(f"    焦虑等级: {anxiety}  情绪: {emotion}  安抚: {comfort}")
        print(f"    持续 {duration} 秒...")

        steps = duration
        for step in range(steps):
            a = anxiety + random.randint(-3, 3)
            a = max(0, min(100, a))
            hr = 80 + int(a * 1.2) + random.randint(-3, 3)
            activity = int(a * 0.6) + random.randint(0, 5)
            spo2 = 98 - int(a * 0.05) + random.randint(-1, 1)

            payload = build_payload(
                anxiety=a, emotion=emotion, comfort=comfort,
                hr=hr, spo2=max(90, min(99, spo2)),
                activity=activity
            )
            client.publish(TOPIC, payload, qos=0)
            print(f"    [{step+1}/{steps}] anxiety={a} HR={hr} SPO2={spo2}% act={activity}", end="\r")
            time.sleep(1)
        print()

    print("\n" + "=" * 55)
    print("  仿真结束。App Dashboard 应显示了完整情绪变化过程。")
    print("  如需重播，重新运行此脚本即可。")
    print("=" * 55)

    client.loop_stop()
    client.disconnect()


if __name__ == "__main__":
    main()
