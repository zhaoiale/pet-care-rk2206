// FeedingPage.ets — 智能投喂页（UI 优化版，逻辑不变）
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
import { Theme } from '../common/Theme';

interface FeedRecord {
  time: string;
  amount: number;
}

@Entry
@Component
export struct FeedingPage {
  @State feedingPlans: FeedingPlan[] = [];
  @State feedHistory: FeedingRecord[] = [];
  @State feedAmount: number = 350;
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
    if (diff < 60000) { return '刚刚'; }
    else if (diff < 3600000) { return Math.floor(diff / 60000) + '分钟前'; }
    else if (date.toDateString() === now.toDateString()) {
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
      if (planTime > currentTime) { return plan.feedTime; }
    }
    for (const plan of this.feedingPlans) {
      if (plan.enabled) { return plan.feedTime; }
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
      // 标题栏
      Row() {
        Image($rawfile('image/ic_back.svg')).width(22).height(22)
          .fillColor(Theme.TEXT_PRIMARY).onClick(() => { router.back(); });
        Blank();
        Text('智能投喂').fontSize(19).fontWeight(FontWeight.Bold).fontColor(Theme.TEXT_PRIMARY);
        Blank();
        Text('').width(22);
      }
      .width('100%').padding({ left: 16, right: 16, top: 14, bottom: 12 });

      if (this.isLoading) {
        Column() {
          LoadingProgress().width(40).height(40).color(Theme.PRIMARY);
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center);
      } else {
        Scroll() {
          Column() {
            // 下次投喂 Hero 卡
            Column() {
              Row() {
                Image($rawfile('image/ic_schedule.svg')).width(18).height(18).fillColor(Theme.TEXT_WHITE);
                Text('下次投喂').fontSize(13).fontColor('#CCFFFFFF').margin({ left: 6 });
                Blank();
              }
              .width('100%');
              Text(this.getNextFeedTime())
                .fontSize(48).fontWeight(FontWeight.Bold).fontColor(Theme.TEXT_WHITE)
                .margin({ top: 8 });
              if (this.feedingPlans.length > 0) {
                Text(`计划出粮 ${this.feedingPlans.find(p => p.enabled)?.amount || 350}g`)
                  .fontSize(13).fontColor('#CCFFFFFF').margin({ top: 4 });
              }
            }
            .width('100%').padding(22).backgroundColor(Theme.PRIMARY)
            .borderRadius(Theme.RADIUS_XL).margin({ bottom: 16 });

            // 上次投喂
            if (this.feedHistory.length > 0) {
              Row() {
                Image($rawfile('image/ic_food.svg')).width(16).height(16).fillColor(Theme.WARNING);
                Text('上次投喂：').fontSize(13).fontColor(Theme.TEXT_TERTIARY).margin({ left: 6 });
                Text(this.formatTime(this.feedHistory[0].timestamp))
                  .fontSize(13).fontColor(Theme.TEXT_PRIMARY).fontWeight(FontWeight.Medium);
                Blank();
                Text(`${this.feedHistory[0].amount}g`).fontSize(13).fontColor(Theme.WARNING).fontWeight(FontWeight.Medium);
              }
              .width('100%').padding(14).backgroundColor(Theme.CARD)
              .borderRadius(Theme.RADIUS_LG).margin({ bottom: 16 })
              .shadow({ radius: 8, color: '#0A000000', offsetX: 0, offsetY: 2 });
            }

            // 投喂计划
            Column() {
              Row() {
                Text('投喂计划').fontSize(16).fontWeight(FontWeight.Bold).fontColor(Theme.TEXT_PRIMARY);
                Blank();
                Button() {
                  Row() {
                    Image($rawfile('image/ic_add.svg')).width(14).height(14).fillColor(Theme.TEXT_WHITE);
                    Text('添加').fontSize(12).fontColor(Theme.TEXT_WHITE).margin({ left: 4 });
                  }
                }
                .height(30).backgroundColor(Theme.PRIMARY).borderRadius(Theme.RADIUS_PILL)
                .padding({ left: 12, right: 12 })
                .onClick(() => { this.showAddPlan = true; });
              }
              .width('100%').margin({ bottom: 12 });

              // 添加计划表单
              if (this.showAddPlan) {
                Column() {
                  Row() {
                    Text('时间').fontSize(13).fontColor(Theme.TEXT_SECONDARY).width(50);
                    TextInput({ text: this.newPlanTime })
                      .layoutWeight(1).height(40).backgroundColor(Theme.CARD_SOFT)
                      .borderRadius(Theme.RADIUS_SM).padding({ left: 10 })
                      .onChange((value: string) => { this.newPlanTime = value; });
                    Text('克数').fontSize(13).fontColor(Theme.TEXT_SECONDARY).margin({ left: 10 }).width(50);
                    TextInput({ text: this.newPlanAmount.toString() })
                      .width(70).height(40).backgroundColor(Theme.CARD_SOFT)
                      .borderRadius(Theme.RADIUS_SM).padding({ left: 10 })
                      .onChange((value: string) => { this.newPlanAmount = Number(value) || 350; });
                  }
                  .width('100%').margin({ bottom: 12 });
                  Row() {
                    Button('取消').fontSize(13).height(36).backgroundColor(Theme.TEXT_TERTIARY)
                      .borderRadius(Theme.RADIUS_PILL).layoutWeight(1)
                      .onClick(() => { this.showAddPlan = false; });
                    Button('保存').fontSize(13).height(36).backgroundColor(Theme.SUCCESS)
                      .borderRadius(Theme.RADIUS_PILL).layoutWeight(1).margin({ left: 10 })
                      .onClick(async () => {
                        const newId = await createFeedingPlan(this.newPlanTime, this.newPlanAmount);
                        if (newId > 0) {
                          await this.loadData();
                          await this.syncScheduleToFirmware();
                          this.showAddPlan = false;
                          await promptAction.showDialog({
                            title: '添加成功', message: '投喂计划已添加',
                            buttons: [{ text: '好的', color: Theme.SUCCESS }]
                          });
                        }
                      });
                  }
                  .width('100%');
                }
                .width('100%').padding(14).backgroundColor(Theme.PRIMARY_SOFT)
                .borderRadius(Theme.RADIUS_LG).margin({ bottom: 12 });
              }

              if (this.feedingPlans.length === 0) {
                Column() {
                  Text('暂无投喂计划').fontSize(14).fontColor(Theme.TEXT_TERTIARY);
                  Text('点击右上角添加定时投喂').fontSize(12).fontColor(Theme.TEXT_TERTIARY).margin({ top: 4 });
                }
                .width('100%').padding({ top: 24, bottom: 24 });
              } else {
                ForEach(this.feedingPlans, (plan: FeedingPlan, index: number) => {
                  Row() {
                    Column() {
                      Text(plan.feedTime).fontSize(20).fontWeight(FontWeight.Bold).fontColor(Theme.TEXT_PRIMARY);
                      Text(`${plan.amount}g`).fontSize(12).fontColor(Theme.TEXT_TERTIARY).margin({ top: 2 });
                    }
                    .alignItems(HorizontalAlign.Start).layoutWeight(1);
                    // 启用开关
                    Text(plan.enabled ? '已启用' : '已禁用')
                      .fontSize(11).fontColor(plan.enabled ? Theme.SUCCESS : Theme.TEXT_TERTIARY)
                      .backgroundColor(plan.enabled ? Theme.SUCCESS + '18' : Theme.BORDER)
                      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                      .borderRadius(Theme.RADIUS_PILL)
                      .onClick(async () => {
                        plan.enabled = !plan.enabled;
                        await updatePlan(plan);
                        await this.loadData();
                        await this.syncScheduleToFirmware();
                      });
                    Image($rawfile('image/ic_delete.svg')).width(18).height(18)
                      .fillColor(Theme.DANGER).margin({ left: 12 })
                      .onClick(async () => {
                        const confirm = await promptAction.showDialog({
                          title: '确认删除', message: '确定要删除这个投喂计划吗？',
                          buttons: [
                            { text: '取消', color: Theme.TEXT_SECONDARY },
                            { text: '删除', color: Theme.DANGER }
                          ]
                        });
                        if (confirm.index === 1) {
                          await removeFeedingPlan(plan.id);
                          await this.loadData();
                          await this.syncScheduleToFirmware();
                        }
                      });
                  }
                  .width('100%').padding(14).backgroundColor(Theme.CARD)
                  .borderRadius(Theme.RADIUS_LG).margin({ bottom: 8 })
                  .shadow({ radius: 6, color: '#08000000', offsetX: 0, offsetY: 1 });
                });
              }
            }
            .width('100%').margin({ bottom: 16 });

            // 立即投喂
            Column() {
              Row() {
                Image($rawfile('image/ic_feed_manual.svg')).width(18).height(18).fillColor(Theme.WARNING);
                Text('立即投喂').fontSize(16).fontWeight(FontWeight.Bold)
                  .fontColor(Theme.TEXT_PRIMARY).margin({ left: 6 });
              }
              .width('100%').margin({ bottom: 12 });

              Row() {
                Text('投喂克数').fontSize(13).fontColor(Theme.TEXT_SECONDARY);
                Blank();
                TextInput({ text: this.feedAmount.toString() })
                  .width(90).height(40).backgroundColor(Theme.CARD_SOFT)
                  .borderRadius(Theme.RADIUS_SM).padding({ left: 10 }).textAlign(TextAlign.Center)
                  .onChange((value: string) => { this.feedAmount = Number(value) || 350; });
                Text('克').fontSize(13).fontColor(Theme.TEXT_SECONDARY).margin({ left: 6 });
              }
              .width('100%').margin({ bottom: 14 });

              Button('立即投喂')
                .width('100%').height(48).fontSize(16).fontWeight(FontWeight.Medium)
                .backgroundColor(Theme.WARNING).borderRadius(Theme.RADIUS_PILL)
                .onClick(async () => {
                  const recordId = await recordFeeding(this.feedAmount);
                  if (recordId > 0) {
                    await sendFeedCommand(this.feedAmount);
                    await this.loadData();
                    await promptAction.showDialog({
                      title: '投喂成功', message: `已出粮 ${this.feedAmount}g`,
                      buttons: [{ text: '好的', color: Theme.WARNING }]
                    });
                  }
                });
            }
            .width('100%').padding(18).backgroundColor(Theme.CARD)
            .borderRadius(Theme.RADIUS_XL).margin({ bottom: 16 })
            .shadow({ radius: 10, color: '#0D000000', offsetX: 0, offsetY: 2 });

            // 投喂历史
            Column() {
              Row() {
                Image($rawfile('image/ic_schedule.svg')).width(16).height(16).fillColor(Theme.INFO);
                Text('投喂历史').fontSize(16).fontWeight(FontWeight.Bold)
                  .fontColor(Theme.TEXT_PRIMARY).margin({ left: 6 });
              }
              .width('100%').margin({ bottom: 8 });

              if (this.feedHistory.length === 0) {
                Text('暂无投喂记录').fontSize(13).fontColor(Theme.TEXT_TERTIARY)
                  .width('100%').padding({ top: 16, bottom: 16 }).textAlign(TextAlign.Center);
              } else {
                ForEach(this.feedHistory, (item: FeedingRecord, index: number) => {
                  Row() {
                    Circle({ width: 6, height: 6 }).fill(Theme.INFO);
                    Text(this.formatTime(item.timestamp)).fontSize(13).fontColor(Theme.TEXT_SECONDARY)
                      .margin({ left: 10 }).layoutWeight(1);
                    Text(`${item.amount}g`).fontSize(14).fontWeight(FontWeight.Medium).fontColor(Theme.TEXT_PRIMARY);
                  }
                  .width('100%').padding({ top: 10, bottom: 10 })
                  .border({ width: { bottom: 0.5 }, color: Theme.DIVIDER });
                });
              }
            }
            .width('100%').padding(18).backgroundColor(Theme.CARD)
            .borderRadius(Theme.RADIUS_XL).margin({ bottom: 20 })
            .shadow({ radius: 10, color: '#0D000000', offsetX: 0, offsetY: 2 });
          }
          .width('100%').padding({ left: 16, right: 16 });
        }
        .width('100%').layoutWeight(1).scrollBar(BarState.Off);
      }
    }
    .width('100%').height('100%').backgroundColor(Theme.BG);
  }
}
