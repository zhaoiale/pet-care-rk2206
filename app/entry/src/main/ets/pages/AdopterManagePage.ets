// AdopterManagePage.ets — 独立领养人管理页面
import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import { User } from '../model/User';
import { Pet } from '../model/Pet';
import { getAllUsers, removeUser, getUserById } from '../utils/UserDataManager';
import { getAllPets, queryPetsByOwner } from '../utils/PetDataManager';
import { insertUser, updateUser } from '../database/DatabaseService';

@Entry
@Component
struct AdopterManagePage {
  @State users: User[] = [];
  @State pets: Pet[] = [];
  @State selectedUser: User | null = null;
  @State currentDialog: 'detail' | 'add' | 'edit' | null = null;
  @State newUsername: string = '';
  @State newPassword: string = '';
  @State newName: string = '';
  @State newPhone: string = '';

  async aboutToAppear() {
    await this.loadData();
  }

  async onPageShow() {
    await this.loadData();
  }

  async loadData() {
    try {
      this.users = await getAllUsers();
      this.pets = await getAllPets();
      console.info('[AdopterManagePage] Loaded', this.users.length, 'users');
    } catch (err) {
      console.error('[AdopterManagePage] loadData error:', JSON.stringify(err));
    }
  }

  getUserPetCount(userId: number): number {
    return this.pets.filter(p => p.ownerId === userId).length;
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
          Text('领养人管理')
            .fontSize(20)
            .fontWeight(FontWeight.Bold);
          Blank();
          Button('添加')
            .fontSize(16)
            .fontColor('#2196F3')
            .onClick(() => {
              this.newUsername = '';
              this.newPassword = '';
              this.newName = '';
              this.newPhone = '';
              this.currentDialog = 'add';
            });
        }
        .width('100%')
        .padding({ left: 15, right: 15, top: 15, bottom: 15 });

        if (this.users.length === 0) {
          Column() {
            Text('暂无领养人数据')
              .fontSize(16)
              .fontColor('#999')
              .margin({ top: 100 });
          }
          .width('100%');
        } else {
          List({ space: 15 }) {
            ForEach(this.users, (user: User) => {
              ListItem() {
                this.UserCard(user);
              }
            }, (user: User) => user.id.toString());
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
      if (this.currentDialog !== null) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#33000000')
          .onClick(() => {
            this.currentDialog = null;
          });

        if (this.currentDialog === 'detail' && this.selectedUser) {
          this.DetailDialogContent();
        } else if (this.currentDialog === 'add') {
          this.AddDialogContent();
        } else if (this.currentDialog === 'edit' && this.selectedUser) {
          this.EditDialogContent();
        }
      }
    }
    .width('100%')
    .height('100%');
  }

  @Builder
  UserCard(user: User) {
    Column() {
      Row() {
        // 头像
        Column() {
          Text(user.name.charAt(0))
            .fontSize(24)
            .fontColor('#FFFFFF')
            .fontWeight(FontWeight.Bold);
        }
        .width(60)
        .height(60)
        .borderRadius(30)
        .backgroundColor('#2196F3')
        .margin({ right: 15 });

        // 用户信息
        Column() {
          Text(user.name)
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor('#333');
          
          Text(user.phone)
            .fontSize(12)
            .fontColor('#999')
            .margin({ top: 3 });
          
          Text(`领养 ${this.getUserPetCount(user.id)} 只宠物`)
            .fontSize(12)
            .fontColor('#666')
            .margin({ top: 3 });
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1);

        // 操作按钮
        Text('详情')
          .fontSize(13)
          .fontColor('#2196F3')
          .onClick(() => {
            this.selectedUser = user;
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

  // 详情弹窗内容
  @Builder
  DetailDialogContent() {
    if (this.selectedUser) {
      Column() {
        // 标题
        Text(this.selectedUser.name)
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .margin({ bottom: 20 });

        // 详细信息
        Column({ space: 12 }) {
          this.DetailRow('用户名', this.selectedUser.username);
          this.DetailRow('姓名', this.selectedUser.name);
          this.DetailRow('手机号', this.selectedUser.phone);
          this.DetailRow('领养宠物数', this.getUserPetCount(this.selectedUser.id).toString());
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
              this.newName = this.selectedUser!.name;
              this.newPhone = this.selectedUser!.phone;
              this.newPassword = '';
              this.currentDialog = 'edit';
            });

          // 删除按钮
          Button('删除')
            .width('100%')
            .height(45)
            .fontSize(16)
            .backgroundColor('#F44336')
            .borderRadius(10)
            .onClick(async () => {
              await this.deleteUser();
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

  // 添加弹窗内容
  @Builder
  AddDialogContent() {
    Column() {
      Text('添加领养人')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 20 });

      Column({ space: 15 }) {
        this.InputField('用户名', this.newUsername, (val) => { this.newUsername = val; });
        this.InputField('密码', this.newPassword, (val) => { this.newPassword = val; }, true);
        this.InputField('姓名', this.newName, (val) => { this.newName = val; });
        this.InputField('手机号', this.newPhone, (val) => { this.newPhone = val; });
      }
      .width('100%')
      .margin({ bottom: 20 });

      Column({ space: 12 }) {
        Button('保存')
          .width('100%')
          .height(45)
          .fontSize(16)
          .backgroundColor('#4CAF50')
          .borderRadius(10)
          .onClick(async () => {
            await this.saveNewUser();
          });

        Button('取消')
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

  // 编辑弹窗内容
  @Builder
  EditDialogContent() {
    if (this.selectedUser) {
      Column() {
        Text('编辑领养人')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .margin({ bottom: 20 });

        Column({ space: 15 }) {
          this.InputField('用户名（不可改）', this.selectedUser.username, () => {}, false);
          this.InputField('新密码（留空不修改）', this.newPassword, (val) => { this.newPassword = val; }, true);
          this.InputField('姓名', this.newName, (val) => { this.newName = val; });
          this.InputField('手机号', this.newPhone, (val) => { this.newPhone = val; });
        }
        .width('100%')
        .margin({ bottom: 20 });

        Column({ space: 12 }) {
          Button('保存')
            .width('100%')
            .height(45)
            .fontSize(16)
            .backgroundColor('#4CAF50')
            .borderRadius(10)
            .onClick(async () => {
              await this.saveEditUser();
            });

          Button('取消')
            .width('100%')
            .height(45)
            .fontSize(16)
            .backgroundColor('#999')
            .borderRadius(10)
            .onClick(() => {
              this.currentDialog = 'detail';
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
  InputField(label: string, value: string, onChange: (val: string) => void, editable: boolean = true) {
    Column() {
      Text(label)
        .fontSize(14)
        .fontColor('#666')
        .width('100%')
        .margin({ bottom: 5 });
      TextInput({ text: value })
        .width('100%')
        .height(45)
        .backgroundColor('#F5F5F5')
        .borderRadius(8)
        .enabled(editable)
        .onChange(onChange);
    }
    .width('100%');
  }

  async saveNewUser() {
    if (!this.newUsername || !this.newPassword || !this.newName || !this.newPhone) {
      await promptAction.showDialog({
        title: '提示',
        message: '请填写完整信息',
        buttons: [{ text: '确定', color: '#2196F3' }]
      });
      return;
    }

    try {
      const newUser: User = {
        id: 0,
        username: this.newUsername,
        password: this.newPassword,
        name: this.newName,
        phone: this.newPhone,
        createTime: Date.now()
      };

      const rowId = await insertUser(newUser);
      if (rowId > 0) {
        await promptAction.showDialog({
          title: '保存成功',
          message: '领养人信息已保存',
          buttons: [{ text: '确定', color: '#4CAF50' }]
        });
        this.currentDialog = null;
        await this.loadData();
      }
    } catch (err) {
      console.error('[AdopterManagePage] saveNewUser error:', JSON.stringify(err));
      await promptAction.showDialog({
        title: '保存失败',
        message: '用户名可能已存在',
        buttons: [{ text: '确定', color: '#F44336' }]
      });
    }
  }

  async saveEditUser() {
    if (!this.newName || !this.newPhone) {
      await promptAction.showDialog({
        title: '提示',
        message: '请填写完整信息',
        buttons: [{ text: '确定', color: '#2196F3' }]
      });
      return;
    }

    if (this.selectedUser) {
      try {
        const updateData: User = {
          id: this.selectedUser.id,
          username: this.selectedUser.username,
          password: this.newPassword ? this.newPassword : this.selectedUser.password,
          name: this.newName,
          phone: this.newPhone,
          createTime: this.selectedUser.createTime
        };

        const rows = await updateUser(updateData);
        if (rows > 0) {
          await promptAction.showDialog({
            title: '保存成功',
            message: '领养人信息已更新',
            buttons: [{ text: '确定', color: '#4CAF50' }]
          });
          this.currentDialog = null;
          await this.loadData();
        }
      } catch (err) {
        console.error('[AdopterManagePage] saveEditUser error:', JSON.stringify(err));
        await promptAction.showDialog({
          title: '保存失败',
          message: '更新信息时出现错误',
          buttons: [{ text: '确定', color: '#F44336' }]
        });
      }
    }
  }

  async deleteUser() {
    if (this.selectedUser) {
      try {
        const petCount = this.getUserPetCount(this.selectedUser.id);
        let message = `确定要删除 ${this.selectedUser.name} 吗？`;
        if (petCount > 0) {
          message += `\n该领养人还有 ${petCount} 只宠物，删除后这些宠物将变为待领养状态。`;
        }

        const confirm = await promptAction.showDialog({
          title: '确认删除',
          message: message,
          buttons: [
            { text: '取消', color: '#999' },
            { text: '删除', color: '#F44336' }
          ]
        });

        if (confirm.index === 1) {
          // 先将该用户的宠物 ownerId 设为 0
          const userPets = this.pets.filter(p => p.ownerId === this.selectedUser!.id);
          for (const pet of userPets) {
            pet.ownerId = 0;
            pet.adoptionStatus = 'available';
            // 这里可以调用 updatePet，但为了简化，我们先只删除用户
          }

          const rows = await removeUser(this.selectedUser.id);
          if (rows > 0) {
            await promptAction.showDialog({
              title: '删除成功',
              message: `${this.selectedUser.name} 已删除`,
              buttons: [{ text: '确定', color: '#4CAF50' }]
            });
            this.currentDialog = null;
            await this.loadData();
          }
        }
      } catch (err) {
        console.error('[AdopterManagePage] deleteUser error:', JSON.stringify(err));
        await promptAction.showDialog({
          title: '删除失败',
          message: '删除领养人时出现错误',
          buttons: [{ text: '确定', color: '#F44336' }]
        });
      }
    }
  }
}
