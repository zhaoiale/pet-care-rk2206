// PetManagePage.ets — 独立宠物管理页面
import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import { Pet, petAdoptionLabel } from '../model/Pet';
import { User } from '../model/User';
import { getAllPets, getPet, savePet, removePet } from '../utils/PetDataManager';
import { getAllUsers, getUserById } from '../utils/UserDataManager';

@Entry
@Component
struct PetManagePage {
  @State pets: Pet[] = [];
  @State users: User[] = [];
  @State selectedPet: Pet | null = null;
  @State currentDialog: 'detail' | 'adopt' | null = null;

  async aboutToAppear() {
    await this.loadData();
  }

  async onPageShow() {
    await this.loadData();
  }

  async loadData() {
    try {
      this.pets = await getAllPets();
      this.users = await getAllUsers();
      console.info('[PetManagePage] Loaded', this.pets.length, 'pets and', this.users.length, 'users');
    } catch (err) {
      console.error('[PetManagePage] loadData error:', JSON.stringify(err));
    }
  }

  build() {
    Stack() {
      Column() {
        // 顶部导航
        Row() {
          Button('返回')
            .fontSize(16)
            .fontColor('#2196F3')
            .onClick(() => router.back());
          Blank();
          Text('宠物信息管理')
            .fontSize(20)
            .fontWeight(FontWeight.Bold);
          Blank();
          Button('添加')
            .fontSize(16)
            .fontColor('#2196F3')
            .onClick(() => {
              router.pushUrl({ 
                url: 'pages/EditProfilePage',
                params: { noOwner: true }
              });
            });
        }
        .width('100%')
        .padding({ left: 15, right: 15, top: 15, bottom: 15 });

        if (this.pets.length === 0) {
          Column() {
            Text('暂无宠物数据')
              .fontSize(16)
              .fontColor('#999')
              .margin({ top: 100 });
          }
          .width('100%');
        } else {
          List({ space: 15 }) {
            ForEach(this.pets, (pet: Pet) => {
              ListItem() {
                this.PetCard(pet);
              }
            }, (pet: Pet) => pet.id.toString());
          }
          .width('100%')
          .padding({ left: 15, right: 15, top: 10, bottom: 10 })
          .layoutWeight(1);
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#F5F5F5');

      // 弹窗遮罩和内容
      if (this.currentDialog !== null && this.selectedPet) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#33000000')
          .onClick(() => {
            this.currentDialog = null;
          });

        if (this.currentDialog === 'detail') {
          this.DetailDialogContent();
        } else if (this.currentDialog === 'adopt') {
          this.AdoptDialogContent();
        }
      }
    }
    .width('100%')
    .height('100%');
  }

  @Builder
  PetCard(pet: Pet) {
    Column() {
      Row() {
        // 头像
        Image(pet.avatar !== '' ? pet.avatar : $r('app.media.startIcon'))
          .width(60)
          .height(60)
          .borderRadius(30)
          .backgroundColor('#E0E0E0')
          .margin({ right: 15 });

        // 宠物信息
        Column() {
          Text(pet.name)
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor('#333');
          
          Text(`${pet.breed} · ${pet.age} · ${pet.gender}`)
            .fontSize(12)
            .fontColor('#999')
            .margin({ top: 3 });
          
          Row() {
            Text(petAdoptionLabel(pet.adoptionStatus))
              .fontSize(11)
              .fontColor('#FFF')
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              .backgroundColor(pet.ownerId > 0 ? '#4CAF50' : '#FF9800')
              .borderRadius(10);
            
            if (pet.ownerId > 0) {
              Text('领养人: ' + this.getOwnerNameSync(pet.ownerId))
                .fontSize(11)
                .fontColor('#666')
                .margin({ left: 8 });
            }
          }
          .margin({ top: 5 });
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1);

        // 操作按钮
        Text('详情')
          .fontSize(13)
          .fontColor('#2196F3')
          .onClick(() => {
            this.selectedPet = pet;
            this.currentDialog = 'detail';
          });
      }
      .width('100%')
      .padding(15);
    }
    .width('100%')
    .backgroundColor('#FFFFFF')
    .borderRadius(12)
    .shadow({
      radius: 6,
      color: '#1F000000',
      offsetX: 0,
      offsetY: 2
    });
  }

  getOwnerNameSync(ownerId: number): string {
    if (ownerId <= 0) return '无';
    const user = this.users.find(u => u.id === ownerId);
    return user ? user.name : '无';
  }

  // 详情弹窗内容
  @Builder
  DetailDialogContent() {
    if (this.selectedPet) {
      Column() {
        // 标题
        Text(this.selectedPet.name)
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .margin({ bottom: 20 });

        // 详细信息
        Column({ space: 12 }) {
          this.DetailRow('品种', this.selectedPet.breed);
          this.DetailRow('年龄', this.selectedPet.age);
          this.DetailRow('体重', this.selectedPet.weight);
          this.DetailRow('性别', this.selectedPet.gender);
          this.DetailRow('领养状态', petAdoptionLabel(this.selectedPet.adoptionStatus));
          this.DetailRow('领养人', this.getOwnerNameSync(this.selectedPet.ownerId));
        }
        .width('100%')
        .margin({ bottom: 25 });

        // 操作按钮
        Column({ space: 12 }) {
          // 编辑按钮
          Button('编辑资料')
            .width('100%')
            .height(45)
            .fontSize(16)
            .backgroundColor('#2196F3')
            .borderRadius(10)
            .onClick(() => {
              this.currentDialog = null;
              router.pushUrl({ 
                url: 'pages/EditProfilePage', 
                params: { petId: this.selectedPet!.id } 
              });
            });

          // 设置领养人按钮
          if (this.users.length > 0) {
            Button(this.selectedPet.ownerId > 0 ? '更换领养人' : '设置领养人')
              .width('100%')
              .height(45)
              .fontSize(16)
              .backgroundColor('#4CAF50')
              .borderRadius(10)
              .onClick(() => {
                this.currentDialog = 'adopt';
              });
          }

          // 取消领养按钮
          if (this.selectedPet.ownerId > 0) {
            Button('取消领养')
              .width('100%')
              .height(45)
              .fontSize(16)
              .backgroundColor('#FF9800')
              .borderRadius(10)
              .onClick(async () => {
                await this.cancelAdoption();
              });
          }

          // 删除按钮
          Button('删除')
            .width('100%')
            .height(45)
            .fontSize(16)
            .backgroundColor('#F44336')
            .borderRadius(10)
            .onClick(async () => {
              await this.deletePet();
            });

          // 关闭按钮
          Button('关闭')
            .width('100%')
            .height(45)
            .fontSize(16)
            .backgroundColor('#999')
            .borderRadius(10)
            .onClick(() => {
              this.currentDialog = null;
            });
        }
        .width('100%');
      }
      .width('90%')
      .padding(25)
      .backgroundColor('#FFFFFF')
      .borderRadius(20);
    }
  }

  @Builder
  DetailRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor('#666')
        .width(80);
      Text(value)
        .fontSize(14)
        .fontColor('#333')
        .layoutWeight(1);
    }
    .width('100%');
  }

  // 领养人选择弹窗内容
  @Builder
  AdoptDialogContent() {
    if (this.selectedPet) {
      Column() {
        Text('选择领养人')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .margin({ bottom: 20 });

        if (this.users.length === 0) {
          Text('暂无领养人数据')
            .fontSize(14)
            .fontColor('#999')
            .margin({ top: 30, bottom: 30 });
        } else {
          List({ space: 10 }) {
            ForEach(this.users, (user: User) => {
              ListItem() {
                Row() {
                  Column() {
                    Text(user.name)
                      .fontSize(16)
                      .fontColor('#333')
                      .fontWeight(FontWeight.Medium);
                    Text(user.phone)
                      .fontSize(12)
                      .fontColor('#999')
                      .margin({ top: 3 });
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1);

                  if (this.selectedPet!.ownerId === user.id) {
                    Text('当前')
                      .fontSize(12)
                      .fontColor('#4CAF50')
                      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                      .border({ width: 1, color: '#4CAF50', radius: 10 });
                  }
                }
                .width('100%')
                .padding(15)
                .backgroundColor(this.selectedPet!.ownerId === user.id ? '#E8F5E9' : '#F5F5F5')
                .borderRadius(10)
                .onClick(async () => {
                  await this.setAdopter(user);
                });
              }
            }, (user: User) => user.id.toString());
          }
          .width('100%')
          .height(300)
          .margin({ bottom: 20 });
        }

        Button('返回')
          .width('100%')
          .height(45)
          .fontSize(16)
          .backgroundColor('#999')
          .borderRadius(10)
          .onClick(() => {
            this.currentDialog = 'detail';
          });
      }
      .width('90%')
      .padding(25)
      .backgroundColor('#FFFFFF')
      .borderRadius(20);
    }
  }

  async setAdopter(user: User) {
    try {
      if (this.selectedPet) {
        this.selectedPet.ownerId = user.id;
        this.selectedPet.adoptionStatus = 'owned';
        const rows = await savePet(this.selectedPet);
        if (rows > 0) {
          await promptAction.showDialog({ 
            title: '设置成功', 
            message: `已将 ${this.selectedPet.name} 的领养人设为 ${user.name}`, 
            buttons: [{ text: '确定', color: '#4CAF50' }] 
          });
          this.currentDialog = null;
          await this.loadData();
        }
      }
    } catch (err) {
      console.error('[PetManagePage] setAdopter error:', JSON.stringify(err));
      await promptAction.showDialog({ 
        title: '设置失败', 
        message: '设置领养人时出现错误', 
        buttons: [{ text: '确定', color: '#F44336' }] 
      });
    }
  }

  async cancelAdoption() {
    try {
      if (this.selectedPet) {
        const confirm = await promptAction.showDialog({ 
          title: '确认取消', 
          message: `确定要取消 ${this.selectedPet.name} 的领养吗？`, 
          buttons: [
            { text: '取消', color: '#999' },
            { text: '确定', color: '#FF9800' }
          ] 
        });
        
        if (confirm.index === 1) {
          this.selectedPet.ownerId = 0;
          this.selectedPet.adoptionStatus = 'available';
          const rows = await savePet(this.selectedPet);
          if (rows > 0) {
            await promptAction.showDialog({ 
              title: '取消成功', 
              message: `${this.selectedPet.name} 已恢复为待领养状态`, 
              buttons: [{ text: '确定', color: '#4CAF50' }] 
            });
            this.currentDialog = null;
            await this.loadData();
          }
        }
      }
    } catch (err) {
      console.error('[PetManagePage] cancelAdoption error:', JSON.stringify(err));
    }
  }

  async deletePet() {
    try {
      if (this.selectedPet) {
        const confirm = await promptAction.showDialog({ 
          title: '确认删除', 
          message: `确定要删除 ${this.selectedPet.name} 吗？此操作不可恢复！`, 
          buttons: [
            { text: '取消', color: '#999' },
            { text: '删除', color: '#F44336' }
          ] 
        });
        
        if (confirm.index === 1) {
          const rows = await removePet(this.selectedPet.id);
          if (rows > 0) {
            await promptAction.showDialog({ 
              title: '删除成功', 
              message: `${this.selectedPet.name} 已删除`, 
              buttons: [{ text: '确定', color: '#4CAF50' }] 
            });
            this.currentDialog = null;
            await this.loadData();
          }
        }
      }
    } catch (err) {
      console.error('[PetManagePage] deletePet error:', JSON.stringify(err));
      await promptAction.showDialog({ 
        title: '删除失败', 
        message: '删除宠物时出现错误', 
        buttons: [{ text: '确定', color: '#F44336' }] 
      });
    }
  }
}
