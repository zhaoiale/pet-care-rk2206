// DashboardPage.ets — 数据看板：7天统计 + 趋势图 + 安抚记录 + 围栏
import router from '@ohos.router';
import { SensorRecord } from '../model/SensorRecord';
import { queryRecords, getRecordCount } from '../database/DatabaseService';
import { sendGetPathCommand, gpsPathPoints, gpsPathVersion, clearGpsPathPoints, lastGeofenceStatus, lastGpsLat, lastGpsLon, lastHomeLat, lastHomeLon, lastVoiceIntent, lastAiInterpretation, getConnectionStatus } from '../services/MqttService';
import { promptAction } from '@kit.ArkUI';
import { Theme } from '../common/Theme';

const DATA_UPDATE_KEY: string = 'dataUpdateKey';

interface DayStats {
  day: number;
  label: string;
  avgAnxiety: number;
  avgHeart: number;
  avgSpo2: number;
  comfortCount: number;
}

interface FilterItem { t: number; l: string; }
const filterItemList: FilterItem[] = [
  { t: 0, l: '全部' }, { t: 1, l: '灯光安抚' }, { t: 2, l: '语音安抚' }
];

@Entry
@Component
export struct DashboardPage {
  @State records: SensorRecord[] = [];
  @State totalCount: number = 0;
  @State isLoading: boolean = false;
  @State lastUpdateTime: string = '--';
  @State comfortFilter: number = 0;
  @State avgAnxiety: number = 0;
  @State comfortTotal: number = 0;
  @State maxAnxiety: number = 0;
  @State coveredDays: number = 0;
  @State weekStats: DayStats[] = [];
  @State avgHeart: number = 0;
  @State avgSpo2: number = 0;
  @State avgHealthScore: number = 0;
  @State geoStatus: number = 0;
  @State voiceIntentText: string = '--';
  @State aiInterpretation: string = '';
  @State gpsText: string = '--';
  @State pathCount: number = 0;
  @State pathVersion: number = 0;
  @State homeLat: number = 0;
  @State homeLon: number = 0;
  private trajSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private trajCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.trajSettings);
  private chartSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private chartCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.chartSettings);
  private timerId: number = -1;
  @State chartMetric: number = 0;  // 0=焦虑, 1=心率

  @Watch('onDataUpdate')
  @StorageLink(DATA_UPDATE_KEY) dataUpdateKey: number = 0;

  aboutToAppear() {
    this.loadData();
    this.timerId = setInterval(() => { this.loadData(); }, 5000);
  }

  aboutToDisappear() {
    if (this.timerId !== -1) { clearInterval(this.timerId); this.timerId = -1; }
  }

  onPageShow() {
    this.loadData();
  }

  onDataUpdate() {
    this.loadData();
  }

  async loadData() {
    this.isLoading = true;
    try {
      const newRecords: SensorRecord[] = await queryRecords(7);
      this.totalCount = await getRecordCount();
      this.lastUpdateTime = new Date().toLocaleTimeString();
      this.records = [...newRecords];
      this.computeStats(newRecords);
      this.computeWeekStats(newRecords);
      this.geoStatus = lastGeofenceStatus;
      this.gpsText = lastGpsLat > 0
        ? lastGpsLat.toFixed(4) + ', ' + lastGpsLon.toFixed(4)
        : '等待定位';
      this.voiceIntentText = lastVoiceIntent || '--';
      this.aiInterpretation = lastAiInterpretation || '';
      this.pathCount = gpsPathPoints.length;
      this.pathVersion = gpsPathVersion;
      this.homeLat = lastHomeLat;
      this.homeLon = lastHomeLon;
      if (this.trajCtx && this.pathCount > 0) {
        this.drawTrajectory();
      }
      if (this.chartCtx) {
        this.drawBarChart();
      }
    } catch (_err) {
      console.error('[Dashboard] loadData error');
    }
    this.isLoading = false;
  }

  computeStats(records: SensorRecord[]): void {
    console.info('[Dashboard] computeStats called, records.length=' + records.length.toString());
    if (records.length === 0) {
      this.avgAnxiety = 0; this.comfortTotal = 0; this.maxAnxiety = 0;
      this.coveredDays = 0; this.avgHeart = 0; this.avgSpo2 = 0; this.avgHealthScore = 0;
      console.info('[Dashboard] computeStats: no records, all set to 0');
      return;
    }
    let sumA: number = 0; let sumH: number = 0; let sumS: number = 0; let sumHS: number = 0;
    let max: number = 0; let comfortCount: number = 0;
    let hCount: number = 0; let sCount: number = 0;
    const days: Set<number> = new Set<number>();
    for (const r of records) {
      sumA += r.anxietyLevel;
      if (r.anxietyLevel > max) max = r.anxietyLevel;
      if (r.comfortType > 0) comfortCount++;
      if (r.heartRate > 0) { sumH += r.heartRate; hCount++; }
      if (r.spo2 > 0) { sumS += r.spo2; sCount++; }
      if (r.healthScore > 0) sumHS += r.healthScore;
      days.add(new Date(r.timestamp).getDate());
    }
    this.avgAnxiety = Math.round(sumA / records.length);
    this.maxAnxiety = max;
    this.comfortTotal = comfortCount;
    this.coveredDays = days.size;
    this.avgHeart = hCount > 0 ? Math.round(sumH / hCount) : 0;
    this.avgSpo2 = sCount > 0 ? Math.round(sumS / sCount) : 0;
    this.avgHealthScore = Math.round(sumHS / records.length);
    console.info('[Dashboard] computeStats result: avgA=' + this.avgAnxiety.toString() +
      ' days=' + this.coveredDays.toString() +
      ' comfort=' + this.comfortTotal.toString() +
      ' total=' + this.totalCount.toString());
  }

  computeWeekStats(records: SensorRecord[]): void {
    const dayMap: Map<number, SensorRecord[]> = new Map<number, SensorRecord[]>();
    for (const r of records) {
      const day: number = new Date(r.timestamp).getDay();
      if (!dayMap.has(day)) dayMap.set(day, []);
      const arr: SensorRecord[] = dayMap.get(day)!;
      arr.push(r);
    }
    const labels: string[] = ['日', '一', '二', '三', '四', '五', '六'];
    const stats: DayStats[] = [];
    for (let d: number = 0; d < 7; d++) {
      const dayRecords: SensorRecord[] = dayMap.get(d) || [];
      if (dayRecords.length > 0) {
        let sumA: number = 0; let sumH: number = 0; let sumS: number = 0;
        let hc: number = 0; let sc: number = 0; let comfort: number = 0;
        for (const r of dayRecords) {
          sumA += r.anxietyLevel;
          if (r.comfortType > 0) comfort++;
          if (r.heartRate > 0) { sumH += r.heartRate; hc++; }
          if (r.spo2 > 0) { sumS += r.spo2; sc++; }
        }
        const s: DayStats = {
          day: d, label: labels[d],
          avgAnxiety: Math.round(sumA / dayRecords.length),
          avgHeart: hc > 0 ? Math.round(sumH / hc) : 0,
          avgSpo2: sc > 0 ? Math.round(sumS / sc) : 0,
          comfortCount: comfort
        };
        stats.push(s);
      } else {
        const s: DayStats = {
          day: d, label: labels[d],
          avgAnxiety: 0, avgHeart: 0, avgSpo2: 0, comfortCount: 0
        };
        stats.push(s);
      }
    }
    this.weekStats = stats;
  }

  getFilteredRecords(): SensorRecord[] {
    if (this.comfortFilter === 0) {
      return this.records.filter((r: SensorRecord): boolean => r.comfortType > 0);
    }
    if (this.comfortFilter === 2) {
      // 语音安抚: 包含新 type=2 和旧 type=3 (白噪音)
      return this.records.filter((r: SensorRecord): boolean =>
        r.comfortType === 2 || r.comfortType === 3);
    }
    return this.records.filter((r: SensorRecord): boolean => r.comfortType === this.comfortFilter);
  }

  comfortLabel(type: number, audioSubType: number = 0): string {
    switch (type) {
      case 1: return '灯光安抚';
      case 2:
        switch (audioSubType) {
          case 1: return '语音安抚-白噪音';
          case 2: return '语音安抚-宠物叫声';
          case 3: return '语音安抚(旧)';
          default: return '语音安抚';
        }
      case 3: return '语音安抚(旧)';
      default: return '--';
    }
  }

  comfortColor(type: number): string {
    switch (type) { case 1: return '#FF9800'; case 2: return '#9C27B0'; case 3: return '#2196F3'; default: return '#999'; }
  }

  emojiByIntent(intent: string): string {
    if (intent.includes('饿') || intent.includes('吃') || intent.includes('饭')) return '🍖';
    if (intent.includes('渴') || intent.includes('水')) return '💧';
    if (intent.includes('叫') || intent.includes('喵') || intent.includes('汪')) return '🐱';
    if (intent.includes('开心') || intent.includes('高兴')) return '😊';
    if (intent.includes('悲伤') || intent.includes('难过')) return '😢';
    if (intent.includes('生气') || intent.includes('凶')) return '😠';
    if (intent.includes('害怕') || intent.includes('紧张')) return '😨';
    if (intent.includes('困') || intent.includes('睡')) return '😴';
    if (intent.includes('玩') || intent.includes('跑')) return '🎾';
    return '🐾';
  }

  drawTrajectory(): void {
    const ctx: CanvasRenderingContext2D = this.trajCtx;
    const w: number = ctx.width;
    const h: number = ctx.height;
    const pad: number = 30;

    ctx.clearRect(0, 0, w, h);

    // 收集所有点 + home 来确定坐标范围
    const pts = gpsPathPoints;
    if (pts.length === 0) return;

    let minLat: number = pts[0].lat;
    let maxLat: number = pts[0].lat;
    let minLon: number = pts[0].lon;
    let maxLon: number = pts[0].lon;

    for (const p of pts) {
      if (p.lat < minLat) minLat = p.lat;
      if (p.lat > maxLat) maxLat = p.lat;
      if (p.lon < minLon) minLon = p.lon;
      if (p.lon > maxLon) maxLon = p.lon;
    }

    if (this.homeLat > 0) {
      if (this.homeLat < minLat) minLat = this.homeLat;
      if (this.homeLat > maxLat) maxLat = this.homeLat;
      if (this.homeLon < minLon) minLon = this.homeLon;
      if (this.homeLon > maxLon) maxLon = this.homeLon;
    }

    // 防止单点导致除零
    const rangeLat: number = (maxLat - minLat) || 0.0001;
    const rangeLon: number = (maxLon - minLon) || 0.0001;

    const toX = (lon: number): number =>
      pad + ((lon - minLon) / rangeLon) * (w - pad * 2);
    const toY = (lat: number): number =>
      pad + ((maxLat - lat) / rangeLat) * (h - pad * 2);

    // 画围栏圈 (如果有home)
    if (this.homeLat > 0) {
      const homeX: number = toX(this.homeLon);
      const homeY: number = toY(this.homeLat);
      const radiusPx: number = Math.max(15,
        (0.001 * (w - pad * 2)) / rangeLon); // ~100m ≈ 0.001°

      ctx.beginPath();
      ctx.arc(homeX, homeY, radiusPx, 0, Math.PI * 2);
      ctx.strokeStyle = '#4CAF50';
      ctx.lineWidth = 1.5;
      ctx.setLineDash([4, 3]);
      ctx.stroke();
      ctx.setLineDash([]);

      // 家标记
      ctx.beginPath();
      ctx.arc(homeX, homeY, 6, 0, Math.PI * 2);
      ctx.fillStyle = '#FF5722';
      ctx.fill();
      ctx.strokeStyle = '#FFF';
      ctx.lineWidth = 2;
      ctx.stroke();
    }

    // 画轨迹线
    if (pts.length >= 2) {
      ctx.beginPath();
      ctx.moveTo(toX(pts[0].lon), toY(pts[0].lat));
      for (let i: number = 1; i < pts.length; i++) {
        ctx.lineTo(toX(pts[i].lon), toY(pts[i].lat));
      }
      ctx.strokeStyle = '#2196F3';
      ctx.lineWidth = 2.5;
      ctx.lineCap = 'round';
      ctx.lineJoin = 'round';
      ctx.stroke();
    }

    // 画GPS点
    for (const p of pts) {
      const px: number = toX(p.lon);
      const py: number = toY(p.lat);
      ctx.beginPath();
      ctx.arc(px, py, 3, 0, Math.PI * 2);
      ctx.fillStyle = '#2196F3';
      ctx.fill();
    }
  }

  drawBarChart(): void {
    const ctx: CanvasRenderingContext2D = this.chartCtx;
    const w: number = ctx.width;
    const h: number = ctx.height;
    if (w <= 0 || h <= 0) return;

    ctx.clearRect(0, 0, w, h);
    const stats: DayStats[] = this.weekStats;
    if (stats.length === 0) return;

    const isHeart: boolean = this.chartMetric === 1;
    const values: number[] = stats.map((s: DayStats): number =>
      isHeart ? s.avgHeart : s.avgAnxiety);
    const maxVal: number = Math.max(isHeart ? 50 : 10, ...values);
    const barW: number = (w - 60) / 7 - 6;
    if (barW < 6) return;

    const labels: string[] = ['日', '一', '二', '三', '四', '五', '六'];

    for (let i: number = 0; i < 7; i++) {
      const val: number = values[i];
      const barH: number = Math.max(2, (val / maxVal) * (h - 30));
      const x: number = 30 + i * ((w - 60) / 7) + 3;
      const y: number = h - 14 - barH;

      let color: string;
      if (isHeart) {
        color = val >= 100 ? '#E91E63' : val >= 80 ? '#FF9800' : '#4CAF50';
      } else {
        color = val >= 50 ? '#FF5722' : val >= 30 ? '#FF9800' : '#4CAF50';
      }
      ctx.fillStyle = val > 0 ? color : '#E0E0E0';
      ctx.fillRect(x, y, barW, barH);

      if (val > 0) {
        ctx.fillStyle = '#333';
        ctx.font = '9px sans-serif';
        ctx.textAlign = 'center';
        ctx.fillText(val.toString(), x + barW / 2, y - 3);
      }

      ctx.fillStyle = '#999';
      ctx.font = '10px sans-serif';
      ctx.textAlign = 'center';
      ctx.fillText(labels[i], x + barW / 2, h - 2);
    }
  }

  build() {
    Column() {
    Scroll() {
      Column() {
        Row() {
          Image($rawfile('image/ic_back.svg'))
            .width(22).height(22).fillColor(Theme.TEXT_PRIMARY)
            .onClick(() => { router.back(); })
          Blank()
          Text('数据看板')
            .fontSize(19).fontWeight(FontWeight.Bold).fontColor(Theme.TEXT_PRIMARY)
          Blank()
          Column() {
            Text('共' + this.totalCount.toString() + '条')
              .fontSize(12).fontColor(Theme.TEXT_TERTIARY)
            Text('更新于 ' + this.lastUpdateTime)
              .fontSize(10).fontColor(Theme.TEXT_TERTIARY)
          }.alignItems(HorizontalAlign.End)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 14, bottom: 10 })

        Text('7天概览')
          .fontSize(16).fontWeight(FontWeight.Medium).fontColor('#333')
          .width('100%').margin({ bottom: 4 }).padding({ left: 15, right: 15 })

        Row() {
          Text('情绪')
            .fontSize(12)
            .fontColor(this.chartMetric === 0 ? '#FFF' : '#666')
            .backgroundColor(this.chartMetric === 0 ? '#FF5722' : '#E0E0E0')
            .borderRadius(10)
            .padding({ left: 10, right: 10, top: 3, bottom: 3 })
            .onClick(() => { this.chartMetric = 0; this.drawBarChart(); })
          Text('心率')
            .fontSize(12)
            .fontColor(this.chartMetric === 1 ? '#FFF' : '#666')
            .backgroundColor(this.chartMetric === 1 ? '#E91E63' : '#E0E0E0')
            .borderRadius(10)
            .padding({ left: 10, right: 10, top: 3, bottom: 3 })
            .margin({ left: 6 })
            .onClick(() => { this.chartMetric = 1; this.drawBarChart(); })
        }
        .width('100%').padding({ left: 15, right: 15 }).margin({ bottom: 6 })

        Canvas(this.chartCtx)
          .width('100%')
          .height(160)
          .backgroundColor('#FAFAFA')
          .borderRadius(8)
          .margin({ left: 15, right: 15, bottom: 8 })
          .onReady(() => { this.drawBarChart(); })

        Row() {
          Column() {
            Text('情绪均值').fontSize(11).fontColor('#999')
            Row() {
              Text(this.avgAnxiety.toString()).fontSize(22).fontWeight(FontWeight.Bold).fontColor('#FF5722')
            }.margin({ top: 2 })
          }
          .width('23%').padding({ top: 10, bottom: 10, left: 6, right: 6 })
          .backgroundColor('#FFF').borderRadius(8)

          Column() {
            Text('平均心率').fontSize(11).fontColor('#999')
            Row() {
              Text(this.avgHeart.toString()).fontSize(22).fontWeight(FontWeight.Bold).fontColor('#E91E63')
              Text('bpm').fontSize(12).fontColor('#999').margin({ left: 2 })
            }.margin({ top: 2 })
          }
          .width('23%').padding({ top: 10, bottom: 10, left: 6, right: 6 })
          .backgroundColor('#FFF').borderRadius(8)

          Column() {
            Text('平均血氧').fontSize(11).fontColor('#999')
            Row() {
              Text(this.avgSpo2.toString()).fontSize(22).fontWeight(FontWeight.Bold).fontColor('#4CAF50')
              Text('%').fontSize(12).fontColor('#999').margin({ left: 2 })
            }.margin({ top: 2 })
          }
          .width('23%').padding({ top: 10, bottom: 10, left: 6, right: 6 })
          .backgroundColor('#FFF').borderRadius(8)

          Column() {
            Text('平均健康评分').fontSize(11).fontColor('#999')
            Row() {
              Text(this.avgHealthScore.toString()).fontSize(22).fontWeight(FontWeight.Bold)
                .fontColor(this.avgHealthScore >= 90 ? '#4CAF50' : this.avgHealthScore >= 70 ? '#FF9800' : '#F44336')
              Text('分').fontSize(12).fontColor('#999').margin({ left: 2 })
            }.margin({ top: 2 })
          }
          .width('23%').padding({ top: 10, bottom: 10, left: 6, right: 6 })
          .backgroundColor('#FFF').borderRadius(8)
        }
        .width('100%').justifyContent(FlexAlign.SpaceBetween)
        .padding({ left: 15, right: 15 }).margin({ bottom: 6 })

        Row() {
          Column() {
            Text('安抚次数').fontSize(11).fontColor('#999')
            Row() {
              Text(this.comfortTotal.toString()).fontSize(22).fontWeight(FontWeight.Bold).fontColor('#9C27B0')
              Text('次').fontSize(12).fontColor('#999').margin({ left: 2 })
            }.margin({ top: 2 })
          }
          .width('31%').padding({ top: 10, bottom: 10, left: 6, right: 6 })
          .backgroundColor('#FFF').borderRadius(8)

          Column() {
            Text('覆盖天数').fontSize(11).fontColor('#999')
            Row() {
              Text(this.coveredDays.toString()).fontSize(22).fontWeight(FontWeight.Bold).fontColor('#2196F3')
              Text('天').fontSize(12).fontColor('#999').margin({ left: 2 })
            }.margin({ top: 2 })
          }
          .width('31%').padding({ top: 10, bottom: 10, left: 6, right: 6 })
          .backgroundColor('#FFF').borderRadius(8)

          Column() {
            Text('数据总量').fontSize(11).fontColor('#999')
            Row() {
              Text(this.totalCount.toString()).fontSize(22).fontWeight(FontWeight.Bold).fontColor('#FF9800')
              Text('条').fontSize(12).fontColor('#999').margin({ left: 2 })
            }.margin({ top: 2 })
          }
          .width('31%').padding({ top: 10, bottom: 10, left: 6, right: 6 })
          .backgroundColor('#FFF').borderRadius(8)
        }
        .width('100%').justifyContent(FlexAlign.SpaceBetween)
        .padding({ left: 15, right: 15 }).margin({ bottom: 6 })

        // 围栏 & GPS
        Row() {
          Column() {
            Text('当前位置')
              .fontSize(11).fontColor('#999')
            Text(this.gpsText)
              .fontSize(12).fontColor('#333').margin({ top: 3 })
          }
          .width('42%').padding(10).backgroundColor('#FFF').borderRadius(8)

          Column() {
            Text('围栏状态')
              .fontSize(11).fontColor('#999')
            Text(this.geoStatus === 1 ? '⚠ 越界' : '✓ 在家')
              .fontSize(16).fontWeight(FontWeight.Bold)
              .fontColor(this.geoStatus === 1 ? '#FF0000' : '#4CAF50')
              .margin({ top: 3 })
          }
          .width('25%').padding(10).backgroundColor('#FFF').borderRadius(8)

          Column() {
            Text('离线路径')
              .fontSize(11).fontColor('#999')
            Text(this.pathCount.toString() + '点')
              .fontSize(16).fontWeight(FontWeight.Bold)
              .fontColor('#2196F3').margin({ top: 3 })
          }
          .width('22%').padding(10).backgroundColor('#FFF').borderRadius(8)
        }
        .width('100%').justifyContent(FlexAlign.SpaceBetween)
        .padding({ left: 15, right: 15 }).margin({ bottom: 6 })

        Row() {
          Column() {
            Text('叫声意图')
              .fontSize(11).fontColor('#999')
            Text(`叫声: ${this.voiceIntentText} ${this.emojiByIntent(this.voiceIntentText)}`)
              .fontSize(14).fontColor('#333').margin({ top: 3 })
          }
          .width('100%').padding(10).backgroundColor('#FFF').borderRadius(8)
        }
        .width('100%').padding({ left: 15, right: 15 }).margin({ bottom: 6 })

        if (this.aiInterpretation.length > 0) {
          Row() {
            Column() {
              Row() {
                Text('AI 解读')
                  .fontSize(11).fontColor('#6C47FF')
                  .fontWeight(FontWeight.Medium)
                Text(' DeepSeek')
                  .fontSize(9).fontColor('#6C47FF')
                  .opacity(0.6)
                  .margin({ left: 4 })
              }
              .margin({ bottom: 4 })
              Text(this.aiInterpretation)
                .fontSize(13).fontColor('#333')
                .lineHeight(20)
                .maxLines(3)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .width('100%').padding(12)
            .backgroundColor('#F5F0FF').borderRadius(8)
          }
          .width('100%').padding({ left: 15, right: 15 }).margin({ bottom: 6 })
        }

        Row() {
          Button('获取离线路径')
            .fontSize(12).height(32)
            .backgroundColor('#2196F3').borderRadius(16)
            .onClick(() => {
              if (!getConnectionStatus()) {
                promptAction.showToast({ message: 'MQTT未连接，无法获取路径', duration: 2000 });
                return;
              }
              this.pathCount = 0;
              clearGpsPathPoints();
              sendGetPathCommand();
              promptAction.showToast({ message: '已发送获取路径指令，等待硬件上传...', duration: 2000 });
            })
          Blank()
          Text(this.pathCount > 0
            ? '最近 ' + this.pathCount.toString() + ' 个GPS点'
            : '点击获取')
            .fontSize(11).fontColor('#999')
        }
        .width('100%').padding({ left: 15, right: 15 }).margin({ bottom: 10 })

        // GPS轨迹图
        if (this.pathCount > 0) {
          Column() {
            Canvas(this.trajCtx)
              .width('100%')
              .height(220)
              .backgroundColor('#FAFAFA')
              .borderRadius(8)
              .onReady(() => {
                this.drawTrajectory();
              })
            Row() {
              Circle({ width: 8, height: 8 }).fill('#2196F3')
              Text('GPS轨迹').fontSize(10).fontColor('#666').margin({ left: 4, right: 12 })
              Circle({ width: 8, height: 8 }).fill('#FF5722')
              Text('家').fontSize(10).fontColor('#666').margin({ left: 4, right: 12 })
              Circle({ width: 8, height: 8 }).fill('#4CAF50')
              Text('围栏').fontSize(10).fontColor('#666').margin({ left: 4 })
            }
            .width('100%').justifyContent(FlexAlign.Center).margin({ top: 6 })
          }
          .width('100%').padding({ left: 15, right: 15 }).margin({ bottom: 15 })
        }

        // 历史传感器记录
        Row() {
          Text('历史记录')
            .fontSize(16).fontWeight(FontWeight.Medium).fontColor('#333')
          Blank()
          Text(this.records.length.toString() + '条')
            .fontSize(12).fontColor('#999')
        }
        .width('100%').padding({ left: 15, right: 15 }).margin({ top: 15, bottom: 8 })

        if (this.records.length === 0) {
          Text('暂无历史记录')
            .fontSize(14).fontColor('#CCC')
            .width('100%').textAlign(TextAlign.Center).margin({ top: 20 })
        } else {
          Column() {
            ForEach(this.records.slice(0, 30), (record: SensorRecord, index: number) => {
              Row() {
                Column() {
                  Text(new Date(record.timestamp).toLocaleString())
                    .fontSize(12).fontColor('#666')
                  Row() {
                    Text('焦虑:' + record.anxietyLevel.toString())
                      .fontSize(11).fontColor('#FF5722').margin({ right: 8 })
                    Text('HR:' + record.heartRate.toString())
                      .fontSize(11).fontColor('#E91E63').margin({ right: 8 })
                    Text('SpO2:' + record.spo2.toString() + '%')
                      .fontSize(11).fontColor('#4CAF50')
                  }
                  .margin({ top: 3 })
                }
                .alignItems(HorizontalAlign.Start)
                Blank()
                Column() {
                  Text(record.emotion === 'HAPPY' ? '高兴' :
                       record.emotion === 'CALM' ? '平静' :
                       record.emotion === 'ALERT' ? '警觉' :
                       record.emotion === 'ANXIOUS' ? '焦虑' : '--')
                    .fontSize(12).fontWeight(FontWeight.Medium)
                    .fontColor(record.emotion === 'HAPPY' ? '#4CAF50' :
                               record.emotion === 'CALM' ? '#2196F3' :
                               record.emotion === 'ALERT' ? '#FF9800' :
                               record.emotion === 'ANXIOUS' ? '#FF5722' : '#999')
                  Text('健康:' + record.healthScore.toString())
                    .fontSize(11).fontColor('#999').margin({ top: 2 })
                }
                .alignItems(HorizontalAlign.End)
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 10, bottom: 10 })
              .backgroundColor('#FFF').borderRadius(8).margin({ bottom: 6 })
            })
          }.width('100%').padding({ left: 15, right: 15 })
        }

        // 安抚记录
        Row() {
          Text('安抚记录')
            .fontSize(16).fontWeight(FontWeight.Medium).fontColor('#333')
          Blank()
          Text(this.getFilteredRecords().length.toString() + '条')
            .fontSize(12).fontColor('#999')
        }
        .width('100%').padding({ left: 15, right: 15 }).margin({ top: 20, bottom: 8 })

        Row() {
          ForEach(filterItemList, (item: FilterItem) => {
            Text(item.l)
              .fontSize(13)
              .fontColor(this.comfortFilter === item.t ? '#FFF' : '#666')
              .backgroundColor(this.comfortFilter === item.t ? '#2196F3' : '#E0E0E0')
              .borderRadius(14)
              .padding({ left: 12, right: 12, top: 5, bottom: 5 })
              .margin({ right: 8 })
              .onClick(() => { this.comfortFilter = item.t; })
          })
        }
        .width('100%').padding({ left: 15, right: 15 }).margin({ bottom: 10 })

        if (this.getFilteredRecords().length === 0) {
          Text('暂无安抚记录')
            .fontSize(14).fontColor('#CCC')
            .width('100%').textAlign(TextAlign.Center).margin({ top: 30 })
        } else {
          Column() {
            ForEach(this.getFilteredRecords(), (record: SensorRecord, index: number) => {
              Row() {
                Column() {
                  Text(new Date(record.timestamp).toLocaleString())
                    .fontSize(12).fontColor('#666')
                  Text('情绪: ' + record.anxietyLevel.toString() + ' 心率: ' + record.heartRate.toString())
                    .fontSize(11).fontColor('#999').margin({ top: 2 })
                }
                .alignItems(HorizontalAlign.Start)
                Blank()
                Text(this.comfortLabel(record.comfortType, record.audioSubType))
                  .fontSize(13).fontWeight(FontWeight.Medium)
                  .fontColor('#FFF')
                  .backgroundColor(this.comfortColor(record.comfortType))
                  .borderRadius(10)
                  .padding({ left: 10, right: 10, top: 3, bottom: 3 })
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 10, bottom: 10 })
              .backgroundColor('#FFF').borderRadius(8).margin({ bottom: 6 })
            })
          }.width('100%').padding({ left: 15, right: 15 })
        }
      }
      .width('100%').padding({ bottom: 20 })
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.On)
    .scrollable(ScrollDirection.Vertical)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.BG)
  }

}
