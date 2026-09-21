// FeedingManager.ets — 投喂计划和记录管理

import { FeedingPlan, FeedingRecord } from '../model/FeedingPlan';
import {
  insertFeedingPlan,
  updateFeedingPlan,
  deleteFeedingPlan,
  getFeedingPlansByPet,
  insertFeedingRecord,
  getFeedingRecordsByPet
} from '../database/DatabaseService';
import { getCurrentPetId } from './PetDataManager';

// 获取当前宠物的投喂计划
export async function getFeedingPlans(): Promise<FeedingPlan[]> {
  const petId = getCurrentPetId();
  if (petId <= 0) return [];
  return await getFeedingPlansByPet(petId);
}

// 创建新的投喂计划
export async function createFeedingPlan(feedTime: string, amount: number): Promise<number> {
  const petId = getCurrentPetId();
  if (petId <= 0) return -1;
  const plan: FeedingPlan = {
    id: 0,
    petId: petId,
    feedTime: feedTime,
    amount: amount,
    enabled: true,
    createTime: Date.now()
  };
  return await insertFeedingPlan(plan);
}

// 更新投喂计划
export async function updatePlan(plan: FeedingPlan): Promise<boolean> {
  const rows = await updateFeedingPlan(plan);
  return rows > 0;
}

// 删除投喂计划
export async function removeFeedingPlan(planId: number): Promise<boolean> {
  const rows = await deleteFeedingPlan(planId);
  return rows > 0;
}

// 记录投喂（手动投喂）
export async function recordFeeding(amount: number): Promise<number> {
  const petId = getCurrentPetId();
  if (petId <= 0) return -1;
  const record: FeedingRecord = {
    id: 0,
    petId: petId,
    amount: amount,
    isManual: true,
    timestamp: Date.now()
  };
  return await insertFeedingRecord(record);
}

// 获取投喂历史
export async function getFeedingHistory(): Promise<FeedingRecord[]> {
  const petId = getCurrentPetId();
  if (petId <= 0) return [];
  return await getFeedingRecordsByPet(petId, 30);
}
