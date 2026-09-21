// ComfortPage.ets — 安抚控制页（UI 优化版，逻辑不变）
import router from '@ohos.router';
import { sendComfortCommand, sendPetSoundCommand, getConnectionStatus } from '../services/MqttService';
import { promptAction } from '@kit.ArkUI';
import { Theme, anxietyColor } from '../common/Theme';

@Entry
@Component
export struct ComfortPage {
  @StorageLink('anxietyIndex') anxietyIndex: number = 35;
  @StorageLink('temperature') temperature: number = 0;
  @StorageLink('humidity') humidity: number = 0;
  @StorageLink('petName') petName: string = '胖宝宝';
  @State isComforting: boolean = false;
  @State selectedTab: number = 1;
  @State selectedSpecies: string = 'cat';
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

  @Builder
  MiniStat(icon: Resource, label: string, value: string, tint: string) {
    Column() {
      Image(icon).width(16).height(16).fillColor(tint);
      Text(value).fontSize(18).fontWeight(FontWeight.Bold).fontColor(Theme.TEXT_PRIMARY).margin({ top: 4 });
      Text(label).fontSize(10).fontColor(Theme.TEXT_TERTIARY).margin({ top: 1 });
    }
    .layoutWeight(1).alignItems(HorizontalAlign.Center);
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        Image($rawfile('image/ic_back.svg')).width(22).height(22)
          .fillColor(Theme.TEXT_PRIMARY).onClick(() => { router.back(); });
        Blank();
        Text('安抚中心').fontSize(19).fontWeight(FontWeight.Bold).fontColor(Theme.TEXT_PRIMARY);
        Blank();
        Text('').width(22);
      }
      .width('100%').padding({ left: 16, right: 16, top: 14, bottom: 12 });

      Scroll() {
        Column() {
          // 宠物状态卡
          Row() {
            this.MiniStat($rawfile('image/ic_emotion.svg'), '情绪指数',
              this.anxietyIndex.toString(), anxietyColor(this.anxietyIndex));
            Column().width(1).height(30).backgroundColor(Theme.BORDER);
            this.MiniStat($rawfile('image/ic_temp.svg'), '温度',
              this.temperature.toFixed(1) + '°', Theme.WARNING);
            Column().width(1).height(30).backgroundColor(Theme.BORDER);
            this.MiniStat($rawfile('image/ic_humidity.svg'), '湿度',
              this.humidity.toFixed(0) + '%', Theme.INFO);
          }
          .width('100%').padding(16).backgroundColor(Theme.CARD)
          .borderRadius(Theme.RADIUS_LG)
          .shadow({ radius: 10, color: '#0D000000', offsetX: 0, offsetY: 2 });

          Text('正在陪伴 ' + this.petName)
            .fontSize(13).fontColor(Theme.TEXT_TERTIARY).margin({ top: 14, bottom: 4 });

          // 安抚类型分段切换
          Row() {
            Text('灯光安抚').fontSize(14).fontWeight(this.selectedTab === 1 ? FontWeight.Medium : FontWeight.Normal)
              .fontColor(this.selectedTab === 1 ? Theme.TEXT_WHITE : Theme.TEXT_SECONDARY)
              .layoutWeight(1).textAlign(TextAlign.Center).padding({ top: 9, bottom: 9 })
              .backgroundColor(this.selectedTab === 1 ? Theme.PRIMARY : Color.Transparent)
              .borderRadius(Theme.RADIUS_PILL)
              .onClick(() => { this.selectedTab = 1; });
            Text('语音安抚').fontSize(14).fontWeight(this.selectedTab === 2 ? FontWeight.Medium : FontWeight.Normal)
              .fontColor(this.selectedTab === 2 ? Theme.TEXT_WHITE : Theme.TEXT_SECONDARY)
              .layoutWeight(1).textAlign(TextAlign.Center).padding({ top: 9, bottom: 9 })
              .backgroundColor(this.selectedTab === 2 ? Theme.PRIMARY : Color.Transparent)
              .borderRadius(Theme.RADIUS_PILL)
              .onClick(() => { this.selectedTab = 2; });
          }
          .width('100%').padding(4).backgroundColor(Theme.CARD_SOFT)
          .borderRadius(Theme.RADIUS_PILL).margin({ top: 12, bottom: 16 });

          // ---- 灯光安抚 ----
          if (this.selectedTab === 1) {
            Column() {
              Column() {
                Image($rawfile('image/ic_light_bulb.svg')).width(48).height(48)
                  .fillColor(Theme.PRIMARY).margin({ bottom: 12 });
                Text('呼吸灯安抚').fontSize(18).fontWeight(FontWeight.Bold)
                  .fontColor(Theme.TEXT_PRIMARY);
                Text('通过 RGB LED 发出暖橙色呼吸光，约 30 秒自动停止')
                  .fontSize(12).fontColor(Theme.TEXT_TERTIARY)
                  .textAlign(TextAlign.Center).margin({ top: 6 });
              }
              .width('100%').padding({ top: 28, bottom: 20 }).alignItems(HorizontalAlign.Center);

              Button(this.isComforting ? '发送中...' : '开启呼吸灯')
                .width('100%').height(50).fontSize(16).fontWeight(FontWeight.Medium)
                .backgroundColor(Theme.PRIMARY).borderRadius(Theme.RADIUS_PILL)
                .enabled(!this.isComforting)
                .onClick(() => { this.handleLightComfort(); });
            }
            .width('100%').padding(20).backgroundColor(Theme.CARD)
            .borderRadius(Theme.RADIUS_XL)
            .shadow({ radius: 12, color: '#0D000000', offsetX: 0, offsetY: 3 });
          }

          // ---- 语音安抚 ----
          if (this.selectedTab === 2) {
            Column() {
              // 舒缓音乐卡
              Row() {
                Column() {
                  Image($rawfile('image/ic_music.svg')).width(28).height(28).fillColor('#9C27B0');
                }
                .width(52).height(52).borderRadius(Theme.RADIUS_MD)
                .backgroundColor('#9C27B0' + '18').margin({ right: 14 });
                Column() {
                  Text('舒缓音乐').fontSize(16).fontWeight(FontWeight.Medium).fontColor(Theme.TEXT_PRIMARY);
                  Text('蜂鸣器五声音阶摇篮曲 + 暖光呼吸灯').fontSize(11).fontColor(Theme.TEXT_TERTIARY).margin({ top: 2 });
                }
                .alignItems(HorizontalAlign.Start).layoutWeight(1);
                Button(this.isComforting ? '播放中' : '播放')
                  .fontSize(13).height(34).backgroundColor('#9C27B0')
                  .borderRadius(Theme.RADIUS_PILL).enabled(!this.isComforting)
                  .onClick(() => { this.handleMusicComfort(); });
              }
              .width('100%').padding(14).backgroundColor(Theme.CARD)
              .borderRadius(Theme.RADIUS_LG).margin({ bottom: 12 })
              .shadow({ radius: 8, color: '#0A000000', offsetX: 0, offsetY: 2 });

              // 宠物叫声卡
              Column() {
                Row() {
                  Image($rawfile('image/ic_sound.svg')).width(20).height(20).fillColor(Theme.PRIMARY);
                  Text('宠物叫声').fontSize(15).fontWeight(FontWeight.Medium)
                    .fontColor(Theme.TEXT_PRIMARY).margin({ left: 6 });
                  Blank();
                  // 物种切换
                  Row() {
                    Text('猫').fontSize(12).fontColor(this.selectedSpecies === 'cat' ? Theme.TEXT_WHITE : Theme.TEXT_SECONDARY)
                      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                      .backgroundColor(this.selectedSpecies === 'cat' ? Theme.PRIMARY : Color.Transparent)
                      .borderRadius(Theme.RADIUS_PILL)
                      .onClick(() => { this.selectedSpecies = 'cat'; });
                    Text('狗').fontSize(12).fontColor(this.selectedSpecies === 'dog' ? Theme.TEXT_WHITE : Theme.TEXT_SECONDARY)
                      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                      .backgroundColor(this.selectedSpecies === 'dog' ? Theme.PRIMARY : Color.Transparent)
                      .borderRadius(Theme.RADIUS_PILL)
                      .onClick(() => { this.selectedSpecies = 'dog'; });
                  }
                  .padding(3).backgroundColor(Theme.CARD_SOFT).borderRadius(Theme.RADIUS_PILL);
                }
                .width('100%').margin({ bottom: 12 });

                Row({ space: 10 }) {
                  this.SoundBtn('开心', 'happy', Theme.SUCCESS);
                  this.SoundBtn('玩耍', 'play', Theme.INFO);
                  this.SoundBtn('平静', 'calm', Theme.PRIMARY);
                }
                .width('100%');
              }
              .width('100%').padding(16).backgroundColor(Theme.CARD)
              .borderRadius(Theme.RADIUS_LG)
              .shadow({ radius: 8, color: '#0A000000', offsetX: 0, offsetY: 2 });
            }
            .width('100%');
          }

          // 状态消息
          if (this.statusMsg !== '') {
            Text(this.statusMsg)
              .fontSize(13).fontColor(this.statusMsg.includes('失败') ? Theme.DANGER : Theme.SUCCESS)
              .margin({ top: 18 }).textAlign(TextAlign.Center)
              .width('100%').padding(12).backgroundColor(
                this.statusMsg.includes('失败') ? Theme.DANGER + '12' : Theme.SUCCESS + '12')
              .borderRadius(Theme.RADIUS_MD);
          }
        }
        .width('100%').padding({ left: 16, right: 16, bottom: 30 });
      }
      .width('100%').layoutWeight(1).scrollBar(BarState.Off);
    }
    .width('100%').height('100%').backgroundColor(Theme.BG);
  }

  @Builder
  SoundBtn(label: string, mood: string, tint: string) {
    Column() {
      Text(label).fontSize(14).fontWeight(FontWeight.Medium).fontColor(tint);
    }
    .layoutWeight(1).padding({ top: 12, bottom: 12 })
    .backgroundColor(tint + '12').borderRadius(Theme.RADIUS_MD)
    .onClick(() => { this.handlePetSound(mood); });
  }
}
