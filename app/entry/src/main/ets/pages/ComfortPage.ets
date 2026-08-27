// ComfortPage.ets — 安抚控制页: 灯光安抚 / 语音安抚(音乐+宠物叫声)
import router from '@ohos.router';
import { sendComfortCommand, sendPetSoundCommand, getConnectionStatus } from '../services/MqttService';
import { promptAction } from '@kit.ArkUI';

@Entry
@Component
export struct ComfortPage {
  @StorageLink('anxietyIndex') anxietyIndex: number = 35;
  @StorageLink('temperature') temperature: number = 0;
  @StorageLink('humidity') humidity: number = 0;
  @StorageLink('petName') petName: string = '胖宝宝';
  @State isComforting: boolean = false;
  @State selectedTab: number = 1;         // 1=灯光安抚, 2=语音安抚
  @State selectedSpecies: string = 'cat'; // 'cat' | 'dog'
  @State statusMsg: string = '';
  @State isSending: boolean = false;

  handleLightComfort() {
    if (this.isComforting) return;
    this.isComforting = true;
    this.statusMsg = '正在发送...';

    sendComfortCommand(1).then(() => {
      this.statusMsg = '灯光安抚已开启 (呼吸暖橙光, ~30秒)';
      this.isComforting = false;
    }).catch(() => {
      this.statusMsg = '发送失败，请检查MQTT连接';
      this.isComforting = false;
    });
  }

  handleMusicComfort() {
    if (this.isComforting) return;
    if (!getConnectionStatus()) {
      promptAction.showToast({ message: 'MQTT未连接，无法发送', duration: 2000 });
      return;
    }
    this.isComforting = true;
    this.statusMsg = '正在发送...';

    sendComfortCommand(2, 1).then(() => {
      this.statusMsg = '舒缓音乐已开启 (蜂鸣器摇篮曲 + 暖光, ~20秒)';
      this.isComforting = false;
    }).catch(() => {
      this.statusMsg = '发送失败，请检查MQTT连接';
      this.isComforting = false;
    });
  }

  handlePetSound(mood: string) {
    if (this.isSending) return;
    if (!getConnectionStatus()) {
      promptAction.showToast({ message: 'MQTT未连接，无法发送', duration: 2000 });
      return;
    }
    this.isSending = true;
    this.statusMsg = '正在发送...';

    sendPetSoundCommand(this.selectedSpecies, mood).then(() => {
      const speciesLabel = this.selectedSpecies === 'dog' ? '小狗' : '小猫';
      const moodLabels: Record<string, string> = {
        'happy': speciesLabel + '开心叫声已播放',
        'play': speciesLabel + '玩耍叫声已播放',
        'calm': speciesLabel + '平静叫声已播放',
      };
      this.statusMsg = moodLabels[mood] || (this.selectedSpecies + ' ' + mood + ' 已发送');
      this.isSending = false;
    }).catch(() => {
      this.statusMsg = '发送失败，请检查MQTT连接';
      this.isSending = false;
    });
  }

  speciesLabel(): string {
    return this.selectedSpecies === 'dog' ? '小狗' : '小猫';
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        Text('< 返回')
          .fontSize(16)
          .fontColor('#2196F3')
          .onClick(() => { router.back(); })
        Blank()
        Text('安抚中心')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
        Blank()
        Text(' ')
          .fontSize(16)
      }
      .width('100%')
      .padding({ left: 15, right: 15, top: 30, bottom: 10 })

      Scroll() {
        Column() {
          // 当前状态卡片
          Column() {
            Text('当前状态')
              .fontSize(16)
              .fontColor('#666')
              .margin({ bottom: 10 })
            Row() {
              Column() {
                Text('情绪指数')
                  .fontSize(12).fontColor('#999')
                Text(this.anxietyIndex.toString())
                  .fontSize(24).fontWeight(FontWeight.Bold).fontColor('#FF5722')
              }.layoutWeight(1)

              Column() {
                Text('温度')
                  .fontSize(12).fontColor('#999')
                Text(this.temperature.toFixed(1))
                  .fontSize(24).fontWeight(FontWeight.Bold).fontColor('#FF5722')
              }.layoutWeight(1)

              Column() {
                Text('湿度')
                  .fontSize(12).fontColor('#999')
                Text(this.humidity.toFixed(1))
                  .fontSize(24).fontWeight(FontWeight.Bold).fontColor('#2196F3')
              }.layoutWeight(1)
            }
            .width('100%')
          }
          .width('85%')
          .padding(15)
          .backgroundColor('#F5F5F5')
          .borderRadius(15)
          .margin({ top: 20 })

          Text('正在陪伴 ' + this.petName)
            .fontSize(16)
            .fontColor('#666')
            .margin({ top: 20 })

          // 安抚类型 Tab (2个)
          Row() {
            Button('灯光安抚')
              .fontSize(14)
              .height(38)
              .backgroundColor(this.selectedTab === 1 ? '#FF9800' : '#E0E0E0')
              .fontColor(this.selectedTab === 1 ? '#FFF' : '#666')
              .borderRadius(19)
              .layoutWeight(1)
              .onClick(() => { this.selectedTab = 1; })
            Button('语音安抚')
              .fontSize(14)
              .height(38)
              .backgroundColor(this.selectedTab === 2 ? '#9C27B0' : '#E0E0E0')
              .fontColor(this.selectedTab === 2 ? '#FFF' : '#666')
              .borderRadius(19)
              .layoutWeight(1)
              .margin({ left: 6 })
              .onClick(() => { this.selectedTab = 2; })
          }
          .width('85%')
          .margin({ top: 25 })

          // ---- 灯光安抚 Tab ----
          if (this.selectedTab === 1) {
            Column() {
              Text('通过 RGB LED 发出暖橙色呼吸光')
                .fontSize(13).fontColor('#999')
                .margin({ top: 15, bottom: 10 })
              Button(this.isComforting ? '发送中...' : '开启呼吸灯')
                .width('100%')
                .height(48)
                .fontSize(17)
                .backgroundColor('#FF9800')
                .borderRadius(24)
                .onClick(() => { this.handleLightComfort(); })
            }
            .width('85%')
          }

          // ---- 语音安抚 Tab (合并了音乐+宠物叫声) ----
          if (this.selectedTab === 2) {
            Column() {
              // ===== 舒缓音乐 =====
              Text('舒缓音乐')
                .fontSize(17)
                .fontWeight(FontWeight.Bold)
                .fontColor('#333')
                .margin({ top: 15, bottom: 6 })
              Text('蜂鸣器播放五声音阶摇篮曲 + 暖光呼吸灯')
                .fontSize(12).fontColor('#999')
                .margin({ bottom: 10 })
              Button(this.isComforting ? '播放中...' : '播放舒缓音乐 (~20秒)')
                .width('100%')
                .height(48)
                .fontSize(16)
                .backgroundColor('#9C27B0')
                .borderRadius(24)
                .onClick(() => { this.handleMusicComfort(); })

              Text('提示：通过蜂鸣器播放摇篮曲旋律，LED 暖光呼吸灯同步')
                .fontSize(11).fontColor('#CCC')
                .margin({ top: 15 })
            }
            .width('85%')
          }

          // 状态消息
          if (this.statusMsg !== '') {
            Text(this.statusMsg)
              .fontSize(14)
              .fontColor(this.statusMsg.includes('失败') ? '#F44336' : '#4CAF50')
              .margin({ top: 20 })
              .textAlign(TextAlign.Center)
          }
        }
        .width('100%').padding({ bottom: 30 })
      }
      .width('100%').layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%').height('100%').backgroundColor('#F5F5F5')
  }
}
