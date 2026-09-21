// HistoryPage.ets — 传感器历史数据查看页面
import router from '@ohos.router';
import { SensorRecord } from '../model/SensorRecord';
import { queryRecords, getRecordCount } from '../database/DatabaseService';

const DATA_UPDATE_KEY: string = 'dataUpdateKey';

@Entry
@Component
export struct HistoryPage {
  @State records: SensorRecord[] = [];
  @State selectedDays: number = 7;
  @State totalCount: number = 0;
  @State isLoading: boolean = false;
  @State lastUpdateTime: string = '刚刚';
  @State refreshCounter: number = 0;  // 强制刷新计数器
  private timerId: number = -1;

  @Watch('onDataUpdate')
  @StorageLink(DATA_UPDATE_KEY) dataUpdateKey: number = 0;

  aboutToAppear() {
    console.info('[HistoryPage] aboutToAppear called at:', new Date().toLocaleTimeString());
    this.loadRecords();
    // 每30秒自动刷新一次
    this.startAutoRefresh();
    console.info('[HistoryPage] aboutToAppear completed');
  }

  onPageShow() {
    console.info('[HistoryPage] onPageShow called at:', new Date().toLocaleTimeString());
    this.loadRecords();
    console.info('[HistoryPage] onPageShow completed');
  }

  onDataUpdate() {
    console.info('[HistoryPage] Data update triggered by AppStorage at:', new Date().toLocaleTimeString());
    this.loadRecords();
  }

  startAutoRefresh() {
    console.info('[HistoryPage] Starting auto-refresh timer at:', new Date().toLocaleTimeString());
    this.timerId = setInterval(() => {
      const now = new Date().toLocaleTimeString();
      console.info('[HistoryPage] Auto-refresh triggered at:', now);
      this.loadRecords();
    }, 30000);
    console.info('[HistoryPage] Timer ID:', this.timerId, 'Interval: 30000ms');
  }

  async loadRecords() {
    this.isLoading = true;
    try {
      const newRecords = await queryRecords(this.selectedDays);
      this.totalCount = await getRecordCount();
      this.lastUpdateTime = new Date().toLocaleTimeString();
      
      // 强制刷新UI - 使用新建数组的方式
      this.records = [...newRecords];
      this.refreshCounter++;
      const newCounter = this.refreshCounter;
      
      // 创建临时组件来触发重新渲染
      setTimeout(() => {
        this.refreshCounter = newCounter;
      }, 10);
      
      console.info('[HistoryPage] Auto-refresh completed, records:', this.records.length, 'counter:', this.refreshCounter);
    } catch (err) {
      console.error('[HistoryPage] loadRecords error: ' + JSON.stringify(err));
    }
    this.isLoading = false;
  }

  // 数据标签 builder
  @Builder
  dataChip(label: string, value: string, color: string) {
    Row() {
      Text(label)
        .fontSize(11)
        .fontColor('#999')
      Text(value)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(color)
        .margin({ left: 3 })
    }
    .padding({ left: 8, right: 8, top: 3, bottom: 3 })
    .backgroundColor('#F5F5F5')
    .borderRadius(4)
    .margin({ right: 6 })
  }

  build() {
    Column() {
      // 顶部标题栏
      Row() {
        Text('< 返回')
          .fontSize(16)
          .fontColor('#2196F3')
          .onClick(() => {
            router.back();
          })

        Blank()

        Text('历史数据')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)

        Blank()

        Column() {
          Text('共' + this.totalCount.toString() + '条')
            .fontSize(13)
            .fontColor('#999')
          Text('更新于 ' + this.lastUpdateTime)
            .fontSize(11)
            .fontColor('#BBB')
        }
        .alignItems(HorizontalAlign.End)
      }
      .width('100%')
      .padding({ left: 15, right: 15, top: 30, bottom: 10 })

      // 时间筛选按钮组
      Row() {
        Button('今天')
          .fontSize(14)
          .type(this.selectedDays === 1 ? ButtonType.Normal : ButtonType.Capsule)
          .backgroundColor(this.selectedDays === 1 ? '#2196F3' : '#E0E0E0')
          .fontColor(this.selectedDays === 1 ? '#FFF' : '#666')
          .onClick(() => {
            this.selectedDays = 1;
            this.loadRecords();
          })

        Button('7天')
          .fontSize(14)
          .type(this.selectedDays === 7 ? ButtonType.Normal : ButtonType.Capsule)
          .backgroundColor(this.selectedDays === 7 ? '#2196F3' : '#E0E0E0')
          .fontColor(this.selectedDays === 7 ? '#FFF' : '#666')
          .margin({ left: 10 })
          .onClick(() => {
            this.selectedDays = 7;
            this.loadRecords();
          })

        Button('30天')
          .fontSize(14)
          .type(this.selectedDays === 30 ? ButtonType.Normal : ButtonType.Capsule)
          .backgroundColor(this.selectedDays === 30 ? '#2196F3' : '#E0E0E0')
          .fontColor(this.selectedDays === 30 ? '#FFF' : '#666')
          .margin({ left: 10 })
          .onClick(() => {
            this.selectedDays = 30;
            this.loadRecords();
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .margin({ bottom: 15 })

      // 数据列表 - 使用refreshCounter强制刷新
      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(40)
            .height(40)
          Text('加载中...')
            .fontSize(14)
            .visibility(this.refreshCounter >= 0 ? Visibility.Visible : Visibility.Hidden)
            .fontColor('#999')
            .margin({ top: 10 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.records.length === 0) {
        Column() {
          Text('暂无历史数据')
            .fontSize(18)
            .fontColor('#999')
          Text('等待硬件上报后自动存入')
            .fontSize(13)
            .fontColor('#CCC')
            .margin({ top: 5 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        // 使用 Stack + if 条件渲染来实现强制刷新
        Stack() {
          List() {
            ForEach(this.records, (record: SensorRecord, index: number) => {
              ListItem() {
                Column() {
                  // 时间 + 焦虑等级
                  Row() {
                    Text(new Date(record.timestamp).toLocaleString())
                      .fontSize(13)
                      .fontColor('#666')

                    Blank()

                    Text('情绪: ' + record.anxietyLevel.toString())
                      .fontSize(15)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(record.anxietyLevel >= 80 ? '#FF0000' :
                        record.anxietyLevel >= 50 ? '#FF9800' : '#4CAF50')
                  }
                  .width('100%')
                  .margin({ bottom: 6 })

                  // 传感器数据行
                  Row() {
                    this.dataChip('温度', record.temperature.toFixed(1) + '℃', '#FF5722')
                    this.dataChip('湿度', record.humidity.toFixed(1) + '%', '#2196F3')
                    this.dataChip('光照', record.illumination.toFixed(0) + 'Lx', '#FFC107')
                  }
                  .width('100%')
                  .margin({ bottom: 4 })

                  // 健康数据行
                  Row() {
                    if (record.heartRate > 0) {
                      this.dataChip('心率', record.heartRate.toString() + 'bpm', '#E91E63')
                    }
                    if (record.spo2 > 0) {
                      this.dataChip('血氧', record.spo2.toString() + '%', '#4CAF50')
                    }
                    if (record.healthScore > 0) {
                      this.dataChip('健康', record.healthScore.toString() + '分',
                        record.healthScore >= 90 ? '#4CAF50' : record.healthScore >= 70 ? '#FF9800' : '#F44336')
                    }
                    if (record.activityLevel > 0) {
                      this.dataChip('活动', record.activityLevel.toString(), '#795548')
                    }
                  }
                  .width('100%')
                  .margin({ bottom: 4 })

                  // 情绪+GPS+安抚行
                  Row() {
                    if (record.emotion && record.emotion !== 'CALM') {
                      Text(record.emotion === 'HAPPY' ? '😊高兴' :
                           record.emotion === 'ANXIOUS' ? '😰焦虑' :
                           record.emotion === 'ALERT' ? '⚠警觉' : record.emotion)
                        .fontSize(11).fontColor('#666')
                        .margin({ right: 6 })
                    }
                    if (record.gpsLat > 0) {
                      Text('📍' + record.gpsLat.toFixed(4) + ',' + record.gpsLon.toFixed(4))
                        .fontSize(10).fontColor('#999')
                        .maxLines(1)
                    }
                    Blank()
                    if (record.comfortType > 0) {
                      if (record.comfortType === 1) {
                        this.dataChip('安抚', '灯光', '#9C27B0')
                      } else if (record.comfortType === 2) {
                        this.dataChip('安抚', '蜂鸣', '#9C27B0')
                      } else {
                        this.dataChip('安抚', '灯+鸣', '#9C27B0')
                      }
                    }
                  }
                  .width('100%')
                }
                .width('100%')
                .padding(12)
                .backgroundColor('#FFF')
                .borderRadius(8)
                .margin({ bottom: 8 })
              }
            }, (record: SensorRecord): string => this.refreshCounter.toString() + '_' + record.id.toString())
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 15, right: 15 })
        }
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }
}
