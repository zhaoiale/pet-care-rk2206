// SensorRecord.ets — 传感器历史记录数据模型
export interface SensorRecord {
  id: number;
  temperature: number;
  humidity: number;
  illumination: number;
  anxietyLevel: number;
  comfortType: number;
  audioSubType: number;
  foodWeight: number;
  foodEaten: number;
  timestamp: number;
  heartRate: number;
  spo2: number;
  gpsLat: number;
  gpsLon: number;
  geofenceStatus: number;
  activityLevel: number;
  emotion: string;
  hrvStress: number;
  healthScore: number;
  bodyTemp: number;
}

// GPS 路径点（来自硬件 pathData 消息）
export interface GpsPathPoint {
  lat: number;
  lon: number;
}

export function sensorRecordToString(r: SensorRecord): string {
  return `[${new Date(r.timestamp).toLocaleString()}] T:${r.temperature.toFixed(1)}℃ H:${r.humidity.toFixed(1)}% L:${r.illumination.toFixed(1)}Lux 焦虑:${r.anxietyLevel} 心率:${r.heartRate} SpO2:${r.spo2} 健康评分:${r.healthScore}`;
}
