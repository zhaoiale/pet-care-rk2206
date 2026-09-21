// SeedData.ets — 首次启动时创建演示用户/宠物/投喂计划 + 注入模拟GPS路径
// ★ DEMO MODE: 注入模拟传感器/投喂记录用于截图，拍完视频后删掉 generateDemo* 调用即可
import {
  insertFeedingPlan,
  getFeedingPlansByPet,
  insertUser, getUserByUsername, insertPet, queryAllPets, queryPetsByOwner,
  insertSensorRecord, insertFeedingRecord, getLatestRecord,
} from './DatabaseService';
import relationalStore from '@ohos.data.relationalStore';
import { GpsPathPoint, SensorRecord } from '../model/SensorRecord';
import { FeedingPlan, FeedingRecord } from '../model/FeedingPlan';
import { User } from '../model/User';
import { Pet } from '../model/Pet';
import { appendGpsPathPoints } from '../services/MqttService';
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

const SEED_FLAG_KEY = 'seedDataV7_7day_noToday';  // ★ v7: 清除今日零值记录后重新播种，修复传感器未就绪时demo数据被覆盖

function generateFeedingPlans(petId: number): FeedingPlan[] {
  const now = Date.now();
  return [
    { id: 0, petId, feedTime: '08:00', amount: 350, enabled: true, createTime: now },
    { id: 0, petId, feedTime: '14:00', amount: 350, enabled: true, createTime: now },
    { id: 0, petId, feedTime: '20:00', amount: 350, enabled: true, createTime: now }
  ];
}

// ★★★ DEMO DATA — 截完屏后删除下面两个函数及其调用 ★★★

function generateDemoSensorRecords(): SensorRecord[] {
  const now = Date.now();
  const records: SensorRecord[] = [];
  const DAY_MS = 86400000;

  // 每天 6:00-22:00，每 1-2 小时一条，约 14 条/天 × 7 天 ≈ 98 条
  const dailyHours = [6, 7, 8, 9, 10, 12, 14, 16, 17, 18, 19, 20, 21, 22];

  // 每天的情绪曲线模板: [anxiety, emotion, hr, spo2, activity]
  type HourProfile = [number, string, number, number, number];
  const dayProfile: HourProfile[] = [
    [12, 'CALM',   82, 98,  6],   // 6:00 刚醒
    [15, 'CALM',   85, 98,  8],   // 7:00
    [ 8, 'HAPPY',  88, 98, 12],   // 8:00 早餐后开心
    [10, 'HAPPY',  90, 97, 15],   // 9:00
    [18, 'HAPPY',  92, 97, 18],   // 10:00
    [25, 'CALM',   95, 97, 20],   // 12:00 午间
    [30, 'CALM',   98, 96, 22],   // 14:00
    [38, 'ALERT', 102, 96, 28],   // 16:00 警觉期
    [45, 'ALERT', 108, 95, 32],   // 17:00 主人快回来了
    [35, 'ALERT', 105, 96, 25],   // 18:00
    [55, 'ANXIOUS',118, 95, 42],  // 19:00 分离焦虑
    [60, 'ANXIOUS',122, 94, 48],  // 20:00
    [48, 'ALERT', 112, 95, 30],   // 21:00 逐渐平静
    [22, 'CALM',   95, 97, 15],   // 22:00 准备休息
  ];

  // 每周变化: 周末更活跃
  const weekendBoost = [false, false, false, false, false, true, true]; // 0=Sun ... 6=Sat

  /* 从7天前到昨天, 不包含今天, 确保首页 getLatestRecord 不会被demo数据覆盖 */
  for (let dayOffset = 7; dayOffset >= 1; dayOffset--) {
    const dayStart = now - dayOffset * DAY_MS;
    // 设置到当天 0:00
    const dayBase = new Date(dayStart);
    dayBase.setHours(0, 0, 0, 0);
    const dayBaseMs = dayBase.getTime();

    const isWeekend = weekendBoost[(new Date(dayBaseMs).getDay())];

    for (let h = 0; h < dailyHours.length; h++) {
      const hour = dailyHours[h];
      const profile = dayProfile[h];
      let anxiety = profile[0];
      const emotion = profile[1];
      let hr = profile[2];
      const spo2 = profile[3];
      let activity = profile[4];

      // 周末微调: 更开心一点
      if (isWeekend && emotion === 'HAPPY') {
        anxiety = Math.max(3, anxiety - 3);
        hr += 3;
        activity += 5;
      }

      // 添加随机波动 ±5
      anxiety = Math.max(3, Math.min(80, anxiety + Math.floor((Math.random() - 0.5) * 10)));
      hr = Math.max(70, Math.min(130, hr + Math.floor((Math.random() - 0.5) * 8)));
      // 确保数值型字段不会变成 NaN
      const adjAnxiety = anxiety || 25;
      const adjHr = hr || 90;
      const adjSpo2 = spo2 || 97;
      const adjActivity = activity || 20;

      records.push({
        id: 0,
        temperature: 24.5 + Math.random() * 2.5,
        humidity: 50 + Math.random() * 15,
        illumination: hour < 8 ? 200 : hour > 19 ? 150 : 600 + Math.random() * 800,
        anxietyLevel: adjAnxiety,
        comfortType: emotion === 'ANXIOUS' ? (Math.random() > 0.5 ? 2 : 1) :
                     emotion === 'ALERT' ? (Math.random() > 0.7 ? 1 : 0) : 0,
        audioSubType: emotion === 'ANXIOUS' && Math.random() > 0.5 ? 2 : 0,
        foodWeight: 350 - dayOffset * 15 + Math.random() * 10,
        foodEaten: 20 + dayOffset * 15 + Math.random() * 8,
        timestamp: dayBaseMs + hour * 3600000 + Math.floor(Math.random() * 1800000),
        heartRate: adjHr,
        spo2: adjSpo2,
        gpsLat: 34.1084 + (Math.random() - 0.5) * 0.0005,
        gpsLon: 109.0030 + (Math.random() - 0.5) * 0.0005,
        geofenceStatus: 0,
        activityLevel: adjActivity,
        emotion: emotion,
        hrvStress: emotion === 'ANXIOUS' ? 60 : emotion === 'ALERT' ? 40 : 18,
        healthScore: emotion === 'ANXIOUS' ? 65 : emotion === 'ALERT' ? 82 : 93,
        bodyTemp: 37.5 + Math.random() * 1.5,
      });
    }
  }
  return records;
}

function generateDemoFeedingRecords(petId: number): FeedingRecord[] {
  const now = Date.now();
  const DAY_MS = 86400000;
  const records: FeedingRecord[] = [];
  // 每天 3 顿 × 7 天
  const mealHours = [8, 14, 20];
  for (let d = 7; d >= 1; d--) {
    for (const h of mealHours) {
      const ts = now - d * DAY_MS + (h - new Date().getHours()) * 3600000
                 - new Date().getMinutes() * 60000 + Math.floor(Math.random() * 1800000);
      records.push({
        id: 0, petId,
        amount: 300 + Math.floor(Math.random() * 80),
        isManual: (d === 0 && h >= 20) || Math.random() > 0.7,
        timestamp: ts
      });
    }
  }
  return records;
}

// ★★★ END DEMO DATA ★★★

export function generateGpsPath(homeLat: number, homeLon: number): void {
  // 模拟遛宠矩形轨迹，加点随机噪声使路径看起来自然
  // 边长约 0.001° ≈ 100m
  const SIDE: number = 0.001;
  const N: number = 10;          // 每边点数
  const NOISE: number = 0.00004; // 随机偏移幅度 ≈ 4m

  const rnd = () => (Math.random() - 0.5) * 2 * NOISE;

  const route: [number, number][] = [];

  // 起点：家
  route.push([rnd(), rnd()]);

  // 底边：向东
  for (let i = 1; i <= N; i++) {
    route.push([rnd(), (SIDE * i) / N + rnd()]);
  }

  // 右边：向北
  for (let i = 1; i <= N; i++) {
    route.push([(SIDE * i) / N + rnd(), SIDE + rnd()]);
  }

  // 顶边：向西
  for (let i = 1; i <= N; i++) {
    route.push([SIDE + rnd(), SIDE - (SIDE * i) / N + rnd()]);
  }

  // 左边：向南回家
  for (let i = 1; i <= N; i++) {
    route.push([SIDE - (SIDE * i) / N + rnd(), rnd()]);
  }

  // 终点：回到家附近
  route.push([rnd(), rnd()]);

  const newPoints: GpsPathPoint[] = [];
  for (let i = 0; i < route.length; i++) {
    const pt: GpsPathPoint = {
      lat: Number((homeLat + route[i][0]).toFixed(7)),
      lon: Number((homeLon + route[i][1]).toFixed(7))
    };
    newPoints.push(pt);
  }

  appendGpsPathPoints(newPoints);
  console.info('[SeedData] GPS path injected: ' + newPoints.length.toString() + ' points (rectangle + noise)');
}

export async function seedDemoData(context?: object): Promise<void> {
  try {
    // 清理今天的零值传感器记录（传感器未就绪时产生的垃圾数据）
    try {
      const store = await relationalStore.getRdbStore(context as common.Context, {
        name: 'petcare.db',
        securityLevel: relationalStore.SecurityLevel.S1
      });
      const todayStart = new Date();
      todayStart.setHours(0, 0, 0, 0);
      await store.executeSql(
        'DELETE FROM sensor_records WHERE timestamp >= ? AND heart_rate = 0 AND spo2 = 0 AND anxiety_level = 0',
        [todayStart.getTime().toString()]
      );
      console.info('[SeedData] Cleaned zero-value records from today');
    } catch (cleanErr) {
      console.warn('[SeedData] Cleanup skipped: ' + JSON.stringify(cleanErr));
    }

    // Use persistent Preferences instead of volatile AppStorage
    let prefs: preferences.Preferences | null = null;
    if (context) {
      prefs = await preferences.getPreferences(context as common.Context, 'petcare_seed');
      const seeded = await prefs.get(SEED_FLAG_KEY, false) as boolean;
      if (seeded) {
        console.info('[SeedData] Already seeded (persistent), skip');
        return;
      }
    } else {
      // fallback: check AppStorage for backward compatibility
      const alreadySeeded = AppStorage.Get<boolean>(SEED_FLAG_KEY);
      if (alreadySeeded) {
        console.info('[SeedData] Already seeded (memory), skip');
        return;
      }
    }

    // 1. Ensure demo user
    let userId = 0;
    const existingUser = await getUserByUsername('demo');
    if (existingUser !== null) {
      userId = existingUser.id;
      console.info('[SeedData] Demo user exists, id=' + userId.toString());
    } else {
      const user: User = {
        id: 0,
        username: 'demo',
        password: '123456',
        name: '宠物主人',
        phone: '13800138000',
        createTime: Date.now()
      };
      userId = await insertUser(user);
      console.info('[SeedData] Created demo user, id=' + userId.toString());
    }

    if (userId <= 0) {
      console.error('[SeedData] Failed to create/get demo user');
      return;
    }

    // 2. Ensure demo pet
    let petId = 0;
    const pets = await queryPetsByOwner(userId);
    if (pets.length > 0) {
      petId = pets[0].id;
      console.info('[SeedData] Found pet, id=' + petId.toString());
    } else {
      const allPets = await queryAllPets();
      if (allPets.length > 0) {
        petId = allPets[0].id;
        console.info('[SeedData] Using existing pet, id=' + petId.toString());
      } else {
        const pet: Pet = {
          id: 0,
          name: '胖宝宝',
          breed: '藏獒',
          age: '2岁',
          weight: '37kg',
          gender: '女孩',
          adoptionStatus: 'owned',
          avatar: '',
          createTime: Date.now(),
          ownerId: userId
        };
        petId = await insertPet(pet);
        console.info('[SeedData] Created demo pet, id=' + petId.toString());
      }
    }

    if (petId <= 0) {
      console.error('[SeedData] Failed to create/get demo pet');
      return;
    }

    // 3. Insert feeding plans if none (functional data, not synthetic history)
    const existingPlans = await getFeedingPlansByPet(petId);
    if (existingPlans.length === 0) {
      const plans = generateFeedingPlans(petId);
      for (const p of plans) {
        await insertFeedingPlan(p);
      }
      console.info('[SeedData] Inserted ' + plans.length.toString() + ' feeding plans');
    }

    // ★ DEMO: 注入模拟传感器记录（截完屏后删除此段）
    const demoRecords = generateDemoSensorRecords();
    for (const r of demoRecords) {
      await insertSensorRecord(r);
    }
    console.info('[SeedData] ★ Inserted ' + demoRecords.length.toString() + ' DEMO sensor records');

    // ★ DEMO: 注入模拟投喂记录（截完屏后删除此段）
    const demoFeeding = generateDemoFeedingRecords(petId);
    for (const f of demoFeeding) {
      await insertFeedingRecord(f);
    }
    console.info('[SeedData] ★ Inserted ' + demoFeeding.length.toString() + ' DEMO feeding records');

    // GPS path is injected unconditionally in EntryAbility (in-memory only)
    AppStorage.SetOrCreate(SEED_FLAG_KEY, true);
    if (prefs) {
      await prefs.put(SEED_FLAG_KEY, true);
      await prefs.flush();
    }
    console.info('[SeedData] ★ DEMO seed complete (user/pet/plans/GPS/sensor/feeding)');
  } catch (err) {
    console.error('[SeedData] Error: ' + JSON.stringify(err));
  }
}
