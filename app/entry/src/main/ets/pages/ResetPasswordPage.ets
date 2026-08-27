// ResetPasswordPage.ets — 密码重置页面
import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import { getUserByUsername, getUserById, updateUser } from '../utils/UserDataManager';
import { User } from '../model/User';

@Entry
@Component
struct ResetPasswordPage {
  @State step: number = 1;  // 1: 输入用户名, 2: 输入新密码, 3: 完成
  @State username: string = '';
  @State verifyCode: string = '';
  @State newPassword: string = '';
  @State confirmPassword: string = '';
  @State currentUser: User | null = null;
  @State userPhone: string = '';
  @State generatedCode: string = '';

  async aboutToAppear() {
    // 从 URL 参数获取用户名
    const params = router.getParams() as Object;
    if (params) {
      const usernameParam = (params as Record<string, string>)['username'];
      if (usernameParam) {
        this.username = usernameParam;
        await this.checkUser();
      }
    }
  }

  async checkUser() {
    if (this.username.trim() === '') {
      await promptAction.showDialog({
        title: '提示',
        message: '请输入用户名',
        buttons: [{ text: '确定', color: '#2196F3' }]
      });
      return;
    }

    const user = await getUserByUsername(this.username.trim());
    if (user !== null) {
      this.currentUser = user;
      this.userPhone = user.phone;
      // 生成4位验证码
      this.generatedCode = Math.floor(1000 + Math.random() * 9000).toString();
      this.step = 2;
      
      await promptAction.showDialog({
        title: '验证码提示',
        message: `您的验证码是：${this.generatedCode}\n\n（实际应用中会发送到手机：${this.userPhone.replace(this.userPhone.substring(3, 7), '****')}）`,
        buttons: [{ text: '确定', color: '#2196F3' }]
      });
    } else {
      await promptAction.showDialog({
        title: '用户不存在',
        message: '未找到该用户名，请检查输入是否正确',
        buttons: [{ text: '确定', color: '#2196F3' }]
      });
    }
  }

  async verifyAndReset() {
    if (this.verifyCode.trim() === '') {
      await promptAction.showDialog({
        title: '提示',
        message: '请输入验证码',
        buttons: [{ text: '确定', color: '#2196F3' }]
      });
      return;
    }

    if (this.verifyCode.trim() !== this.generatedCode) {
      await promptAction.showDialog({
        title: '验证码错误',
        message: '您输入的验证码不正确，请重新输入',
        buttons: [{ text: '确定', color: '#2196F3' }]
      });
      return;
    }

    if (this.newPassword.trim() === '') {
      await promptAction.showDialog({
        title: '提示',
        message: '请输入新密码',
        buttons: [{ text: '确定', color: '#2196F3' }]
      });
      return;
    }

    if (this.newPassword.length < 6) {
      await promptAction.showDialog({
        title: '密码太短',
        message: '密码至少需要6个字符',
        buttons: [{ text: '确定', color: '#2196F3' }]
      });
      return;
    }

    if (this.newPassword !== this.confirmPassword) {
      await promptAction.showDialog({
        title: '密码不一致',
        message: '两次输入的密码不一致，请重新输入',
        buttons: [{ text: '确定', color: '#2196F3' }]
      });
      return;
    }

    try {
      if (this.currentUser) {
        this.currentUser.password = this.newPassword;
        const rows = await updateUser(this.currentUser);
        if (rows > 0) {
          this.step = 3;
        } else {
          await promptAction.showDialog({
            title: '修改失败',
            message: '密码修改失败，请稍后重试',
            buttons: [{ text: '确定', color: '#F44336' }]
          });
        }
      }
    } catch (err) {
      console.error('[ResetPasswordPage] error:', JSON.stringify(err as Object));
      await promptAction.showDialog({
        title: '修改失败',
        message: '密码修改失败，请稍后重试',
        buttons: [{ text: '确定', color: '#F44336' }]
      });
    }
  }

  build() {
    Column() {
      // 顶部导航
      Row() {
        Button('返回')
          .fontSize(16)
          .fontColor('#2196F3')
          .onClick(() => {
            if (this.step > 1 && this.step < 3) {
              this.step = 1;
              this.verifyCode = '';
              this.newPassword = '';
              this.confirmPassword = '';
            } else {
              router.back();
            }
          });
        Blank();
        Text('找回密码')
          .fontSize(20)
          .fontWeight(FontWeight.Bold);
        Blank();
        Text('').width(50);
      }
      .width('100%')
      .padding({ left: 15, right: 15, top: 15, bottom: 15 });

      if (this.step === 1) {
        // 步骤1: 输入用户名
        Column({ space: 20 }) {
          Text('请输入您的用户名')
            .fontSize(16)
            .fontColor('#666')
            .margin({ top: 30 });

          Column() {
            Text('用户名')
              .fontSize(14)
              .fontColor('#666')
              .width('100%')
              .margin({ bottom: 5 });
            TextInput({ text: this.username, placeholder: '请输入用户名' })
              .width('100%')
              .height(45)
              .backgroundColor('#F5F5F5')
              .borderRadius(8)
              .onChange((value: string) => { this.username = value; });
          }
          .width('85%')
          .margin({ top: 20 });

          Button('下一步')
            .width('85%')
            .height(50)
            .fontSize(18)
            .backgroundColor('#2196F3')
            .borderRadius(25)
            .margin({ top: 30 })
            .onClick(() => this.checkUser());

          Text('验证通过后将发送验证码到您的注册手机号')
            .fontSize(12)
            .fontColor('#999')
            .margin({ top: 20 });
        }
        .width('100%');
      }

      if (this.step === 2) {
        // 步骤2: 输入验证码和新密码
        Column({ space: 20 }) {
          Text(`验证码已发送至 ${this.userPhone.replace(this.userPhone.substring(3, 7), '****')}`)
            .fontSize(14)
            .fontColor('#666')
            .margin({ top: 30 });

          Column() {
            Text('验证码')
              .fontSize(14)
              .fontColor('#666')
              .width('100%')
              .margin({ bottom: 5 });
            TextInput({ text: this.verifyCode, placeholder: '请输入4位验证码' })
              .type(InputType.Number)
              .width('100%')
              .height(45)
              .backgroundColor('#F5F5F5')
              .borderRadius(8)
              .onChange((value: string) => { this.verifyCode = value; });
          }
          .width('85%')
          .margin({ top: 20 });

          Column() {
            Text('新密码')
              .fontSize(14)
              .fontColor('#666')
              .width('100%')
              .margin({ bottom: 5 });
            TextInput({ text: this.newPassword, placeholder: '请输入新密码（至少6位）' })
              .type(InputType.Password)
              .width('100%')
              .height(45)
              .backgroundColor('#F5F5F5')
              .borderRadius(8)
              .onChange((value: string) => { this.newPassword = value; });
          }
          .width('85%');

          Column() {
            Text('确认密码')
              .fontSize(14)
              .fontColor('#666')
              .width('100%')
              .margin({ bottom: 5 });
            TextInput({ text: this.confirmPassword, placeholder: '请再次输入新密码' })
              .type(InputType.Password)
              .width('100%')
              .height(45)
              .backgroundColor('#F5F5F5')
              .borderRadius(8)
              .onChange((value: string) => { this.confirmPassword = value; });
          }
          .width('85%');

          Button('重置密码')
            .width('85%')
            .height(50)
            .fontSize(18)
            .backgroundColor('#4CAF50')
            .borderRadius(25)
            .margin({ top: 30 })
            .onClick(() => this.verifyAndReset());

          Button('重新获取验证码')
            .width('85%')
            .height(45)
            .fontSize(16)
            .backgroundColor('#F5F5F5')
            .fontColor('#2196F3')
            .borderRadius(25)
            .margin({ top: 15 })
            .onClick(async () => {
              this.generatedCode = Math.floor(1000 + Math.random() * 9000).toString();
              await promptAction.showDialog({
                title: '新验证码',
                message: `您的新验证码是：${this.generatedCode}`,
                buttons: [{ text: '确定', color: '#2196F3' }]
              });
            });
        }
        .width('100%');
      }

      if (this.step === 3) {
        // 步骤3: 完成
        Column() {
          Column() {
            Text('✓')
              .fontSize(80)
              .fontColor('#4CAF50')
              .margin({ top: 80 });
          }
          .width('100%');

          Text('密码重置成功')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor('#333')
            .margin({ top: 30 });

          Text('请使用新密码登录')
            .fontSize(14)
            .fontColor('#666')
            .margin({ top: 10 });

          Button('返回登录')
            .width('85%')
            .height(50)
            .fontSize(18)
            .backgroundColor('#2196F3')
            .borderRadius(25)
            .margin({ top: 50 })
            .onClick(() => {
              router.replaceUrl({ url: 'pages/LoginPage' });
            });
        }
        .width('100%');
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF');
  }
}
