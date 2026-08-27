// HomePage.ets
import router from '@ohos.router';
import { getLatestRecord, queryRecords, getRecordCount, insertSensorRecord } from '../database/DatabaseService';
import { getConnectionStatus, sendRefreshCommand, sendSetHomeCommand } from '../services/MqttService';
import { SensorRecord } from '../model/SensorRecord';
import { lastGeofenceStatus, lastGpsLat, lastGpsLon, lastVoiceIntent, lastEmotion, lastAnxiety } from '../services/MqttService';
import { promptAction } from '@kit.ArkUI';

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
    // 立即用全局默认值填充，确保任何路径下情绪都不显示 --
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
      this.mqttDotColor = '#4CAF50';
      this.statusText = 'MQTT已连接';
    } else {
      this.mqttDotColor = '#FF0000';
      this.statusText = 'MQTT断开';
    }
  }

  isRecent(timestamp: number): boolean {
    return (Date.now() - timestamp) < 300000; // 5分钟内视为实时数据
  }

  async loadRealData() {
    try {
      const latest = await getLatestRecord();
      if (latest !== null) {
        if (this.isRecent(latest.timestamp)) {
          this.applyRecord(latest);
          console.info('[HomePage] loadRealData: recent record applied');
        } else {
          // 无近期数据时回退到最新一条，避免首页全显示 --
          this.applyRecord(latest);
          this.lastUpdateTime = new Date(latest.timestamp).toLocaleTimeString() + ' (历史)';
          console.info('[HomePage] loadRealData: fallback to archived record');
        }
      } else {
        // 数据库无记录时，用 MQTT 全局默认值填充（避免全页 --）
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
        console.info('[HomePage] Refresh: HR=' + latest.heartRate.toString() +
          ' SpO2=' + latest.spo2.toString() +
          ' Geo=' + latest.geofenceStatus.toString());
      }
      // 不再覆盖 lastUpdateTime 为"等待硬件数据"，保留 loadRealData 设置的回退时间
      // Sync live MQTT globals (实时覆盖，即使传感器健康数据不全也能更新)
      this.geofenceStatus = lastGeofenceStatus;
      this.gpsLat = lastGpsLat;
      this.gpsLon = lastGpsLon;
      if (lastAnxiety > 0) {
        this.anxietyIndex = lastAnxiety;
      }
      this.emotion = lastEmotion;
      // Sync voice intent (from global variable, not in record)
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

  build() {
    Column() {
    if (this.isLoading) {
      Column() {
        LoadingProgress()
          .width(50)
          .height(50)
          .margin({ top: 200 })
        Text('加载中...')
          .fontSize(14)
          .fontColor('#999')
          .margin({ top: 12 })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    } else {
    Scroll() {
      Column() {
      // 顶部标题
      Row() {
        Text('智宠管家')
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
        Blank()
        Text('当前: ' + this.petName)
          .fontSize(14)
          .fontColor('#2196F3')
          .backgroundColor('#E3F2FD')
          .borderRadius(10)
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
      }
      .width('100%')
      .margin({ top: 30, bottom: 5 })

      Text('数据更新于 ' + this.lastUpdateTime)
        .fontSize(12)
        .fontColor('#999')
        .visibility(this.refreshCounter >= 0 ? Visibility.Visible : Visibility.Hidden)

      Row() {
        Circle({ width: 8, height: 8 })
          .fill(this.mqttDotColor)
        Text(this.statusText)
          .fontSize(11)
          .fontColor(this.mqttDotColor)
          .margin({ left: 4 })
      }
      .margin({ top: 4, bottom: 15 })

      // 核心指标卡片 - 第一排: 焦虑 + 体温
      Row() {
        Column() {
          Text('情绪指数')
            .fontSize(16)
            .fontColor('#666')
          Text(this.anxietyIndex.toString())
            .fontSize(36)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FF5722')
            .margin({ top: 5 })
          Text(this.anxietyIndex > 60 ? '偏高' : '正常')
            .fontSize(14)
            .fontColor(this.anxietyIndex > 60 ? '#FF0000' : '#00AA00')
        }
        .width('45%')
        .padding(15)
        .backgroundColor('#F5F5F5')
        .borderRadius(10)

        Column() {
          Text('体温')
            .fontSize(16)
            .fontColor('#666')
          Row() {
            Text(this.bodyTemp > 0 ? this.bodyTemp.toFixed(1) : '--')
              .fontSize(36)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.bodyTemp > 38.5 ? '#F44336' : this.bodyTemp > 37.5 ? '#FF9800' : '#4CAF50')
              .margin({ top: 5 })
            Text(this.bodyTemp > 0 ? '℃' : '')
              .fontSize(14)
              .fontColor('#999')
              .margin({ left: 2, top: 12 })
          }
          Text(this.bodyTemp > 0
            ? (this.bodyTemp > 38.5 ? '发热' : this.bodyTemp > 37.5 ? '偏高' : '正常')
            : '等待数据')
            .fontSize(14)
            .fontColor(this.bodyTemp > 38.5 ? '#F44336' : this.bodyTemp > 37.5 ? '#FF9800' : '#4CAF50')
        }
        .width('45%')
        .padding(15)
        .backgroundColor('#F5F5F5')
        .borderRadius(10)
        .margin({ left: 10 })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .margin({ bottom: 10 })

      // 第二排: 环境(温湿度) + 活动状态
      Row() {
        Column() {
          Text('环境')
            .fontSize(16)
            .fontColor('#666')
          Row() {
            Column() {
              Text(this.temperature.toFixed(1))
                .fontSize(28)
                .fontWeight(FontWeight.Bold)
                .fontColor('#FF5722')
              Text('℃')
                .fontSize(11)
                .fontColor('#999')
            }
            .alignItems(HorizontalAlign.Center)
            .margin({ right: 12 })

            Column() {
              Text(this.humidity.toFixed(1))
                .fontSize(28)
                .fontWeight(FontWeight.Bold)
                .fontColor('#2196F3')
              Text('%')
                .fontSize(11)
                .fontColor('#999')
            }
            .alignItems(HorizontalAlign.Center)
          }
          .margin({ top: 8 })
        }
        .width('45%')
        .padding(12)
        .backgroundColor('#F5F5F5')
        .borderRadius(10)

        Column() {
          Text('活动状态')
            .fontSize(16)
            .fontColor('#666')
          Text(this.activityLevel)
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor('#4CAF50')
            .margin({ top: 12 })
        }
        .width('45%')
        .padding(15)
        .backgroundColor('#F5F5F5')
        .borderRadius(10)
        .margin({ left: 10 })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)

      // 第三排: 心率 + 血氧（新增健康指标）
      Row() {
        Column() {
          Text('心率')
            .fontSize(16)
            .fontColor('#666')
          Row() {
            Text(this.heartRate.toFixed(0))
              .fontSize(36)
              .fontWeight(FontWeight.Bold)
              .fontColor('#E91E63')
            Text('bpm')
              .fontSize(12)
              .fontColor('#999')
              .margin({ left: 4 })
          }
          .margin({ top: 5 })
          Text(this.heartRate > 100 ? '偏快' : this.heartRate > 0 ? '正常' : '--')
            .fontSize(14)
            .fontColor(this.heartRate > 100 ? '#FF0000' : '#00AA00')
        }
        .width('45%')
        .padding(15)
        .backgroundColor('#F5F5F5')
        .borderRadius(10)

        Column() {
          Text('血氧')
            .fontSize(16)
            .fontColor('#666')
          Row() {
            Text(this.spo2.toFixed(0))
              .fontSize(36)
              .fontWeight(FontWeight.Bold)
              .fontColor('#4CAF50')
            Text('%')
              .fontSize(12)
              .fontColor('#999')
              .margin({ left: 4 })
          }
          .margin({ top: 5 })
          Text(this.spo2 >= 95 ? '正常' : this.spo2 > 0 ? '偏低' : '--')
            .fontSize(14)
            .fontColor(this.spo2 >= 95 ? '#00AA00' : '#FF0000')
        }
        .width('45%')
        .padding(15)
        .backgroundColor('#F5F5F5')
        .borderRadius(10)
        .margin({ left: 10 })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .margin({ top: 10 })

      // 情绪状态
      Row() {
        Column() {
          Text('情绪状态')
            .fontSize(16)
            .fontColor('#666')
          Text(this.emotion === 'HAPPY' ? '高兴' :
               this.emotion === 'CALM' ? '平静' :
               this.emotion === 'ALERT' ? '警觉' :
               this.emotion === 'ANXIOUS' ? '焦虑' : '--')
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.emotion === 'HAPPY' ? '#4CAF50' :
                       this.emotion === 'CALM' ? '#2196F3' :
                       this.emotion === 'ALERT' ? '#FF9800' :
                       this.emotion === 'ANXIOUS' ? '#FF5722' : '#999')
            .margin({ top: 8 })
          Text(this.emotion)
            .fontSize(11)
            .fontColor('#999')
            .margin({ top: 2 })
        }
        .width('100%')
        .padding(12)
        .backgroundColor('#F5F5F5')
        .borderRadius(10)
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .margin({ top: 10 })

      // 第四排: GPS 位置 + 围栏状态
      Row() {
        Column() {
          Text('GPS 位置')
            .fontSize(16)
            .fontColor('#666')
          Text(this.gpsLat > 0 ? this.gpsLat.toFixed(4) + ', ' + this.gpsLon.toFixed(4) : '等待定位')
            .fontSize(12)
            .fontColor('#333')
            .margin({ top: 8 })
        }
        .width('60%')
        .padding(12)
        .backgroundColor('#F5F5F5')
        .borderRadius(10)

        Column() {
          Text('围栏')
            .fontSize(16)
            .fontColor('#666')
          Text(this.geofenceStatus === 1 ? '⚠ 越界' : '✓ 在家')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.geofenceStatus === 1 ? '#FF0000' : '#4CAF50')
            .margin({ top: 8 })
        }
        .width('35%')
        .padding(12)
        .backgroundColor(this.geofenceStatus === 1 ? '#FFF3F3' : '#F1F8F1')
        .borderRadius(10)
        .margin({ left: 10 })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .margin({ top: 10 })

      // 食盆重量
      if (this.foodWeight > 0) {
        Row() {
          Column() {
            Text('食盆重量')
              .fontSize(14)
              .fontColor('#666')
            Text(this.foodWeight.toFixed(0))
              .fontSize(28)
              .fontWeight(FontWeight.Bold)
              .fontColor('#795548')
              .margin({ top: 5 })
            Text('g')
              .fontSize(12)
              .fontColor('#999')
          }
          .width('45%')
          .padding(12)
          .backgroundColor('#F5F5F5')
          .borderRadius(10)

          Column() {
            Text('宠物已食')
              .fontSize(14)
              .fontColor('#666')
            Text(this.foodEaten.toFixed(0))
              .fontSize(28)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FF9800')
              .margin({ top: 5 })
            Text('g')
              .fontSize(12)
              .fontColor('#999')
          }
          .width('45%')
          .padding(12)
          .backgroundColor('#F5F5F5')
          .borderRadius(10)
          .margin({ left: 10 })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .margin({ top: 10, bottom: 10 })
      }

      // 最近叫声意图
      if (lastVoiceIntent.length > 0) {
        Row() {
          Column() {
            Text('最近叫声')
              .fontSize(14)
              .fontColor('#666')
            Row() {
              Text(lastVoiceIntent === 'hungry' ? '🍖 饥饿讨食' :
                   lastVoiceIntent === 'warning' ? '⚠ 警告' :
                   lastVoiceIntent === 'lonely' ? '😢 委屈孤独' :
                   lastVoiceIntent === 'happy' ? '😊 开心' : '🐾 ' + lastVoiceIntent)
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor('#FF5722')
            }
            .margin({ top: 5 })
          }
          .width('100%')
          .padding(12)
          .backgroundColor('#FFF3E0')
          .borderRadius(10)
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .margin({ top: 10 })
      }

      // 操作按钮行: 设家 + 刷新
      Row() {
        Button('设为家')
          .width('38%')
          .height(45)
          .fontSize(15)
          .backgroundColor('#FF9800')
          .borderRadius(22)
          .onClick(() => {
            if (!getConnectionStatus()) {
              promptAction.showToast({ message: 'MQTT未连接，无法发送指令', duration: 2000 });
              return;
            }
            sendSetHomeCommand();
            promptAction.showToast({ message: '已发送设置围栏指令', duration: 1500 });
            console.info('[HomePage] Set home command sent');
          })

        Button('刷新数据')
          .width('38%')
          .height(45)
          .fontSize(15)
          .backgroundColor('#2196F3')
          .borderRadius(22)
          .margin({ left: 10 })
          .onClick(() => {
            if (!getConnectionStatus()) {
              promptAction.showToast({ message: 'MQTT未连接，无法刷新', duration: 2000 });
              return;
            }
            sendRefreshCommand();
            promptAction.showToast({ message: '已发送刷新指令', duration: 1500 });
            setTimeout(() => { this.refreshData(); }, 2000);
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .margin({ top: 15 })

      // 导航按钮行
      Row() {
        Button('数据看板')
          .width('30%')
          .height(45)
          .fontSize(14)
          .backgroundColor('#4CAF50')
          .borderRadius(22)
          .onClick(() => { router.pushUrl({ url: 'pages/DashboardPage' }); })

        Button('一键安抚')
          .width('30%')
          .height(45)
          .fontSize(14)
          .backgroundColor('#9C27B0')
          .borderRadius(22)
          .margin({ left: 8 })
          .onClick(() => { router.pushUrl({ url: 'pages/ComfortPage' }); })

        Button('投喂')
          .width('20%')
          .height(45)
          .fontSize(14)
          .backgroundColor('#FF5722')
          .borderRadius(22)
          .margin({ left: 8 })
          .onClick(() => { router.pushUrl({ url: 'pages/FeedingPage' }); })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .margin({ top: 10 })

      // 第二排导航
      Row() {
        Button('萌宠')
          .width('45%')
          .height(45)
          .fontSize(14)
          .backgroundColor('#FF9800')
          .borderRadius(22)
          .onClick(() => { router.pushUrl({ url: 'pages/VirtualPetPage' }); })

        Button('历史记录')
          .width('45%')
          .height(45)
          .fontSize(14)
          .backgroundColor('#607D8B')
          .borderRadius(22)
          .margin({ left: 10 })
          .onClick(() => { router.pushUrl({ url: 'pages/HistoryPage' }); })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .margin({ top: 10, bottom: 20 })
    }
    .width('100%')
    .padding({ left: 15, right: 15 })
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.On)
    .scrollable(ScrollDirection.Vertical)
    }
    }  // end else (isLoading)
    .width('100%')
    .height('100%')
  }
}
