// ProfilePage.ets — 多宠物档案管理
import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import { Pet, petAdoptionLabel } from '../model/Pet';
import { getMyPets, getCurrentPetId, setCurrentPetId, removePet } from '../utils/PetDataManager';
import { logoutUser, getCurrentUser } from '../utils/UserDataManager';

const PET_UPDATE_KEY: string = 'petUpdateKey';

@Entry
@Component
export struct ProfilePage {
  @State pets: Pet[] = [];
  @State currentPet: Pet | null = null;
  @State isLoading: boolean = true;
  @State userName: string = '';
  
  // 单独的状态变量，确保更新能被检测
  @State petName: string = '';
  @State petBreed: string = '';
  @State petAge: string = '';
  @State petWeight: string = '';
  @State petGender: string = '';
  @State petStatus: string = '';
  @State petAvatar: string = '';
  
  // 宠物选择弹窗
  @State showPetSelector: boolean = false;
  
  // 强制刷新开关
  @State showDetails: boolean = true;
  
  @Watch('onUpdateKeyChanged')
  @StorageLink(PET_UPDATE_KEY) updateKey: number = 0;

  async aboutToAppear() {
    await this.loadUserData();
    await this.loadPets();
  }

  async onPageShow() {
    console.info('[ProfilePage] onPageShow triggered');
    await this.loadPets();
  }
  
  onUpdateKeyChanged() {
    console.info('[ProfilePage] updateKey changed:', this.updateKey);
    this.loadPets();
  }

  forceRefresh() {
    AppStorage.SetOrCreate(PET_UPDATE_KEY, (AppStorage.Get<number>(PET_UPDATE_KEY) ?? 0) + 1);
  }

  async loadUserData() {
    const user = await getCurrentUser();
    if (user !== null) {
      this.userName = user.name;
    }
  }

  async loadPets() {
    this.isLoading = true;
    this.pets = await getMyPets();
    console.info('[ProfilePage] loadPets fetched:', this.pets.length, 'pets');
    const curId = getCurrentPetId();
    if (this.pets.length > 0) {
      const found = this.pets.find(p => p.id === curId);
      const selectedPet = found ?? this.pets[0];
      this.currentPet = selectedPet;
      this.updatePetDisplay(selectedPet);
      setCurrentPetId(selectedPet.id);
      AppStorage.SetOrCreate('petName', selectedPet.name);
      console.info('[ProfilePage] loadPets selected:', selectedPet.id, selectedPet.name);
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
    console.info('[ProfilePage] updatePetDisplay:', pet.name, pet.breed);
  }

  clearPetDisplay() {
    this.petName = '';
    this.petBreed = '';
    this.petAge = '';
    this.petWeight = '';
    this.petGender = '';
    this.petStatus = '';
    this.petAvatar = '';
  }

  selectPet(pet: Pet) {
    console.info('[ProfilePage] selectPet:', pet.id, pet.name);
    
    // 强制刷新：先隐藏再显示
    this.showDetails = false;
    
    // 延迟设置新值并重新显示
    setTimeout(() => {
      this.currentPet = pet;
      this.petName = pet.name;
      this.petBreed = pet.breed;
      this.petAge = pet.age;
      this.petWeight = pet.weight;
      this.petGender = pet.gender;
      this.petStatus = pet.adoptionStatus;
      this.petAvatar = pet.avatar;
      
      setCurrentPetId(pet.id);
      AppStorage.SetOrCreate('petName', pet.name);
      
      this.showDetails = true;
      console.info('[ProfilePage] selectPet updated:', this.petName, this.petBreed);
    }, 50);
  }

  async deleteCurrentPet() {
    if (this.currentPet === null) return;
    const pet = this.currentPet;
    const confirm = await promptAction.showDialog({
      title: '确认删除',
      message: '确定要删除「' + pet.name + '」吗？此操作不可撤销。',
      buttons: [
        { text: '取消', color: '#666' },
        { text: '删除', color: '#F44336' }
      ]
    });
    if (confirm.index === 1) {
      await removePet(pet.id);
      await this.loadPets();
    }
  }

  async handleLogout() {
    const confirm = await promptAction.showDialog({
      title: '确认退出',
      message: '确定要退出登录吗？',
      buttons: [
        { text: '取消', color: '#666' },
        { text: '退出', color: '#2196F3' }
      ]
    });
    if (confirm.index === 1) {
      logoutUser();
      router.replaceUrl({ url: 'pages/LoginPage' });
    }
  }

  build() {
    Column() {
      // 标题和用户信息
      Row() {
        Column() {
          Text('宠物档案')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
          if (this.userName !== '') {
            Text(`欢迎，${this.userName}`)
              .fontSize(14)
              .fontColor('#666')
              .margin({ top: 2 })
          }
        }
        .alignItems(HorizontalAlign.Start)
        Blank()
        Button('退出')
          .fontSize(14)
          .fontColor('#F44336')
          .backgroundColor(Color.Transparent)
          .onClick(() => this.handleLogout())
      }
      .width('100%')
      .margin({ top: 30, bottom: 10 })

      if (this.isLoading) {
        LoadingProgress()
          .width(40)
          .height(40)
          .margin({ top: 80 })
      } else if (this.pets.length === 0) {
        // 空状态
        Column() {
          Text('还没有添加宠物')
            .fontSize(18)
            .fontColor('#999')
            .margin({ top: 80, bottom: 20 })
          Button('添加第一只宠物')
            .width('60%')
            .height(40)
            .fontSize(14)
            .backgroundColor('#2196F3')
            .borderRadius(20)
            .onClick(() => {
              router.pushUrl({ url: 'pages/EditProfilePage', params: { petId: 0 } });
            })
        }
      } else {
        // 当前宠物标题栏（显示名称 + 切换图标）
        Row() {
          Image(this.petAvatar !== '' ? this.petAvatar : $r('app.media.startIcon'))
            .width(45)
            .height(45)
            .borderRadius(22)
            .backgroundColor('#E0E0E0')
          Column() {
            Text('当前宠物')
              .fontSize(12)
              .fontColor('#999')
            Text(this.petName)
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
          }
          .margin({ left: 10 })
          Blank()
          // 切换图标（三个点）
          Image($r('app.media.startIcon'))
            .width(30)
            .height(30)
            .backgroundColor('#E0E0E0')
            .borderRadius(8)
            .onClick(() => {
              this.showPetSelector = true;
            })
        }
        .width('100%')
        .padding({ top: 15, bottom: 15 })
        .margin({ top: 20 })

        // 当前宠物详情 - 使用 showDetails 强制刷新
        if (this.showDetails && this.currentPet !== null) {
          Column() {
            // 头像 + 名字
            Column() {
              Image(this.petAvatar !== '' ? this.petAvatar : $r('app.media.startIcon'))
                .width(80)
                .height(80)
                .borderRadius(40)
                .backgroundColor('#E0E0E0')
              Text(this.petName)
                .fontSize(22)
                .fontWeight(FontWeight.Bold)
                .margin({ top: 8 })
              Text(petAdoptionLabel(this.petStatus))
                .fontSize(13)
                .fontColor('#FFF')
                .backgroundColor(this.petStatus === 'owned' ? '#4CAF50' : '#FF9800')
                .borderRadius(10)
                .padding({ left: 10, right: 10, top: 2, bottom: 2 })
                .margin({ top: 4 })
            }
            .margin({ top: 15, bottom: 15 })

            // 信息列表
            Column() {
              this.infoRow('品种', this.petBreed)
              this.infoRow('年龄', this.petAge)
              this.infoRow('体重', this.petWeight)
              this.infoRow('性别', this.petGender)
            }
            .width('85%')

            // 操作按钮
            Row() {
              Button('编辑')
                .width('35%')
                .height(40)
                .fontSize(14)
                .backgroundColor('#2196F3')
                .borderRadius(20)
                .onClick(() => {
                  if (this.currentPet === null) {
                    console.error('[ProfilePage] currentPet is null, cannot edit');
                    return;
                  }
                  console.info('[ProfilePage] Edit pet:', this.currentPet.id, this.currentPet.name);
                  router.pushUrl({
                    url: 'pages/EditProfilePage',
                    params: { petId: this.currentPet.id }
                  });
                })

              Button('删除')
                .width('35%')
                .height(40)
                .fontSize(14)
                .backgroundColor('#F44336')
                .borderRadius(20)
                .margin({ left: 10 })
                .onClick(() => this.deleteCurrentPet())
            }
            .margin({ top: 25 })

            Button('添加宠物')
              .width('35%')
              .height(40)
              .fontSize(14)
              .backgroundColor('#4CAF50')
              .borderRadius(20)
              .margin({ top: 10 })
              .onClick(() => {
                router.pushUrl({ url: 'pages/EditProfilePage', params: { petId: 0 } });
              })
          }
          .width('100%')
        }
      }

      // 宠物选择弹窗
      if (this.showPetSelector) {
        Column() {
          // 遮罩层
          Stack({ alignContent: Alignment.Center }) {
            Column() {
              Text('选择宠物')
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .margin({ top: 20, bottom: 15 })
              Scroll() {
                Column() {
                  ForEach(this.pets, (pet: Pet) => {
                    Row() {
                      Image(pet.avatar !== '' ? pet.avatar : $r('app.media.startIcon'))
                        .width(50)
                        .height(50)
                        .borderRadius(25)
                        .backgroundColor('#E0E0E0')
                      Column() {
                        Text(pet.name)
                          .fontSize(16)
                          .fontWeight(FontWeight.Medium)
                        Text(pet.breed)
                          .fontSize(12)
                          .fontColor('#666')
                      }
                      .margin({ left: 12 })
                      Blank()
                      if (this.currentPet?.id === pet.id) {
                        Text('当前')
                          .fontSize(12)
                          .fontColor('#2196F3')
                      }
                    }
                    .width('100%')
                    .padding({ top: 12, bottom: 12 })
                    .backgroundColor(this.currentPet?.id === pet.id ? '#E3F2FD' : '#FFF')
                    .borderRadius(10)
                    .onClick(() => {
                      this.selectPet(pet);
                      this.showPetSelector = false;
                    })
                  })
                }
                .width('100%')
              }
              .width('100%')
              .height(200)
              .margin({ bottom: 15 })
              Button('取消')
                .width('80%')
                .height(40)
                .fontSize(14)
                .backgroundColor('#999')
                .borderRadius(20)
                .margin({ bottom: 20 })
                .onClick(() => {
                  this.showPetSelector = false;
                })
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
  infoRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(16)
        .fontColor('#666')
        .width(60)
      Text(value)
        .fontSize(16)
        .fontColor('#333')
        .margin({ left: 20 })
      Blank()
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
    .border({ width: { bottom: 0.5 }, color: '#E0E0E0' })
  }
}
