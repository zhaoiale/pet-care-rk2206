// ProfilePage.ets — 多宠物档案管理（UI 优化版，逻辑不变）
import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import { Pet, petAdoptionLabel } from '../model/Pet';
import { getMyPets, getCurrentPetId, setCurrentPetId, removePet } from '../utils/PetDataManager';
import { logoutUser, getCurrentUser } from '../utils/UserDataManager';
import { Theme } from '../common/Theme';

const PET_UPDATE_KEY: string = 'petUpdateKey';

@Entry
@Component
export struct ProfilePage {
  @State pets: Pet[] = [];
  @State currentPet: Pet | null = null;
  @State isLoading: boolean = true;
  @State userName: string = '';
  @State petName: string = '';
  @State petBreed: string = '';
  @State petAge: string = '';
  @State petWeight: string = '';
  @State petGender: string = '';
  @State petStatus: string = '';
  @State petAvatar: string = '';
  @State showPetSelector: boolean = false;
  @State showDetails: boolean = true;

  @Watch('onUpdateKeyChanged')
  @StorageLink(PET_UPDATE_KEY) updateKey: number = 0;

  async aboutToAppear() {
    await this.loadUserData();
    await this.loadPets();
  }

  async onPageShow() {
    await this.loadPets();
  }

  onUpdateKeyChanged() {
    this.loadPets();
  }

  forceRefresh() {
    AppStorage.SetOrCreate(PET_UPDATE_KEY, (AppStorage.Get<number>(PET_UPDATE_KEY) ?? 0) + 1);
  }

  async loadUserData() {
    const user = await getCurrentUser();
    if (user !== null) { this.userName = user.name; }
  }

  async loadPets() {
    this.isLoading = true;
    this.pets = await getMyPets();
    const curId = getCurrentPetId();
    if (this.pets.length > 0) {
      const found = this.pets.find(p => p.id === curId);
      const selectedPet = found ?? this.pets[0];
      this.currentPet = selectedPet;
      this.updatePetDisplay(selectedPet);
      setCurrentPetId(selectedPet.id);
      AppStorage.SetOrCreate('petName', selectedPet.name);
    } else {
      this.currentPet = null;
      this.clearPetDisplay();
    }
    this.isLoading = false;
  }

  updatePetDisplay(pet: Pet) {
    this.petName = pet.name;
    this.petBreed = pet.breed;
    this.petAge = pet.age;
    this.petWeight = pet.weight;
    this.petGender = pet.gender;
    this.petStatus = pet.adoptionStatus;
    this.petAvatar = pet.avatar;
  }

  clearPetDisplay() {
    this.petName = ''; this.petBreed = ''; this.petAge = '';
    this.petWeight = ''; this.petGender = ''; this.petStatus = ''; this.petAvatar = '';
  }

  selectPet(pet: Pet) {
    this.showDetails = false;
    setTimeout(() => {
      this.currentPet = pet;
      this.petName = pet.name; this.petBreed = pet.breed; this.petAge = pet.age;
      this.petWeight = pet.weight; this.petGender = pet.gender; this.petStatus = pet.adoptionStatus;
      this.petAvatar = pet.avatar;
      setCurrentPetId(pet.id);
      AppStorage.SetOrCreate('petName', pet.name);
      this.showDetails = true;
    }, 50);
  }

  async deleteCurrentPet() {
    if (this.currentPet === null) return;
    const pet = this.currentPet;
    const confirm = await promptAction.showDialog({
      title: '确认删除', message: '确定要删除「' + pet.name + '」吗？此操作不可撤销。',
      buttons: [{ text: '取消', color: Theme.TEXT_SECONDARY }, { text: '删除', color: Theme.DANGER }]
    });
    if (confirm.index === 1) { await removePet(pet.id); await this.loadPets(); }
  }

  async handleLogout() {
    const confirm = await promptAction.showDialog({
      title: '确认退出', message: '确定要退出登录吗？',
      buttons: [{ text: '取消', color: Theme.TEXT_SECONDARY }, { text: '退出', color: Theme.PRIMARY }]
    });
    if (confirm.index === 1) { logoutUser(); router.replaceUrl({ url: 'pages/LoginPage' }); }
  }

  // 宠物头像占位
  @Builder
  PetAvatar(size: number, avatar: string) {
    if (avatar !== '') {
      Image(avatar).width(size).height(size).borderRadius(size / 2).objectFit(ImageFit.Cover);
    } else {
      Column() {
        Image($rawfile('image/tab_pet.svg')).width(size * 0.5).height(size * 0.5).fillColor(Theme.PRIMARY);
      }
      .width(size).height(size).borderRadius(size / 2).backgroundColor(Theme.PRIMARY_SOFT)
      .justifyContent(FlexAlign.Center);
    }
  }

  build() {
    Stack() {
      Column() {
        // 标题栏
        Row() {
          Column() {
            Text('宠物档案').fontSize(22).fontWeight(FontWeight.Bold).fontColor(Theme.TEXT_PRIMARY);
            if (this.userName !== '') {
              Text(`欢迎，${this.userName}`).fontSize(13).fontColor(Theme.TEXT_TERTIARY).margin({ top: 2 });
            }
          }
          .alignItems(HorizontalAlign.Start).layoutWeight(1);
          Image($rawfile('image/ic_user.svg')).width(20).height(20).fillColor(Theme.DANGER)
            .onClick(() => this.handleLogout());
        }
        .width('100%').padding({ top: 14, bottom: 12 });

        if (this.isLoading) {
          Column() {
            LoadingProgress().width(40).height(40).color(Theme.PRIMARY);
          }
          .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center);
        } else if (this.pets.length === 0) {
          Column() {
            Column() {
              Image($rawfile('image/tab_pet.svg')).width(56).height(56).fillColor(Theme.TEXT_TERTIARY);
            }
            .width(96).height(96).borderRadius(48).backgroundColor(Theme.CARD)
            .justifyContent(FlexAlign.Center).margin({ top: 60 });
            Text('还没有添加宠物').fontSize(17).fontColor(Theme.TEXT_SECONDARY).margin({ top: 20 });
            Button('添加第一只宠物')
              .width('60%').height(44).fontSize(14).backgroundColor(Theme.PRIMARY)
              .borderRadius(Theme.RADIUS_PILL).margin({ top: 20 })
              .onClick(() => { router.pushUrl({ url: 'pages/EditProfilePage', params: { petId: 0 } }); });
          }
          .width('100%').layoutWeight(1);
        } else {
          Scroll() {
            Column() {
              // 当前宠物切换卡
              Row() {
                this.PetAvatar(48, this.petAvatar);
                Column() {
                  Text('当前宠物').fontSize(11).fontColor(Theme.TEXT_TERTIARY);
                  Text(this.petName).fontSize(17).fontWeight(FontWeight.Bold).fontColor(Theme.TEXT_PRIMARY).margin({ top: 1 });
                }
                .margin({ left: 12 }).alignItems(HorizontalAlign.Start).layoutWeight(1);
                Row() {
                  Text('切换').fontSize(12).fontColor(Theme.PRIMARY);
                  Image($rawfile('image/ic_arrow_right.svg')).width(14).height(14).fillColor(Theme.PRIMARY).margin({ left: 2 });
                }
                .onClick(() => { this.showPetSelector = true; });
              }
              .width('100%').padding(14).backgroundColor(Theme.CARD)
              .borderRadius(Theme.RADIUS_LG).margin({ bottom: 14 })
              .shadow({ radius: 8, color: '#0A000000', offsetX: 0, offsetY: 2 });

              // 宠物详情
              if (this.showDetails && this.currentPet !== null) {
                Column() {
                  this.PetAvatar(88, this.petAvatar);
                  Text(this.petName).fontSize(22).fontWeight(FontWeight.Bold)
                    .fontColor(Theme.TEXT_PRIMARY).margin({ top: 10 });
                  Text(petAdoptionLabel(this.petStatus))
                    .fontSize(12).fontColor(Theme.TEXT_WHITE)
                    .backgroundColor(this.petStatus === 'owned' ? Theme.SUCCESS : Theme.WARNING)
                    .borderRadius(Theme.RADIUS_PILL)
                    .padding({ left: 12, right: 12, top: 4, bottom: 4 }).margin({ top: 6 });

                  // 信息网格
                  Row({ space: 10 }) {
                    this.InfoCell('品种', this.petBreed);
                    this.InfoCell('年龄', this.petAge);
                  }
                  .width('100%').margin({ top: 18 });
                  Row({ space: 10 }) {
                    this.InfoCell('体重', this.petWeight);
                    this.InfoCell('性别', this.petGender);
                  }
                  .width('100%').margin({ top: 10 });

                  // 操作按钮
                  Row({ space: 12 }) {
                    Button() {
                      Row() {
                        Image($rawfile('image/ic_edit.svg')).width(16).height(16).fillColor(Theme.TEXT_WHITE);
                        Text('编辑').fontSize(14).fontColor(Theme.TEXT_WHITE).margin({ left: 6 });
                      }
                    }
                    .layoutWeight(1).height(44).backgroundColor(Theme.PRIMARY)
                    .borderRadius(Theme.RADIUS_PILL)
                    .onClick(() => {
                      if (this.currentPet === null) return;
                      router.pushUrl({ url: 'pages/EditProfilePage', params: { petId: this.currentPet.id } });
                    });

                    Button() {
                      Row() {
                        Image($rawfile('image/ic_delete.svg')).width(16).height(16).fillColor(Theme.DANGER);
                        Text('删除').fontSize(14).fontColor(Theme.DANGER).margin({ left: 6 });
                      }
                    }
                    .layoutWeight(1).height(44).backgroundColor(Theme.DANGER + '15')
                    .borderRadius(Theme.RADIUS_PILL)
                    .onClick(() => this.deleteCurrentPet());
                  }
                  .width('100%').margin({ top: 20 });

                  Button() {
                    Row() {
                      Image($rawfile('image/ic_add.svg')).width(16).height(16).fillColor(Theme.SUCCESS);
                      Text('添加宠物').fontSize(14).fontColor(Theme.SUCCESS).margin({ left: 6 });
                    }
                  }
                  .width('100%').height(44).backgroundColor(Theme.SUCCESS + '15')
                  .borderRadius(Theme.RADIUS_PILL).margin({ top: 10 })
                  .onClick(() => { router.pushUrl({ url: 'pages/EditProfilePage', params: { petId: 0 } }); });
                }
                .width('100%').padding(20).backgroundColor(Theme.CARD)
                .borderRadius(Theme.RADIUS_XL).margin({ bottom: 20 })
                .shadow({ radius: 12, color: '#0D000000', offsetX: 0, offsetY: 3 });
              }
            }
            .width('100%');
          }
          .width('100%').layoutWeight(1).scrollBar(BarState.Off);
        }
      }
      .width('100%').height('100%').padding({ left: 16, right: 16 }).backgroundColor(Theme.BG);

      // 宠物选择弹窗
      if (this.showPetSelector) {
        Stack({ alignContent: Alignment.Center }) {
          Column() {
            Text('选择宠物').fontSize(18).fontWeight(FontWeight.Bold)
              .fontColor(Theme.TEXT_PRIMARY).margin({ top: 20, bottom: 12 });
            Scroll() {
              Column({ space: 8 }) {
                ForEach(this.pets, (pet: Pet) => {
                  Row() {
                    this.PetAvatar(44, pet.avatar);
                    Column() {
                      Text(pet.name).fontSize(15).fontWeight(FontWeight.Medium).fontColor(Theme.TEXT_PRIMARY);
                      Text(pet.breed).fontSize(12).fontColor(Theme.TEXT_TERTIARY).margin({ top: 1 });
                    }
                    .margin({ left: 12 }).alignItems(HorizontalAlign.Start).layoutWeight(1);
                    if (this.currentPet?.id === pet.id) {
                      Text('当前').fontSize(11).fontColor(Theme.PRIMARY)
                        .backgroundColor(Theme.PRIMARY_SOFT).borderRadius(Theme.RADIUS_PILL)
                        .padding({ left: 8, right: 8, top: 3, bottom: 3 });
                    }
                  }
                  .width('100%').padding(12)
                  .backgroundColor(this.currentPet?.id === pet.id ? Theme.PRIMARY_SOFT : Theme.CARD_SOFT)
                  .borderRadius(Theme.RADIUS_MD)
                  .onClick(() => { this.selectPet(pet); this.showPetSelector = false; });
                });
              }
              .width('100%');
            }
            .width('100%').height(220).margin({ bottom: 14 });
            Button('取消').width('80%').height(42).fontSize(14)
              .backgroundColor(Theme.TEXT_TERTIARY).borderRadius(Theme.RADIUS_PILL)
              .margin({ bottom: 20 }).onClick(() => { this.showPetSelector = false; });
          }
          .width('82%').backgroundColor(Theme.CARD).borderRadius(Theme.RADIUS_XL)
          .shadow({ radius: 20, color: '#30000000', offsetX: 0, offsetY: 8 });
        }
        .width('100%').height('100%').backgroundColor('rgba(0,0,0,0.5)')
        .position({ top: 0, left: 0 });
      }
    }
    .width('100%').height('100%');
  }

  @Builder
  InfoCell(label: string, value: string) {
    Column() {
      Text(label).fontSize(11).fontColor(Theme.TEXT_TERTIARY);
      Text(value).fontSize(15).fontWeight(FontWeight.Medium).fontColor(Theme.TEXT_PRIMARY).margin({ top: 4 });
    }
    .width('100%').layoutWeight(1).padding(12).backgroundColor(Theme.CARD_SOFT).borderRadius(Theme.RADIUS_MD)
    .alignItems(HorizontalAlign.Start);
  }
}
