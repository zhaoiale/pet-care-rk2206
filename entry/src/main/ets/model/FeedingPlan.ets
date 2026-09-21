// FeedingPlan.ets — 投喂计划和记录模型

// 投喂计划
export interface FeedingPlan {
  id: number;
  petId: number;         // 关联的宠物ID
  feedTime: string;      // 投喂时间，格式 "HH:mm"
  amount: number;        // 投喂克数 (g)
  enabled: boolean;      // 是否启用
  createTime: number;    // 创建时间戳
}

// 投喂历史记录
export interface FeedingRecord {
  id: number;
  petId: number;         // 关联的宠物ID
  amount: number;        // 投喂克数 (g)
  isManual: boolean;     // 是否手动投喂
  timestamp: number;     // 投喂时间戳
}
