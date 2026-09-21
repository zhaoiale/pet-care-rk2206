// AdoptionPage.ets — 领养中心
import { Theme } from '../common/Theme';
import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import { Pet, petAdoptionLabel } from '../model/Pet';
import { getAvailablePets, adoptPet as adoptPetManager } from '../utils/PetDataManager';

const PET_UPDATE_KEY: string = 'petUpdateKey';

@Entry
@Component
struct AdoptionPage {
  @State availablePets: Pet[] = [];
  @State isLoading: boolean = true;
  @State showPetDetail: boolean = false;
  @State selectedPet: Pet | null = null;

  async aboutToAppear() {
    await this.loadPets();
  }

  async onPageShow() {
    await this.loadPets();
  }

  async loadPets() {
    this.isLoading = true;
    this.availablePets = await getAvailablePets();
    this.isLoading = false;
  }

  async adoptPet(pet: Pet) {
    const confirm = await promptAction.showDialog({
      title: '确认领养',
      message: '确定要领养「' + pet.name + '」吗？\n\n领养后您将成为它的主人，需要用心照顾它哦！',
      buttons: [
        { text: '取消', color: '#666' },
        { text: '确定领养', color: '#4CAF50' }
      ]
    });
    
    if (confirm.index === 1) {
      const success = await adoptPetManager(pet);
      if (success) {
        await this.loadPets();
        AppStorage.SetOrCreate(PET_UPDATE_KEY, (AppStorage.Get<number>(PET_UPDATE_KEY) ?? 0) + 1);
        this.showPetDetail = false;
        await promptAction.showDialog({
          title: '领养成功',
          message: '恭喜您已成功领养「' + pet.name + '」！\n\n它现在是您家庭的一员了，请好好照顾它！',
          buttons: [
            { text: '太棒了', color: '#4CAF50' }
          ]
        });
      }
    }
  }

  showDetail(pet: Pet) {
    this.selectedPet = pet;
    this.showPetDetail = true;
  }

  build() {
    Column() {
      // 头部
      Column() {
        Text('领养中心')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.TEXT_PRIMARY)
          .margin({ top: 30, bottom: 5 })

        Text('给流浪的小动物一个温暖的家')
          .fontSize(15)
          .fontColor(Theme.TEXT_TERTIARY)
          .margin({ bottom: 10 })

        // 统计信息
        Row() {
          Column() {
            Text(this.availablePets.length.toString())
              .fontSize(28)
              .fontWeight(FontWeight.Bold)
              .fontColor('#4CAF50')
            Text('待领养')
              .fontSize(12)
              .fontColor('#999')
          }
          .margin({ right: 30 })
          Column() {
            Text('100%')
              .fontSize(28)
              .fontWeight(FontWeight.Bold)
              .fontColor('#2196F3')
            Text('成活率')
              .fontSize(12)
              .fontColor('#999')
          }
        }
        .margin({ bottom: 20 })
      }
      .width('100%')
      .backgroundColor(Theme.BG)
      .padding({ bottom: 20 })

      // 内容区域
      if (this.isLoading) {
        LoadingProgress()
          .width(40)
          .height(40)
          .margin({ top: 80 })
      } else if (this.availablePets.length === 0) {
        Column() {
          Image($r('app.media.startIcon'))
            .width(100)
            .height(100)
            .backgroundColor('#E8F5E9')
            .borderRadius(50)
            .margin({ top: 60 })
          Text('暂无可领养宠物')
            .fontSize(18)
            .fontColor('#999')
            .margin({ top: 20 })
          Text('去添加一只需要领养的小动物吧')
            .fontSize(14)
            .fontColor('#BBB')
            .margin({ top: 10 })
          Button('添加宠物')
            .width('50%')
            .height(40)
            .fontSize(14)
            .backgroundColor('#4CAF50')
            .borderRadius(20)
            .margin({ top: 20 })
            .onClick(() => {
              router.pushUrl({ url: 'pages/EditProfilePage', params: { petId: 0 } });
            })
        }
      } else {
        List() {
          ForEach(this.availablePets, (pet: Pet) => {
            ListItem() {
              Column() {
                // 宠物卡片
                Row() {
                  Image(pet.avatar !== '' ? pet.avatar : $r('app.media.startIcon'))
                    .width(70)
                    .height(70)
                    .borderRadius(35)
                    .backgroundColor('#E0E0E0')
                  Column() {
                    Text(pet.name)
                      .fontSize(18)
                      .fontWeight(FontWeight.Bold)
                    Row() {
                      Text(pet.breed)
                        .fontSize(13)
                        .fontColor('#666')
                      Text(' · ')
                        .fontSize(13)
                        .fontColor('#DDD')
                      Text(pet.age)
                        .fontSize(13)
                        .fontColor('#666')
                      Text(' · ')
                        .fontSize(13)
                        .fontColor('#DDD')
                      Text(pet.gender === 'male' ? '公' : '母')
                        .fontSize(13)
                        .fontColor('#666')
                    }
                    .margin({ top: 4 })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .margin({ left: 12 })
                  .layoutWeight(1)

                  Text('待领养')
                    .fontSize(12)
                    .fontColor('#FFF')
                    .backgroundColor('#FF9800')
                    .borderRadius(10)
                    .padding({ left: 10, right: 10, top: 3, bottom: 3 })
                }
                .width('100%')
                .padding(15)

                // 操作按钮
                Row() {
                  Button('查看详情')
                    .fontSize(14)
                    .backgroundColor('#E8F5E9')
                    .fontColor('#4CAF50')
                    .borderRadius(20)
                    .width('40%')
                    .height(36)
                    .onClick(() => this.showDetail(pet))
                  Button('立即领养')
                    .fontSize(14)
                    .backgroundColor('#4CAF50')
                    .borderRadius(20)
                    .width('40%')
                    .height(36)
                    .onClick(() => this.adoptPet(pet))
                }
                .width('100%')
                .justifyContent(FlexAlign.SpaceAround)
                .padding({ bottom: 12 })
              }
              .width('100%')
              .backgroundColor('#FFF')
              .borderRadius(15)
              .shadow({ radius: 3, color: 'rgba(0,0,0,0.05)', offsetX: 0, offsetY: 2 })
              .margin({ bottom: 12 })
            }
          })
        }
        .width('90%')
        .layoutWeight(1)
      }

      // 宠物详情弹窗
      if (this.showPetDetail && this.selectedPet !== null) {
        Column() {
          Stack({ alignContent: Alignment.Center }) {
            Column() {
              // 头像区域
              Stack({ alignContent: Alignment.BottomEnd }) {
                Image(this.selectedPet.avatar !== '' ? this.selectedPet.avatar : $r('app.media.startIcon'))
                  .width(120)
                  .height(120)
                  .borderRadius(60)
                  .backgroundColor('#E0E0E0')
                Text(petAdoptionLabel(this.selectedPet.adoptionStatus))
                  .fontSize(12)
                  .fontColor('#FFF')
                  .backgroundColor('#FF9800')
                  .borderRadius(12)
                  .padding({ left: 8, right: 8, top: 2, bottom: 2 })
              }
              .margin({ top: 20, bottom: 15 })

              // 名字
              Text(this.selectedPet.name)
                .fontSize(24)
                .fontWeight(FontWeight.Bold)
                .margin({ bottom: 5 })

              // 基本信息
              Column() {
                this.detailRow('品种', this.selectedPet.breed)
                this.detailRow('年龄', this.selectedPet.age)
                this.detailRow('体重', this.selectedPet.weight + 'kg')
                this.detailRow('性别', this.selectedPet.gender === 'male' ? '公' : '母')
              }
              .width('80%')
              .margin({ top: 10, bottom: 20 })

              // 操作按钮
              Row() {
                Button('关闭')
                  .fontSize(14)
                  .backgroundColor('#E0E0E0')
                  .borderRadius(20)
                  .width('38%')
                  .height(40)
                  .onClick(() => {
                    this.showPetDetail = false;
                  })
                Button('领养它')
                  .fontSize(14)
                  .backgroundColor('#4CAF50')
                  .borderRadius(20)
                  .width('38%')
                  .height(40)
                  .onClick(() => {
                    this.adoptPet(this.selectedPet!);
                  })
              }
              .width('100%')
              .justifyContent(FlexAlign.SpaceAround)
              .margin({ bottom: 25 })
            }
            .width('85%')
            .backgroundColor('#FFF')
            .borderRadius(20)
            .shadow({ radius: 10, color: 'rgba(0,0,0,0.3)', offsetX: 0, offsetY: 5 })
          }
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(0,0,0,0.5)')
          .position({ top: 0, left: 0 })
        }
        .width('100%')
        .height('100%')
        .position({ top: 0, left: 0 })
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 15, right: 15 })
  }

  @Builder
  detailRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor('#999')
        .width(60)
      Text(value)
        .fontSize(14)
        .fontColor('#333')
      Blank()
    }
    .width('100%')
    .padding({ top: 10, bottom: 10 })
    .border({ width: { bottom: 0.5 }, color: '#F0F0F0' })
  }
}
