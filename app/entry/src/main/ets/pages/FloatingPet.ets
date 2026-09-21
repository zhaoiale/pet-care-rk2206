// FloatingPet.ets — 全局浮窗萌宠，可拖动，所有页面可见
import router from '@ohos.router';
import { getPet, getCurrentPetId } from '../utils/PetDataManager';
import { isCat } from '../model/Pet';
import { Pet } from '../model/Pet';
import { lastAiInterpretation } from '../services/MqttService';

const DATA_UPDATE_KEY: string = 'dataUpdateKey';

@Component
export struct FloatingPet {
  @State offsetX: number = 280;
  @State offsetY: number = 200;
  @State petEmoji: string = '🐶';
  @State petName: string = '';
  @State emotionText: string = '';
  @State isCat: boolean = false;
  @State aiBubble: string = '';
  @StorageLink('anxietyIndex') anxietyLevel: number = 50;
  @StorageLink(DATA_UPDATE_KEY) dataVersion: number = 0;
  @StorageLink('currentTabIndex') currentTab: number = 0;
  private startX: number = 0;
  private startY: number = 0;
  private aiTimer: number = -1;

  async aboutToAppear() {
    await this.loadPetInfo();
    this.aiTimer = setInterval(() => {
      this.aiBubble = lastAiInterpretation || '';
    }, 5000);
  }

  aboutToDisappear() {
    if (this.aiTimer !== -1) { clearInterval(this.aiTimer); this.aiTimer = -1; }
  }

  async loadPetInfo() {
    const petId = getCurrentPetId();
    if (petId > 0) {
      const pet = await getPet(petId);
      if (pet !== null) {
        this.petName = pet.name;
        this.isCat = isCat(pet.breed);
        this.updateEmoji();
      }
    }
  }

  updateEmoji() {
    const level = this.anxietyLevel;
    if (this.isCat) {
      if (level <= 20) this.petEmoji = '😸';
      else if (level >= 80) this.petEmoji = '😿';
      else if (level >= 60) this.petEmoji = '😾';
      else this.petEmoji = '🐱';
    } else {
      this.petEmoji = '🐶';
    }

    if (level <= 15) this.emotionText = '高兴~';
    else if (level <= 35) this.emotionText = '平静';
    else if (level <= 60) this.emotionText = '警觉';
    else this.emotionText = '焦虑';
  }

  build() {
    Column() {
      // AI 气泡
      if (this.aiBubble.length > 0) {
        Row() {
          Text(this.aiBubble)
            .fontSize(10)
            .fontColor('#FFF')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .backgroundColor('#6C47FF')
        .borderRadius(10)
        .margin({ bottom: 4 })
        .constraintSize({ maxWidth: 140 })
      }

      // Pet emoji circle
      Stack() {
        Column() {}
          .width(48)
          .height(48)
          .backgroundColor('#FFF8F0')
          .borderRadius(24)
          .border({ width: 1.5, color: '#E8D5C0' })
          .shadow({ radius: 8, color: '#40000000', offsetX: 0, offsetY: 3 })

        Text(this.petEmoji)
          .fontSize(28)
      }
      .width(48)
      .height(48)

      // Name tag
      if (this.petName !== '') {
        Text(this.petName)
          .fontSize(9)
          .fontColor('#999')
          .maxLines(1)
          .margin({ top: 1 })
      }
    }
    .alignItems(HorizontalAlign.Center)
    .position({ x: this.offsetX, y: this.offsetY })
    .visibility(this.currentTab === 5 ? Visibility.Hidden : Visibility.Visible)
    .onClick(() => {
      router.pushUrl({ url: 'pages/VirtualPetPage' });
    })
    .gesture(
      PanGesture({ fingers: 1, distance: 3 })
        .onActionStart(() => {
          this.startX = this.offsetX;
          this.startY = this.offsetY;
        })
        .onActionUpdate((event: GestureEvent) => {
          this.offsetX = this.startX + event.offsetX;
          this.offsetY = this.startY + event.offsetY;
        })
        .onActionEnd(() => {
          // Snap to nearest edge
          if (this.offsetX < 180) {
            this.offsetX = 8;
          } else {
            this.offsetX = 312;
          }
          // Clamp Y within visible area
          if (this.offsetY < 80) this.offsetY = 80;
          if (this.offsetY > 620) this.offsetY = 620;
        })
    )
  }
}
