// FeedingPage.ets
import promptAction from '@ohos.promptAction';
import { FeedingPlan, FeedingRecord } from '../model/FeedingPlan';
import {
  getFeedingPlans,
  createFeedingPlan,
  updatePlan,
  removeFeedingPlan,
  recordFeeding,
  getFeedingHistory
} from '../utils/FeedingManager';
import { sendFeedCommand, sendScheduleSyncCommand, sendTimeSyncCommand, SchedulePlanItem } from '../services/MqttService';
import router from '@ohos.router';

interface FeedRecord {
  time: string;
  amount: number;
}

@Entry
@Component
export struct FeedingPage {
  @State feedingPlans: FeedingPlan[] = [];
  @State feedHistory: FeedingRecord[] = [];
  @State feedAmount: number = 350;       // 单位：克g
  @State showAddPlan: boolean = false;
  @State newPlanTime: string = '08:00';
  @State newPlanAmount: number = 350;
  @State isLoading: boolean = true;

  async aboutToAppear() {
    await this.loadData();
    await this.syncScheduleToFirmware();
  }

  async onPageShow() {
    await this.loadData();
    await this.syncScheduleToFirmware();
  }

  async loadData() {
    this.isLoading = true;
    this.feedingPlans = await getFeedingPlans();
    this.feedHistory = await getFeedingHistory();
    this.isLoading = false;
  }

  formatTime(timestamp: number): string {
    const date = new Date(timestamp);
    const now = new Date();
    const diff = now.getTime() - timestamp;
    
    if (diff < 60000) { // 1分钟内
      return '刚刚';
    } else if (diff < 3600000) { // 1小时内
      return Math.floor(diff / 60000) + '分钟前';
    } else if (date.toDateString() === now.toDateString()) {
      const hour = date.getHours().toString().padStart(2, '0');
      const minute = date.getMinutes().toString().padStart(2, '0');
      return `今天 ${hour}:${minute}`;
    } else {
      const yesterday = new Date(now);
      yesterday.setDate(yesterday.getDate() - 1);
      if (date.toDateString() === yesterday.toDateString()) {
        const hour = date.getHours().toString().padStart(2, '0');
        const minute = date.getMinutes().toString().padStart(2, '0');
        return `昨天 ${hour}:${minute}`;
      } else {
        const month = (date.getMonth() + 1).toString().padStart(2, '0');
        const day = date.getDate().toString().padStart(2, '0');
        const hour = date.getHours().toString().padStart(2, '0');
        const minute = date.getMinutes().toString().padStart(2, '0');
        return `${month}-${day} ${hour}:${minute}`;
      }
    }
  }

  getNextFeedTime(): string {
    if (this.feedingPlans.length === 0) return '暂无计划';
    
    const now = new Date();
    const currentTime = now.getHours() * 60 + now.getMinutes();
    
    for (const plan of this.feedingPlans) {
      if (!plan.enabled) continue;
      const timeParts = plan.feedTime.split(':');
      const hour = Number(timeParts[0]);
      const minute = Number(timeParts[1]);
      const planTime = hour * 60 + minute;
      if (planTime > currentTime) {
        return plan.feedTime;
      }
    }
    
    // 如果没有找到未来的计划，返回第一个计划
    for (const plan of this.feedingPlans) {
      if (plan.enabled) {
        return plan.feedTime;
      }
    }
    
    return '暂无计划';
  }

  async syncScheduleToFirmware() {
    const plans = await getFeedingPlans();
    const syncData: SchedulePlanItem[] = [];
    for (const p of plans) {
      const item: SchedulePlanItem = { time: p.feedTime, amount: p.amount, enabled: p.enabled };
      syncData.push(item);
    }
    await sendScheduleSyncCommand(syncData);
    await sendTimeSyncCommand();
  }

  build() {
    Column() {
      // 标题
      Row() {
        Text('< 返回')
          .fontSize(16)
          .fontColor('#2196F3')
          .onClick(() => { router.back(); })
        Blank()
        Text('智能投喂')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
        Blank()
        Text('').width(50)
      }
      .width('100%')
      .padding({ left: 15, right: 15, top: 30, bottom: 10 })

      if (this.isLoading) {
        LoadingProgress()
          .width(40)
          .height(40)
          .margin({ top: 50 })
      } else {
        // 下次投喂卡片
        Column() {
          Text('下次投喂')
            .fontSize(16)
            .fontColor('#666')
          Text(this.getNextFeedTime())
            .fontSize(52)
            .fontWeight(FontWeight.Bold)
            .fontColor('#4CAF50')
            .margin({ top: 8 })
          if (this.feedingPlans.length > 0) {
            Text(`计划出粮 ${this.feedingPlans.find(p => p.enabled)?.amount || 350}g`)
              .fontSize(14)
              .fontColor('#999')
              .margin({ top: 5 })
          }
        }
        .width('85%')
        .padding(20)
        .backgroundColor('#F5F5F5')
        .borderRadius(20)
        .margin({ top: 20 })

        // 上次投喂记录
        if (this.feedHistory.length > 0) {
          Row() {
            Text('上次投喂：')
              .fontSize(14)
              .fontColor('#666')
            Text(this.formatTime(this.feedHistory[0].timestamp))
              .fontSize(14)
              .fontColor('#333')
          }
          .width('85%')
          .margin({ top: 15 })
        }

        Divider()
          .margin({ top: 25, bottom: 25 })

        // 投喂计划列表
        Column() {
          Row() {
            Text('投喂计划')
              .fontSize(18)
              .fontWeight(FontWeight.Medium)
            Blank()
            Button('添加')
              .fontSize(14)
              .backgroundColor('#2196F3')
              .borderRadius(15)
              .width(60)
              .height(30)
              .onClick(() => {
                this.showAddPlan = true;
              })
          }
          .width('100%')
          .margin({ bottom: 10 })

          if (this.showAddPlan) {
            Column() {
              Row() {
                Text('时间：')
                  .fontSize(14)
                TextInput({ text: this.newPlanTime })
                  .width(80)
                  .height(35)
                  .onChange((value: string) => {
                    this.newPlanTime = value;
                  })
                Blank()
                Text('克数：')
                  .fontSize(14)
                TextInput({ text: this.newPlanAmount.toString() })
                  .width(60)
                  .height(35)
                  .onChange((value: string) => {
                    this.newPlanAmount = Number(value) || 350;
                  })
                Text('克')
                  .fontSize(14)
              }
              .width('100%')
              .margin({ bottom: 10 })
              Row() {
                Button('取消')
                  .fontSize(14)
                  .backgroundColor('#999')
                  .borderRadius(15)
                  .onClick(() => {
                    this.showAddPlan = false;
                  })
                Blank()
                Button('保存')
                  .fontSize(14)
                  .backgroundColor('#4CAF50')
                  .borderRadius(15)
                  .onClick(async () => {
                    const newId = await createFeedingPlan(this.newPlanTime, this.newPlanAmount);
                    if (newId > 0) {
                      await this.loadData();
                      await this.syncScheduleToFirmware();
                      this.showAddPlan = false;
                      await promptAction.showDialog({
                        title: '添加成功',
                        message: '投喂计划已添加',
                        buttons: [{ text: '好的', color: '#4CAF50' }]
                      });
                    }
                  })
              }
              .width('100%')
            }
            .width('100%')
            .padding(15)
            .backgroundColor('#F0F0F0')
            .borderRadius(10)
            .margin({ bottom: 10 })
          }

          if (this.feedingPlans.length === 0) {
            Text('暂无投喂计划')
              .fontSize(14)
              .fontColor('#999')
              .margin({ top: 20, bottom: 20 })
          } else {
            ForEach(this.feedingPlans, (plan: FeedingPlan, index: number) => {
              Row() {
                Text(plan.feedTime)
                  .fontSize(18)
                  .fontWeight(FontWeight.Medium)
                Text(`${plan.amount}g`)
                  .fontSize(16)
                  .fontColor('#666')
                  .margin({ left: 10 })
                Blank()
                Text(plan.enabled ? '已启用' : '已禁用')
                  .fontSize(12)
                  .fontColor(plan.enabled ? '#4CAF50' : '#999')
                  .onClick(async () => {
                    plan.enabled = !plan.enabled;
                    await updatePlan(plan);
                    await this.loadData();
                    await this.syncScheduleToFirmware();
                  })
                Text('删除')
                  .fontSize(12)
                  .fontColor('#F44336')
                  .margin({ left: 15 })
                  .onClick(async () => {
                    const confirm = await promptAction.showDialog({
                      title: '确认删除',
                      message: '确定要删除这个投喂计划吗？',
                      buttons: [
                        { text: '取消', color: '#666' },
                        { text: '删除', color: '#F44336' }
                      ]
                    });
                    if (confirm.index === 1) {
                      await removeFeedingPlan(plan.id);
                      await this.loadData();
                      await this.syncScheduleToFirmware();
                    }
                  })
              }
              .width('100%')
              .padding({ top: 12, bottom: 12 })
              .border({ width: { bottom: 0.5 }, color: '#E0E0E0' })
            })
          }
        }
        .width('85%')

        // 立即投喂设置
        Column() {
          Text('立即投喂')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .width('100%')
            .margin({ top: 20, bottom: 10 })
          Row() {
            Text('投喂克数：')
              .fontSize(14)
              .fontColor('#666')
            TextInput({ text: this.feedAmount.toString() })
              .width(80)
              .height(40)
              .onChange((value: string) => {
                this.feedAmount = Number(value) || 350;
              })
            Text('克')
              .fontSize(14)
              .fontColor('#666')
          }
          .width('100%')
          .margin({ bottom: 15 })
          Button('立即投喂')
            .width('100%')
            .height(45)
            .fontSize(16)
            .backgroundColor('#FF9800')
            .borderRadius(25)
            .onClick(async () => {
              const recordId = await recordFeeding(this.feedAmount);
              if (recordId > 0) {
                await sendFeedCommand(this.feedAmount);
                await this.loadData();
                await promptAction.showDialog({
                  title: '投喂成功',
                  message: `已出粮 ${this.feedAmount}g`,
                  buttons: [{ text: '好的', color: '#FF9800' }]
                });
              }
            })
        }
        .width('85%')
        .margin({ top: 20 })

        // 投喂历史记录
        Column() {
          Text('投喂历史')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .width('100%')
            .margin({ top: 25, bottom: 10 })

          if (this.feedHistory.length === 0) {
            Text('暂无投喂记录')
              .fontSize(14)
              .fontColor('#999')
              .margin({ top: 20, bottom: 20 })
          } else {
            ForEach(this.feedHistory, (item: FeedingRecord, index: number) => {
              Row() {
                Text(this.formatTime(item.timestamp))
                  .fontSize(14)
                  .fontColor('#666')
                Blank()
                Text(`${item.amount}g`)
                  .fontSize(14)
                  .fontColor('#333')
              }
              .width('100%')
              .padding({ top: 10, bottom: 10 })
              .border({ width: { bottom: 0.5 }, color: '#E0E0E0' })
            })
          }
        }
        .width('85%')
        .margin({ top: 20 })
      }
    }
    .width('100%')
    .height('100%')
  }
}