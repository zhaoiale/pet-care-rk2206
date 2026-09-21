// HomePage.ets — 首页（UI 优化版，逻辑不变）
import router from '@ohos.router';
import { getLatestRecord, queryRecords, getRecordCount, insertSensorRecord } from '../database/DatabaseService';
import { getConnectionStatus, sendRefreshCommand, sendSetHomeCommand } from '../services/MqttService';
import { SensorRecord } from '../model/SensorRecord';
import { lastGeofenceStatus, lastGpsLat, lastGpsLon, lastVoiceIntent, lastEmotion, lastAnxiety } from '../services/MqttService';
import { promptAction } from '@kit.ArkUI';
import { Theme, anxietyColor, emotionLabel } from '../common/Theme';

const DATA_UPDATE_KEY: string = 'dataUpdateKey';

@Entry
@Component
export struct HomePage {
  @StorageLink('anxietyIndex') anxietyIndex: number = 0;
  @StorageLink('temperature') temperature: number = 0;
  @StorageLink('humidity') humidity: number = 0;
  @StorageLink('petName') petName: string = '暂无宠物';
  @State illumination: number = 0;
  @State foodWeight: number = 0;
  @State foodEaten: number = 0;
  @StorageLink('activityLevel') activityLevel: string = '--';
  @State lastUpdateTime: string = '等待硬件数据...';
  @State mqttDotColor: string = '#FF0000';
  @State statusText: string = 'MQTT断开';
  @State refreshCounter: number = 0;
  @State heartRate: number = 0;
  @State spo2: number = 0;
  @State bodyTemp: number = 0;
  @State geofenceStatus: number = 0;
  @State gpsLat: number = 0;
  @State gpsLon: number = 0;
  @State emotion: string = '--';
  @State isLoading: boolean = true;
  private timerId: number = -1;

  @Watch('onDataUpdate')
  @StorageLink(DATA_UPDATE_KEY) dataUpdateKey: number = 0;

  aboutToAppear() {
    console.info('[HomePage] aboutToAppear called at:', new Date().toLocaleTimeString());
    this.emotion = lastEmotion;
    this.loadRealData();
    this.startAutoRefresh();
  }

  aboutToDisappear() {
    console.info('[HomePage] aboutToDisappear called, clearing timer:', this.timerId);
    if (this.timerId !== -1) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  onDataUpdate() {
    this.refreshData();
  }

  startAutoRefresh() {
    this.timerId = setInterval(async () => {
      await this.refreshData();
      this.updateMqttStatus();
      const currentKey = AppStorage.Get<number>(DATA_UPDATE_KEY) ?? 0;
      AppStorage.SetOrCreate(DATA_UPDATE_KEY, currentKey + 1);
    }, 5000);
  }

  updateMqttStatus() {
    if (getConnectionStatus()) {
      this.mqttDotColor = Theme.SUCCESS;
      this.statusText = '已连接';
    } else {
      this.mqttDotColor = Theme.DANGER;
      this.statusText = '断开';
    }
  }

  isRecent(timestamp: number): boolean {
    return (Date.now() - timestamp) < 300000;
  }

  async loadRealData() {
    try {
      const latest = await getLatestRecord();
      if (latest !== null) {
        if (this.isRecent(latest.timestamp)) {
          this.applyRecord(latest);
          console.info('[HomePage] loadRealData: recent record applied');
        } else {
          this.applyRecord(latest);
          this.lastUpdateTime = new Date(latest.timestamp).toLocaleTimeString() + ' (历史)';
          console.info('[HomePage] loadRealData: fallback to archived record');
        }
      } else {
        this.emotion = lastEmotion;
      }
    } catch (_err) {
      console.error('[HomePage] loadRealData error');
      this.emotion = lastEmotion;
    }
    this.isLoading = false;
  }

  applyRecord(r: SensorRecord) {
    this.anxietyIndex = r.anxietyLevel;
    this.temperature = r.temperature;
    this.humidity = r.humidity;
    this.illumination = r.illumination;
    this.foodWeight = r.foodWeight;
    this.foodEaten = r.foodEaten;
    this.heartRate = r.heartRate;
    this.spo2 = r.spo2;
    this.bodyTemp = r.bodyTemp;
    this.geofenceStatus = r.geofenceStatus;
    this.gpsLat = r.gpsLat;
    this.gpsLon = r.gpsLon;
    this.emotion = r.emotion || lastEmotion;
    this.lastUpdateTime = new Date(r.timestamp).toLocaleTimeString();
    this.activityLevel = r.anxietyLevel >= 80 ? '焦躁' :
      r.anxietyLevel <= 20 ? '安静' : '正常';
  }

  async refreshData() {
    try {
      const latest = await getLatestRecord();
      if (latest !== null && this.isRecent(latest.timestamp)) {
        this.applyRecord(latest);
      }
      this.geofenceStatus = lastGeofenceStatus;
      this.gpsLat = lastGpsLat;
      this.gpsLon = lastGpsLon;
      if (lastAnxiety > 0) {
        this.anxietyIndex = lastAnxiety;
      }
      this.emotion = lastEmotion;
      if (lastVoiceIntent.length > 0 && this.emotion === '--') {
        this.emotion = lastVoiceIntent;
      }
      this.refreshCounter++;
    } catch (_err) {
      console.error('[HomePage] refreshData error');
      this.lastUpdateTime = '读取失败';
      this.emotion = lastEmotion;
    }
  }

  // ── UI 构建器 ──

  // 切换到指定 tab（首页在 Index Tab 内，直接改全局 tab 索引即可）
  switchTab(index: number) {
    AppStorage.SetOrCreate('currentTabIndex', index);
  }

  // 指标卡（图标 + 标签 + 数值 + 单位 + 状态）
  @Builder
  MetricCard(icon: Resource, iconTint: string, label: string, value: string,
    unit: string, status: string, statusColor: string) {
    Column() {
      Row() {
        Image(icon).width(18).height(18).fillColor(iconTint);
        Text(label).fontSize(12).fontColor(Theme.TEXT_TERTIARY).margin({ left: 6 });
        Blank();
      }
      .width('100%');

      Row() {
        Text(value).fontSize(26).fontWeight(FontWeight.Bold).fontColor(Theme.TEXT_PRIMARY);
        Text(unit).fontSize(11).fontColor(Theme.TEXT_TERTIARY).margin({ left: 2, top: 8 });
      }
      .width('100%').margin({ top: 6 });

      Text(status).fontSize(11).fontColor(statusColor)
        .width('100%').margin({ top: 2 });
    }
    .width('100%').layoutWeight(1).padding(14).backgroundColor(Theme.CARD)
    .borderRadius(Theme.RADIUS_LG)
    .shadow({ radius: 10, color: '#0D000000', offsetX: 0, offsetY: 2 });
  }

  // 快捷导航卡
  @Builder
  NavCard(icon: Resource, label: string, tint: string, onClick: () => void) {
    Column() {
      Image(icon).width(24).height(24).fillColor(tint);
      Text(label).fontSize(12).fontColor(Theme.TEXT_SECONDARY).margin({ top: 6 });
    }
    .width('100%').layoutWeight(1).padding({ top: 14, bottom: 14 })
    .backgroundColor(Theme.CARD).borderRadius(Theme.RADIUS_LG)
    .shadow({ radius: 8, color: '#0A000000', offsetX: 0, offsetY: 2 })
    .onClick(onClick);
  }

  build() {
    Column() {
      if (this.isLoading) {
        Column() {
          LoadingProgress().width(44).height(44).color(Theme.PRIMARY);
          Text('加载中...').fontSize(14).fontColor(Theme.TEXT_TERTIARY).margin({ top: 12 });
        }
        .width('100%').height('100%').justifyContent(FlexAlign.Center);
      } else {
        Scroll() {
          Column() {
            // ── 顶部：问候 + 宠物名 + MQTT 状态 ──
            Row() {
              Column() {
                Text('你好，主人').fontSize(13).fontColor(Theme.TEXT_TERTIARY);
                Text(this.petName).fontSize(22).fontWeight(FontWeight.Bold)
                  .fontColor(Theme.TEXT_PRIMARY).margin({ top: 2 });
              }
              .alignItems(HorizontalAlign.Start).layoutWeight(1);

              // MQTT 状态胶囊
              Row() {
                Circle({ width: 7, height: 7 }).fill(this.mqttDotColor);
                Text(this.statusText).fontSize(11).fontColor(this.mqttDotColor).margin({ left: 5 });
              }
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .backgroundColor(Theme.CARD).borderRadius(Theme.RADIUS_PILL);
            }
            .width('100%').margin({ top: 8, bottom: 4 });

            Text('数据更新于 ' + this.lastUpdateTime)
              .fontSize(11).fontColor(Theme.TEXT_TERTIARY).width('100%').margin({ bottom: 14 });

            // ── 宠物情绪名片（Hero 卡）──
            Row() {
              Column() {
                Row() {
                  Image($rawfile('image/ic_emotion.svg')).width(20).height(20)
                    .fillColor(Theme.TEXT_WHITE);
                  Text('情绪指数').fontSize(13).fontColor(Theme.TEXT_WHITE).margin({ left: 6 });
                  Blank();
                  Text(emotionLabel(this.emotion)).fontSize(12).fontColor(Theme.TEXT_WHITE)
                    .backgroundColor('#33FFFFFF').borderRadius(8)
                    .padding({ left: 8, right: 8, top: 3, bottom: 3 });
                }
                .width('100%');

                Row() {
                  Text(this.anxietyIndex.toString()).fontSize(44).fontWeight(FontWeight.Bold)
                    .fontColor(Theme.TEXT_WHITE);
                  Column() {
                    Text(this.anxietyIndex > 60 ? '偏高' : '正常').fontSize(13)
                      .fontColor(Theme.TEXT_WHITE);
                    Text('活动: ' + this.activityLevel).fontSize(11)
                      .fontColor('#CCFFFFFF').margin({ top: 2 });
                  }
                  .margin({ left: 12, top: 10 }).alignItems(HorizontalAlign.Start);
                  Blank();
                }
                .width('100%').margin({ top: 10 });
              }
              .layoutWeight(1).alignItems(HorizontalAlign.Start);
            }
            .width('100%').padding(18)
            .backgroundColor(anxietyColor(this.anxietyIndex))
            .borderRadius(Theme.RADIUS_XL)
            .margin({ bottom: 14 });

            // ── 健康指标 2×2 网格 ──
            Row({ space: 12 }) {
              this.MetricCard($rawfile('image/ic_temp.svg'), Theme.WARNING,
                '体温', this.bodyTemp > 0 ? this.bodyTemp.toFixed(1) : '--', '℃',
                this.bodyTemp > 0 ? (this.bodyTemp > 38.5 ? '发热' : this.bodyTemp > 37.5 ? '偏高' : '正常') : '等待数据',
                this.bodyTemp > 38.5 ? Theme.DANGER : this.bodyTemp > 37.5 ? Theme.WARNING : Theme.SUCCESS);
              this.MetricCard($rawfile('image/ic_heart.svg'), Theme.DANGER,
                '心率', this.heartRate.toFixed(0), 'bpm',
                this.heartRate > 100 ? '偏快' : this.heartRate > 0 ? '正常' : '--',
                this.heartRate > 100 ? Theme.DANGER : Theme.SUCCESS);
            }
            .width('100%').margin({ bottom: 12 });

            Row({ space: 12 }) {
              this.MetricCard($rawfile('image/ic_spo2.svg'), Theme.SUCCESS,
                '血氧', this.spo2.toFixed(0), '%',
                this.spo2 >= 95 ? '正常' : this.spo2 > 0 ? '偏低' : '--',
                this.spo2 >= 95 ? Theme.SUCCESS : this.spo2 > 0 ? Theme.DANGER : Theme.TEXT_TERTIARY);
              this.MetricCard($rawfile('image/ic_humidity.svg'), Theme.INFO,
                '环境', this.temperature.toFixed(1) + '° / ' + this.humidity.toFixed(0) + '%', '',
                '温湿度', Theme.TEXT_TERTIARY);
            }
            .width('100%').margin({ bottom: 12 });

            // ── 位置 + 围栏 ──
            Row({ space: 12 }) {
              Column() {
                Row() {
                  Image($rawfile('image/ic_gps.svg')).width(16).height(16).fillColor(Theme.INFO);
                  Text('GPS 位置').fontSize(12).fontColor(Theme.TEXT_TERTIARY).margin({ left: 5 });
                }
                .width('100%');
                Text(this.gpsLat > 0 ? this.gpsLat.toFixed(4) + ', ' + this.gpsLon.toFixed(4) : '等待定位')
                  .fontSize(13).fontColor(Theme.TEXT_PRIMARY).margin({ top: 6 }).width('100%');
              }
              .layoutWeight(1).padding(14).backgroundColor(Theme.CARD)
              .borderRadius(Theme.RADIUS_LG)
              .shadow({ radius: 8, color: '#0A000000', offsetX: 0, offsetY: 2 });

              Column() {
                Row() {
                  Image($rawfile('image/ic_fence.svg')).width(16).height(16)
                    .fillColor(this.geofenceStatus === 1 ? Theme.DANGER : Theme.SUCCESS);
                  Text('围栏').fontSize(12).fontColor(Theme.TEXT_TERTIARY).margin({ left: 5 });
                }
                .width('100%');
                Text(this.geofenceStatus === 1 ? '⚠ 越界' : '✓ 在家')
                  .fontSize(16).fontWeight(FontWeight.Medium)
                  .fontColor(this.geofenceStatus === 1 ? Theme.DANGER : Theme.SUCCESS)
                  .margin({ top: 6 }).width('100%');
              }
              .width(120).padding(14).backgroundColor(Theme.CARD)
              .borderRadius(Theme.RADIUS_LG)
              .shadow({ radius: 8, color: '#0A000000', offsetX: 0, offsetY: 2 });
            }
            .width('100%').margin({ bottom: 12 });

            // ── 食盆数据 ──
            if (this.foodWeight > 0) {
              Row({ space: 12 }) {
                this.MetricCard($rawfile('image/ic_food.svg'), '#8D6E63',
                  '食盆余量', this.foodWeight.toFixed(0), 'g', '实时称重', Theme.TEXT_TERTIARY);
                this.MetricCard($rawfile('image/ic_feed_manual.svg'), Theme.WARNING,
                  '今日已食', this.foodEaten.toFixed(0), 'g', '累计进食', Theme.TEXT_TERTIARY);
              }
              .width('100%').margin({ bottom: 12 });
            }

            // ── 最近叫声意图 ──
            if (lastVoiceIntent.length > 0) {
              Row() {
                Image($rawfile('image/ic_sound.svg')).width(20).height(20).fillColor(Theme.PRIMARY);
                Column() {
                  Text('最近叫声').fontSize(11).fontColor(Theme.TEXT_TERTIARY);
                  Text(lastVoiceIntent === 'hungry' ? '饥饿讨食' :
                       lastVoiceIntent === 'warning' ? '警告吠叫' :
                       lastVoiceIntent === 'lonely' ? '委屈孤独' :
                       lastVoiceIntent === 'happy' ? '开心' : lastVoiceIntent)
                    .fontSize(15).fontWeight(FontWeight.Medium).fontColor(Theme.TEXT_PRIMARY)
                    .margin({ top: 1 });
                }
                .margin({ left: 10 }).alignItems(HorizontalAlign.Start).layoutWeight(1);
              }
              .width('100%').padding(14).backgroundColor(Theme.PRIMARY_SOFT)
              .borderRadius(Theme.RADIUS_LG).margin({ bottom: 14 });
            }

            // ── 操作按钮：设为家 + 刷新 ──
            Row({ space: 12 }) {
              Button() {
                Row() {
                  Image($rawfile('image/ic_fence.svg')).width(16).height(16).fillColor(Theme.TEXT_WHITE);
                  Text('设为家').fontSize(14).fontColor(Theme.TEXT_WHITE).margin({ left: 6 });
                }
              }
              .layoutWeight(1).height(46).backgroundColor(Theme.PRIMARY)
              .borderRadius(Theme.RADIUS_PILL)
              .onClick(() => {
                if (!getConnectionStatus()) {
                  promptAction.showToast({ message: 'MQTT未连接，无法发送指令', duration: 2000 });
                  return;
                }
                sendSetHomeCommand();
                promptAction.showToast({ message: '已发送设置围栏指令', duration: 1500 });
              });

              Button() {
                Row() {
                  Image($rawfile('image/ic_refresh.svg')).width(16).height(16).fillColor(Theme.PRIMARY);
                  Text('刷新数据').fontSize(14).fontColor(Theme.PRIMARY).margin({ left: 6 });
                }
              }
              .layoutWeight(1).height(46).backgroundColor(Theme.CARD)
              .borderRadius(Theme.RADIUS_PILL)
              .onClick(() => {
                if (!getConnectionStatus()) {
                  promptAction.showToast({ message: 'MQTT未连接，无法刷新', duration: 2000 });
                  return;
                }
                sendRefreshCommand();
                promptAction.showToast({ message: '已发送刷新指令', duration: 1500 });
                setTimeout(() => { this.refreshData(); }, 2000);
              });
            }
            .width('100%').margin({ bottom: 14 });

            // ── 快捷导航 4 格 ──
            Row({ space: 12 }) {
              this.NavCard($rawfile('image/tab_dashboard.svg'), '数据看板', Theme.INFO,
                () => { this.switchTab(4); });
              this.NavCard($rawfile('image/tab_comfort.svg'), '一键安抚', '#9C27B0',
                () => { this.switchTab(1); });
              this.NavCard($rawfile('image/tab_feeding.svg'), '投喂', Theme.WARNING,
                () => { this.switchTab(2); });
              this.NavCard($rawfile('image/tab_pet.svg'), '萌宠', Theme.PRIMARY,
                () => { this.switchTab(5); });
            }
            .width('100%').margin({ bottom: 12 });

            // 历史记录
            Row() {
              this.NavCard($rawfile('image/ic_schedule.svg'), '历史记录', '#607D8B',
                () => { router.pushUrl({ url: 'pages/HistoryPage' }); });
            }
            .width('100%').margin({ bottom: 20 });
          }
          .width('100%').padding({ left: 16, right: 16 });
        }
        .width('100%').layoutWeight(1).scrollBar(BarState.Off).scrollable(ScrollDirection.Vertical);
      }
    }
    .width('100%').height('100%').backgroundColor(Theme.BG);
  }
}
