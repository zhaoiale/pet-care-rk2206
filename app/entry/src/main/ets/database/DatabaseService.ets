// DatabaseService.ets — 数据库服务（传感器记录 + 宠物档案 + 用户管理 + 投喂计划）
import relationalStore from '@ohos.data.relationalStore';
import common from '@ohos.app.ability.common';
import { SensorRecord } from '../model/SensorRecord';
import { Pet } from '../model/Pet';
import { User } from '../model/User';
import { FeedingPlan, FeedingRecord } from '../model/FeedingPlan';

const DB_NAME: string = 'petcare.db';
const TABLE_SENSOR: string = 'sensor_records';
const TABLE_PETS: string = 'pets';
const TABLE_USERS: string = 'users';
const TABLE_FEEDING_PLANS: string = 'feeding_plans';
const TABLE_FEEDING_RECORDS: string = 'feeding_records';
const TABLE_INTERACTIONS: string = 'interaction_records';
const MAX_RECORDS: number = 500;

const STORE_CONFIG: relationalStore.StoreConfig = {
  name: DB_NAME,
  securityLevel: relationalStore.SecurityLevel.S1
};

const SQL_CREATE_SENSOR: string =
  'CREATE TABLE IF NOT EXISTS ' + TABLE_SENSOR + ' (' +
  'id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
  'temperature REAL NOT NULL, ' +
  'humidity REAL NOT NULL, ' +
  'illumination REAL NOT NULL, ' +
  'anxiety_level INTEGER NOT NULL, ' +
  'comfort_type INTEGER NOT NULL, ' +
  'audio_sub_type INTEGER NOT NULL DEFAULT 0, ' +
  'food_weight REAL NOT NULL DEFAULT 0, ' +
  'food_eaten REAL NOT NULL DEFAULT 0, ' +
  'heart_rate REAL NOT NULL DEFAULT 0, ' +
  'spo2 REAL NOT NULL DEFAULT 0, ' +
  'gps_lat REAL NOT NULL DEFAULT 0, ' +
  'gps_lon REAL NOT NULL DEFAULT 0, ' +
  'geofence_status INTEGER NOT NULL DEFAULT 0, ' +
  'activity_level INTEGER NOT NULL DEFAULT 0, ' +
  'emotion TEXT NOT NULL DEFAULT \'CALM\', ' +
  'hrv_stress REAL NOT NULL DEFAULT 0, ' +
  'health_score INTEGER NOT NULL DEFAULT 0, ' +
  'body_temp REAL NOT NULL DEFAULT 0, ' +
  'timestamp INTEGER NOT NULL)';

const SQL_CREATE_PETS: string =
  'CREATE TABLE IF NOT EXISTS ' + TABLE_PETS + ' (' +
  'id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
  'name TEXT NOT NULL, ' +
  'breed TEXT NOT NULL, ' +
  'age TEXT NOT NULL, ' +
  'weight TEXT NOT NULL, ' +
  'gender TEXT NOT NULL, ' +
  'adoption_status TEXT NOT NULL DEFAULT \'available\', ' +
  'avatar TEXT NOT NULL DEFAULT \'\', ' +
  'create_time INTEGER NOT NULL, ' +
  'owner_id INTEGER NOT NULL DEFAULT 0)';

const SQL_CREATE_USERS: string =
  'CREATE TABLE IF NOT EXISTS ' + TABLE_USERS + ' (' +
  'id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
  'username TEXT NOT NULL UNIQUE, ' +
  'password TEXT NOT NULL, ' +
  'name TEXT NOT NULL, ' +
  'phone TEXT NOT NULL, ' +
  'create_time INTEGER NOT NULL)';

const SQL_CREATE_FEEDING_PLANS: string =
  'CREATE TABLE IF NOT EXISTS ' + TABLE_FEEDING_PLANS + ' (' +
  'id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
  'pet_id INTEGER NOT NULL, ' +
  'feed_time TEXT NOT NULL, ' +
  'amount INTEGER NOT NULL, ' +
  'enabled INTEGER NOT NULL DEFAULT 1, ' +
  'create_time INTEGER NOT NULL)';

const SQL_CREATE_FEEDING_RECORDS: string =
  'CREATE TABLE IF NOT EXISTS ' + TABLE_FEEDING_RECORDS + ' (' +
  'id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
  'pet_id INTEGER NOT NULL, ' +
  'amount INTEGER NOT NULL, ' +
  'is_manual INTEGER NOT NULL DEFAULT 1, ' +
  'timestamp INTEGER NOT NULL)';

const SQL_CREATE_INTERACTIONS: string =
  'CREATE TABLE IF NOT EXISTS ' + TABLE_INTERACTIONS + ' (' +
  'id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
  'pet_id INTEGER NOT NULL, ' +
  'interaction_type TEXT NOT NULL, ' +
  'content TEXT NOT NULL, ' +
  'timestamp INTEGER NOT NULL)';

export interface InteractionRecord {
  id: number;
  petId: number;
  interactionType: string;
  content: string;
  timestamp: number;
}

let rdbStore: relationalStore.RdbStore | null = null;

async function ensurePetsTableHasOwnerId(): Promise<void> {
  if (rdbStore === null) return;
  try {
    const predicates = new relationalStore.RdbPredicates(TABLE_PETS);
    predicates.limitAs(1);
    const testResult = await rdbStore.query(predicates);
    testResult.close();

    const allPredicates = new relationalStore.RdbPredicates(TABLE_PETS);
    const resultSet = await rdbStore.query(allPredicates);
    const columnNames: string[] = [];
    const columnCount = resultSet.columnCount;
    for (let i = 0; i < columnCount; i++) {
      columnNames.push(resultSet.getColumnName(i));
    }
    resultSet.close();

    if (!columnNames.includes('owner_id')) {
      try {
        await rdbStore.executeSql('ALTER TABLE ' + TABLE_PETS + ' ADD COLUMN owner_id INTEGER NOT NULL DEFAULT 0');
        console.info('[DB] Added owner_id column to pets table');
      } catch (alterErr) {
        console.warn('[DB] ALTER TABLE owner_id may have failed: ' + JSON.stringify(alterErr));
      }
    }
  } catch (err) {
    console.error('[DB] ensurePetsTableHasOwnerId error: ' + JSON.stringify(err));
  }
}

async function ensureSensorTableColumns(): Promise<void> {
  if (rdbStore === null) return;
  const migrations: [string, string][] = [
    ['food_weight', 'REAL NOT NULL DEFAULT 0'],
    ['food_eaten', 'REAL NOT NULL DEFAULT 0'],
    ['heart_rate', 'REAL NOT NULL DEFAULT 0'],
    ['spo2', 'REAL NOT NULL DEFAULT 0'],
    ['gps_lat', 'REAL NOT NULL DEFAULT 0'],
    ['gps_lon', 'REAL NOT NULL DEFAULT 0'],
    ['geofence_status', 'INTEGER NOT NULL DEFAULT 0'],
    ['activity_level', 'INTEGER NOT NULL DEFAULT 0'],
    ['emotion', 'TEXT NOT NULL DEFAULT \'CALM\''],
    ['hrv_stress', 'REAL NOT NULL DEFAULT 0'],
    ['audio_sub_type', 'INTEGER NOT NULL DEFAULT 0'],
    ['health_score', 'INTEGER NOT NULL DEFAULT 0'],
    ['body_temp', 'REAL NOT NULL DEFAULT 0'],
  ];

  try {
    const predicates = new relationalStore.RdbPredicates(TABLE_SENSOR);
    predicates.limitAs(1);
    const resultSet = await rdbStore.query(predicates);
    const columnCount = resultSet.columnCount;
    const cols: string[] = [];
    for (let i = 0; i < columnCount; i++) {
      cols.push(resultSet.getColumnName(i));
    }
    resultSet.close();

    for (let mi = 0; mi < migrations.length; mi++) {
      const col: string = migrations[mi][0];
      const def: string = migrations[mi][1];
      if (!cols.includes(col)) {
        try {
          await rdbStore.executeSql('ALTER TABLE ' + TABLE_SENSOR + ' ADD COLUMN ' + col + ' ' + def);
          console.info('[DB] Added ' + col + ' column to sensor table');
        } catch (alterErr) {
          console.warn('[DB] ALTER TABLE ' + col + ' failed: ' + JSON.stringify(alterErr));
        }
      }
    }
  } catch (err) {
    console.error('[DB] ensureSensorTableColumns error: ' + JSON.stringify(err));
  }
}

export async function initDatabase(context: common.Context): Promise<void> {
  try {
    rdbStore = await relationalStore.getRdbStore(context, STORE_CONFIG);
    await rdbStore.executeSql(SQL_CREATE_SENSOR);
    await rdbStore.executeSql(SQL_CREATE_PETS);
    await rdbStore.executeSql(SQL_CREATE_USERS);
    await rdbStore.executeSql(SQL_CREATE_FEEDING_PLANS);
    await rdbStore.executeSql(SQL_CREATE_FEEDING_RECORDS);
    await rdbStore.executeSql(SQL_CREATE_INTERACTIONS);

    await ensurePetsTableHasOwnerId();
    await ensureSensorTableColumns();

    console.info('[DB] Database initialized successfully');
  } catch (err) {
    console.error('[DB] initDatabase error: ' + JSON.stringify(err));
  }
}

export async function deleteFutureSensorRecords(): Promise<void> {
  if (rdbStore === null) return;
  try {
    const now: number = Date.now();
    const sql: string = 'DELETE FROM ' + TABLE_SENSOR + ' WHERE timestamp > ?';
    await rdbStore.executeSql(sql, [now.toString()]);
    console.info('[DB] Deleted future-dated sensor records');
  } catch (err) {
    console.error('[DB] deleteFutureSensorRecords error: ' + JSON.stringify(err));
  }
}

export async function insertSensorRecord(record: SensorRecord): Promise<number> {
  if (rdbStore === null) {
    console.error('[DB] Database not initialized');
    return -1;
  }
  try {
    const valueBucket: relationalStore.ValuesBucket = {
      temperature: record.temperature,
      humidity: record.humidity,
      illumination: record.illumination,
      anxiety_level: record.anxietyLevel,
      comfort_type: record.comfortType,
      audio_sub_type: record.audioSubType,
      food_weight: record.foodWeight,
      food_eaten: record.foodEaten,
      heart_rate: record.heartRate,
      spo2: record.spo2,
      gps_lat: record.gpsLat,
      gps_lon: record.gpsLon,
      geofence_status: record.geofenceStatus,
      activity_level: record.activityLevel,
      emotion: record.emotion,
      hrv_stress: record.hrvStress,
      health_score: record.healthScore,
      body_temp: record.bodyTemp,
      timestamp: record.timestamp
    };
    const rowId: number = await rdbStore.insert(TABLE_SENSOR, valueBucket);
    console.info('[DB] Inserted record id=' + rowId.toString() + ' HR=' + record.heartRate.toString() + ' SpO2=' + record.spo2.toString());
    await cleanupOldRecords();
    return rowId;
  } catch (err) {
    console.error('[DB] insertSensorRecord error: ' + JSON.stringify(err));
    return -1;
  }
}

function rowToRecord(resultSet: relationalStore.ResultSet): SensorRecord {
  return {
    id: resultSet.getLong(resultSet.getColumnIndex('id')),
    temperature: resultSet.getDouble(resultSet.getColumnIndex('temperature')),
    humidity: resultSet.getDouble(resultSet.getColumnIndex('humidity')),
    illumination: resultSet.getDouble(resultSet.getColumnIndex('illumination')),
    anxietyLevel: resultSet.getLong(resultSet.getColumnIndex('anxiety_level')),
    comfortType: resultSet.getLong(resultSet.getColumnIndex('comfort_type')),
    audioSubType: resultSet.getLong(resultSet.getColumnIndex('audio_sub_type')),
    foodWeight: resultSet.getDouble(resultSet.getColumnIndex('food_weight')),
    foodEaten: resultSet.getDouble(resultSet.getColumnIndex('food_eaten')),
    heartRate: resultSet.getDouble(resultSet.getColumnIndex('heart_rate')),
    spo2: resultSet.getDouble(resultSet.getColumnIndex('spo2')),
    gpsLat: resultSet.getDouble(resultSet.getColumnIndex('gps_lat')),
    gpsLon: resultSet.getDouble(resultSet.getColumnIndex('gps_lon')),
    geofenceStatus: resultSet.getLong(resultSet.getColumnIndex('geofence_status')),
    activityLevel: resultSet.getLong(resultSet.getColumnIndex('activity_level')),
    emotion: resultSet.getString(resultSet.getColumnIndex('emotion')),
    hrvStress: resultSet.getDouble(resultSet.getColumnIndex('hrv_stress')),
    healthScore: resultSet.getLong(resultSet.getColumnIndex('health_score')),
    bodyTemp: resultSet.getDouble(resultSet.getColumnIndex('body_temp')),
    timestamp: resultSet.getLong(resultSet.getColumnIndex('timestamp'))
  };
}

export async function queryRecords(days: number): Promise<SensorRecord[]> {
  if (rdbStore === null) {
    console.error('[DB] Database not initialized');
    return [];
  }
  try {
    const cutoffTime: number = Date.now() - days * 24 * 60 * 60 * 1000;
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE_SENSOR);
    predicates.greaterThan('timestamp', cutoffTime);
    predicates.orderByDesc('timestamp');
    if (days > 0) {
      predicates.limitAs(300);
    }

    const resultSet = await rdbStore.query(predicates);
    const records: SensorRecord[] = [];

    while (resultSet.goToNextRow()) {
      records.push(rowToRecord(resultSet));
    }
    resultSet.close();
    console.info('[DB] Queried ' + records.length.toString() + ' records');
    return records;
  } catch (err) {
    console.error('[DB] queryRecords error: ' + JSON.stringify(err));
    return [];
  }
}

export async function getLatestRecord(): Promise<SensorRecord | null> {
  if (rdbStore === null) {
    return null;
  }
  try {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE_SENSOR);
    predicates.orderByDesc('timestamp');
    predicates.limitAs(1);

    const resultSet = await rdbStore.query(predicates);
    if (resultSet.goToFirstRow()) {
      const record = rowToRecord(resultSet);
      resultSet.close();
      return record;
    }
    resultSet.close();
    return null;
  } catch (err) {
    console.error('[DB] getLatestRecord error: ' + JSON.stringify(err));
    return null;
  }
}

async function cleanupOldRecords(): Promise<void> {
  if (rdbStore === null) {
    return;
  }
  try {
    const sql: string =
      'DELETE FROM ' + TABLE_SENSOR +
      ' WHERE id NOT IN (SELECT id FROM ' + TABLE_SENSOR +
      ' ORDER BY timestamp DESC LIMIT ' + MAX_RECORDS.toString() + ')';
    await rdbStore.executeSql(sql);
  } catch (err) {
    // 静默处理
  }
}

export async function getRecordCount(): Promise<number> {
  if (rdbStore === null) {
    return 0;
  }
  try {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE_SENSOR);
    const resultSet = await rdbStore.query(predicates);
    const count: number = resultSet.rowCount;
    resultSet.close();
    return count;
  } catch (err) {
    return 0;
  }
}

// ==================== 宠物档案 CRUD ====================

function rowToPet(resultSet: relationalStore.ResultSet): Pet | null {
  try {
    return {
      id: resultSet.getLong(resultSet.getColumnIndex('id')) ?? 0,
      name: resultSet.getString(resultSet.getColumnIndex('name')) ?? '',
      breed: resultSet.getString(resultSet.getColumnIndex('breed')) ?? '',
      age: resultSet.getString(resultSet.getColumnIndex('age')) ?? '',
      weight: resultSet.getString(resultSet.getColumnIndex('weight')) ?? '',
      gender: resultSet.getString(resultSet.getColumnIndex('gender')) ?? '',
      adoptionStatus: resultSet.getString(resultSet.getColumnIndex('adoption_status')) ?? 'available',
      avatar: resultSet.getString(resultSet.getColumnIndex('avatar')) ?? '',
      createTime: resultSet.getLong(resultSet.getColumnIndex('create_time')) ?? 0,
      ownerId: resultSet.getLong(resultSet.getColumnIndex('owner_id')) ?? 0
    };
  } catch (err) {
    console.error('[DB] rowToPet error: ' + JSON.stringify(err));
    return null;
  }
}

export async function insertPet(pet: Pet): Promise<number> {
  if (rdbStore === null) return -1;
  try {
    const vb: relationalStore.ValuesBucket = {
      name: pet.name,
      breed: pet.breed,
      age: pet.age,
      weight: pet.weight,
      gender: pet.gender,
      adoption_status: pet.adoptionStatus,
      avatar: pet.avatar,
      create_time: pet.createTime,
      owner_id: pet.ownerId
    };
    const rowId = await rdbStore.insert(TABLE_PETS, vb);
    console.info('[DB] insertPet rowId=' + rowId.toString());
    return rowId;
  } catch (err) {
    console.error('[DB] insertPet error: ' + JSON.stringify(err));
    return -1;
  }
}

export async function updatePet(pet: Pet): Promise<number> {
  if (rdbStore === null) return -1;
  try {
    const vb: relationalStore.ValuesBucket = {
      name: pet.name,
      breed: pet.breed,
      age: pet.age,
      weight: pet.weight,
      gender: pet.gender,
      adoption_status: pet.adoptionStatus,
      avatar: pet.avatar,
      owner_id: pet.ownerId
    };
    const predicates = new relationalStore.RdbPredicates(TABLE_PETS);
    predicates.equalTo('id', pet.id);
    const rows = await rdbStore.update(vb, predicates);
    console.info('[DB] updatePet rows=' + rows.toString());
    return rows;
  } catch (err) {
    console.error('[DB] updatePet error: ' + JSON.stringify(err));
    return -1;
  }
}

export async function queryPetsByOwner(ownerId: number): Promise<Pet[]> {
  if (rdbStore === null) return [];
  try {
    const predicates = new relationalStore.RdbPredicates(TABLE_PETS);
    predicates.equalTo('owner_id', ownerId);
    predicates.orderByDesc('create_time');
    const resultSet = await rdbStore.query(predicates);
    const pets: Pet[] = [];
    while (resultSet.goToNextRow()) {
      const pet = rowToPet(resultSet);
      if (pet !== null) {
        pets.push(pet);
      }
    }
    resultSet.close();
    return pets;
  } catch (err) {
    console.error('[DB] queryPetsByOwner error: ' + JSON.stringify(err));
    return [];
  }
}

// ==================== 用户 CRUD ====================

function rowToUser(resultSet: relationalStore.ResultSet): User | null {
  try {
    return {
      id: resultSet.getLong(resultSet.getColumnIndex('id')) ?? 0,
      username: resultSet.getString(resultSet.getColumnIndex('username')) ?? '',
      password: resultSet.getString(resultSet.getColumnIndex('password')) ?? '',
      name: resultSet.getString(resultSet.getColumnIndex('name')) ?? '',
      phone: resultSet.getString(resultSet.getColumnIndex('phone')) ?? '',
      createTime: resultSet.getLong(resultSet.getColumnIndex('create_time')) ?? 0
    };
  } catch (err) {
    console.error('[DB] rowToUser error: ' + JSON.stringify(err));
    return null;
  }
}

export async function insertUser(user: User): Promise<number> {
  if (rdbStore === null) return -1;
  try {
    const vb: relationalStore.ValuesBucket = {
      username: user.username,
      password: user.password,
      name: user.name,
      phone: user.phone,
      create_time: user.createTime
    };
    const rowId = await rdbStore.insert(TABLE_USERS, vb);
    console.info('[DB] insertUser rowId=' + rowId.toString());
    return rowId;
  } catch (err) {
    console.error('[DB] insertUser error: ' + JSON.stringify(err));
    return -1;
  }
}

export async function getUserByUsername(username: string): Promise<User | null> {
  if (rdbStore === null) return null;
  try {
    const predicates = new relationalStore.RdbPredicates(TABLE_USERS);
    predicates.equalTo('username', username);
    const resultSet = await rdbStore.query(predicates);
    if (resultSet.goToFirstRow()) {
      const user = rowToUser(resultSet);
      resultSet.close();
      return user;
    }
    resultSet.close();
    return null;
  } catch (err) {
    console.error('[DB] getUserByUsername error: ' + JSON.stringify(err));
    return null;
  }
}

export async function getUserById(userId: number): Promise<User | null> {
  if (rdbStore === null) return null;
  try {
    const predicates = new relationalStore.RdbPredicates(TABLE_USERS);
    predicates.equalTo('id', userId);
    const resultSet = await rdbStore.query(predicates);
    if (resultSet.goToFirstRow()) {
      const user = rowToUser(resultSet);
      resultSet.close();
      return user;
    }
    resultSet.close();
    return null;
  } catch (err) {
    console.error('[DB] getUserById error: ' + JSON.stringify(err));
    return null;
  }
}

export async function updateUser(user: User): Promise<number> {
  if (rdbStore === null) return -1;
  try {
    const vb: relationalStore.ValuesBucket = {
      name: user.name,
      phone: user.phone,
      password: user.password
    };
    const predicates = new relationalStore.RdbPredicates(TABLE_USERS);
    predicates.equalTo('id', user.id);
    const rows = await rdbStore.update(vb, predicates);
    console.info('[DB] updateUser rows=' + rows.toString());
    return rows;
  } catch (err) {
    console.error('[DB] updateUser error: ' + JSON.stringify(err));
    return -1;
  }
}

export async function deletePet(petId: number): Promise<number> {
  if (rdbStore === null) return -1;
  try {
    const predicates = new relationalStore.RdbPredicates(TABLE_PETS);
    predicates.equalTo('id', petId);
    const rows = await rdbStore.delete(predicates);
    console.info('[DB] deletePet rows=' + rows.toString());
    return rows;
  } catch (err) {
    console.error('[DB] deletePet error: ' + JSON.stringify(err));
    return -1;
  }
}

export async function queryAllPets(): Promise<Pet[]> {
  if (rdbStore === null) return [];
  try {
    const predicates = new relationalStore.RdbPredicates(TABLE_PETS);
    predicates.orderByDesc('create_time');
    const resultSet = await rdbStore.query(predicates);
    const pets: Pet[] = [];
    while (resultSet.goToNextRow()) {
      const pet = rowToPet(resultSet);
      if (pet !== null) {
        pets.push(pet);
      }
    }
    resultSet.close();
    return pets;
  } catch (err) {
    console.error('[DB] queryAllPets error: ' + JSON.stringify(err));
    return [];
  }
}

export async function queryPetsByStatus(status: string): Promise<Pet[]> {
  if (rdbStore === null) return [];
  try {
    const predicates = new relationalStore.RdbPredicates(TABLE_PETS);
    predicates.equalTo('adoption_status', status);
    predicates.orderByDesc('create_time');
    const resultSet = await rdbStore.query(predicates);
    const pets: Pet[] = [];
    while (resultSet.goToNextRow()) {
      const pet = rowToPet(resultSet);
      if (pet !== null) {
        pets.push(pet);
      }
    }
    resultSet.close();
    return pets;
  } catch (err) {
    console.error('[DB] queryPetsByStatus error: ' + JSON.stringify(err));
    return [];
  }
}

export async function getPetById(petId: number): Promise<Pet | null> {
  if (rdbStore === null) return null;
  try {
    const predicates = new relationalStore.RdbPredicates(TABLE_PETS);
    predicates.equalTo('id', petId);
    const resultSet = await rdbStore.query(predicates);
    if (resultSet.goToFirstRow()) {
      const pet = rowToPet(resultSet);
      resultSet.close();
      return pet;
    }
    resultSet.close();
    return null;
  } catch (err) {
    console.error('[DB] getPetById error: ' + JSON.stringify(err));
    return null;
  }
}

export async function queryAllUsers(): Promise<User[]> {
  if (rdbStore === null) return [];
  try {
    const predicates = new relationalStore.RdbPredicates(TABLE_USERS);
    predicates.orderByDesc('create_time');
    const resultSet = await rdbStore.query(predicates);
    const users: User[] = [];
    while (resultSet.goToNextRow()) {
      const user = rowToUser(resultSet);
      if (user !== null) {
        users.push(user);
      }
    }
    resultSet.close();
    return users;
  } catch (err) {
    console.error('[DB] queryAllUsers error: ' + JSON.stringify(err));
    return [];
  }
}

export async function deleteUser(userId: number): Promise<number> {
  if (rdbStore === null) return -1;
  try {
    const predicates = new relationalStore.RdbPredicates(TABLE_USERS);
    predicates.equalTo('id', userId);
    const rows = await rdbStore.delete(predicates);
    console.info('[DB] deleteUser rows=' + rows.toString());
    return rows;
  } catch (err) {
    console.error('[DB] deleteUser error: ' + JSON.stringify(err));
    return -1;
  }
}

// ==================== 投喂计划和记录 ====================

function rowToFeedingPlan(resultSet: relationalStore.ResultSet): FeedingPlan | null {
  try {
    return {
      id: resultSet.getLong(resultSet.getColumnIndex('id')) ?? 0,
      petId: resultSet.getLong(resultSet.getColumnIndex('pet_id')) ?? 0,
      feedTime: resultSet.getString(resultSet.getColumnIndex('feed_time')) ?? '',
      amount: resultSet.getLong(resultSet.getColumnIndex('amount')) ?? 0,
      enabled: resultSet.getLong(resultSet.getColumnIndex('enabled')) === 1,
      createTime: resultSet.getLong(resultSet.getColumnIndex('create_time')) ?? 0
    };
  } catch (err) {
    console.error('[DB] rowToFeedingPlan error: ' + JSON.stringify(err));
    return null;
  }
}

function rowToFeedingRecord(resultSet: relationalStore.ResultSet): FeedingRecord | null {
  try {
    return {
      id: resultSet.getLong(resultSet.getColumnIndex('id')) ?? 0,
      petId: resultSet.getLong(resultSet.getColumnIndex('pet_id')) ?? 0,
      amount: resultSet.getLong(resultSet.getColumnIndex('amount')) ?? 0,
      isManual: resultSet.getLong(resultSet.getColumnIndex('is_manual')) === 1,
      timestamp: resultSet.getLong(resultSet.getColumnIndex('timestamp')) ?? 0
    };
  } catch (err) {
    console.error('[DB] rowToFeedingRecord error: ' + JSON.stringify(err));
    return null;
  }
}

export async function insertFeedingPlan(plan: FeedingPlan): Promise<number> {
  if (rdbStore === null) return -1;
  try {
    const value: relationalStore.ValuesBucket = {
      pet_id: plan.petId,
      feed_time: plan.feedTime,
      amount: plan.amount,
      enabled: plan.enabled ? 1 : 0,
      create_time: plan.createTime
    };
    const rowId = await rdbStore.insert(TABLE_FEEDING_PLANS, value);
    console.info('[DB] insertFeedingPlan rowId: ' + rowId);
    return rowId;
  } catch (err) {
    console.error('[DB] insertFeedingPlan error: ' + JSON.stringify(err));
    return -1;
  }
}

export async function updateFeedingPlan(plan: FeedingPlan): Promise<number> {
  if (rdbStore === null) return -1;
  try {
    const value: relationalStore.ValuesBucket = {
      feed_time: plan.feedTime,
      amount: plan.amount,
      enabled: plan.enabled ? 1 : 0
    };
    const predicates = new relationalStore.RdbPredicates(TABLE_FEEDING_PLANS);
    predicates.equalTo('id', plan.id);
    const rows = await rdbStore.update(value, predicates);
    console.info('[DB] updateFeedingPlan rows: ' + rows);
    return rows;
  } catch (err) {
    console.error('[DB] updateFeedingPlan error: ' + JSON.stringify(err));
    return -1;
  }
}

export async function deleteFeedingPlan(planId: number): Promise<number> {
  if (rdbStore === null) return -1;
  try {
    const predicates = new relationalStore.RdbPredicates(TABLE_FEEDING_PLANS);
    predicates.equalTo('id', planId);
    const rows = await rdbStore.delete(predicates);
    console.info('[DB] deleteFeedingPlan rows: ' + rows);
    return rows;
  } catch (err) {
    console.error('[DB] deleteFeedingPlan error: ' + JSON.stringify(err));
    return -1;
  }
}

export async function getFeedingPlansByPet(petId: number): Promise<FeedingPlan[]> {
  if (rdbStore === null) return [];
  try {
    const predicates = new relationalStore.RdbPredicates(TABLE_FEEDING_PLANS);
    predicates.equalTo('pet_id', petId);
    predicates.orderByAsc('feed_time');
    const resultSet = await rdbStore.query(predicates);
    const plans: FeedingPlan[] = [];
    while (resultSet.goToNextRow()) {
      const plan = rowToFeedingPlan(resultSet);
      if (plan !== null) {
        plans.push(plan);
      }
    }
    resultSet.close();
    return plans;
  } catch (err) {
    console.error('[DB] getFeedingPlansByPet error: ' + JSON.stringify(err));
    return [];
  }
}

export async function insertFeedingRecord(record: FeedingRecord): Promise<number> {
  if (rdbStore === null) return -1;
  try {
    const value: relationalStore.ValuesBucket = {
      pet_id: record.petId,
      amount: record.amount,
      is_manual: record.isManual ? 1 : 0,
      timestamp: record.timestamp
    };
    const rowId = await rdbStore.insert(TABLE_FEEDING_RECORDS, value);
    console.info('[DB] insertFeedingRecord rowId: ' + rowId);
    return rowId;
  } catch (err) {
    console.error('[DB] insertFeedingRecord error: ' + JSON.stringify(err));
    return -1;
  }
}

export async function getFeedingRecordsByPet(petId: number, limit: number = 20): Promise<FeedingRecord[]> {
  if (rdbStore === null) return [];
  try {
    const predicates = new relationalStore.RdbPredicates(TABLE_FEEDING_RECORDS);
    predicates.equalTo('pet_id', petId);
    predicates.orderByDesc('timestamp');
    predicates.limitAs(limit);
    const resultSet = await rdbStore.query(predicates);
    const records: FeedingRecord[] = [];
    while (resultSet.goToNextRow()) {
      const record = rowToFeedingRecord(resultSet);
      if (record !== null) {
        records.push(record);
      }
    }
    resultSet.close();
    return records;
  } catch (err) {
    console.error('[DB] getFeedingRecordsByPet error: ' + JSON.stringify(err));
    return [];
  }
}

// ==================== 互动记录 CRUD ====================

function rowToInteractionRecord(resultSet: relationalStore.ResultSet): InteractionRecord | null {
  try {
    return {
      id: resultSet.getLong(resultSet.getColumnIndex('id')) ?? 0,
      petId: resultSet.getLong(resultSet.getColumnIndex('pet_id')) ?? 0,
      interactionType: resultSet.getString(resultSet.getColumnIndex('interaction_type')) ?? '',
      content: resultSet.getString(resultSet.getColumnIndex('content')) ?? '',
      timestamp: resultSet.getLong(resultSet.getColumnIndex('timestamp')) ?? 0
    };
  } catch (err) {
    console.error('[DB] rowToInteractionRecord error: ' + JSON.stringify(err));
    return null;
  }
}

export async function insertInteractionRecord(record: InteractionRecord): Promise<number> {
  if (rdbStore === null) return -1;
  try {
    const value: relationalStore.ValuesBucket = {
      pet_id: record.petId,
      interaction_type: record.interactionType,
      content: record.content,
      timestamp: record.timestamp
    };
    const rowId = await rdbStore.insert(TABLE_INTERACTIONS, value);
    console.info('[DB] insertInteractionRecord rowId: ' + rowId);
    return rowId;
  } catch (err) {
    console.error('[DB] insertInteractionRecord error: ' + JSON.stringify(err));
    return -1;
  }
}

export async function getInteractionRecordsByPet(petId: number, limit: number = 20): Promise<InteractionRecord[]> {
  if (rdbStore === null) return [];
  try {
    const predicates = new relationalStore.RdbPredicates(TABLE_INTERACTIONS);
    predicates.equalTo('pet_id', petId);
    predicates.orderByDesc('timestamp');
    predicates.limitAs(limit);
    const resultSet = await rdbStore.query(predicates);
    const records: InteractionRecord[] = [];
    while (resultSet.goToNextRow()) {
      const record = rowToInteractionRecord(resultSet);
      if (record !== null) {
        records.push(record);
      }
    }
    resultSet.close();
    return records;
  } catch (err) {
    console.error('[DB] getInteractionRecordsByPet error: ' + JSON.stringify(err));
    return [];
  }
}
