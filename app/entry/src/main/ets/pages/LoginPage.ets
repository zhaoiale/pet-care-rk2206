// LoginPage.ets — 登录/注册页面
import router from '@ohos.router';
import { registerUser, loginUser, isLoggedIn, getCurrentUser } from '../utils/UserDataManager';
import { ensureDefaultPet } from '../utils/PetDataManager';

@Entry
@Component
struct LoginPage {
  @State isLoginMode: boolean = true;
  @State username: string = '';
  @State password: string = '';
  @State confirmPassword: string = '';
  @State name: string = '';
  @State phone: string = '';
  @State isLoading: boolean = false;

  async aboutToAppear() {
    // 检查是否已登录
    if (isLoggedIn()) {
      try {
        const user = await getCurrentUser();
        if (user !== null) {
          // 初始化默认宠物
          await ensureDefaultPet();
          router.replaceUrl({ url: 'pages/Index' });
        }
      } catch (err) {
        console.error('[LoginPage] aboutToAppear error: ' + JSON.stringify(err));
      }
    }
  }

  async handleSubmit() {
    if (this.username.trim() === '' || this.password.trim() === '') {
      AlertDialog.show({ title: '提示', message: '用户名和密码不能为空' });
      return;
    }

    this.isLoading = true;

    if (this.isLoginMode) {
      // 登录
      const user = await loginUser(this.username.trim(), this.password.trim());
      if (user !== null) {
        await ensureDefaultPet();
        AlertDialog.show({
          title: '登录成功',
          message: `欢迎回来，${user.name}`,
          confirm: {
            value: '确定',
            action: () => router.replaceUrl({ url: 'pages/Index' })
          }
        });
      } else {
        AlertDialog.show({ title: '登录失败', message: '用户名或密码错误' });
      }
    } else {
      // 注册
      if (this.password !== this.confirmPassword) {
        AlertDialog.show({ title: '提示', message: '两次输入的密码不一致' });
        this.isLoading = false;
        return;
      }
      if (this.name.trim() === '' || this.phone.trim() === '') {
        AlertDialog.show({ title: '提示', message: '姓名和手机号不能为空' });
        this.isLoading = false;
        return;
      }

      const userId = await registerUser(
        this.username.trim(),
        this.password.trim(),
        this.name.trim(),
        this.phone.trim()
      );
      if (userId > 0) {
        AlertDialog.show({
          title: '注册成功',
          message: '请登录您的账户',
          confirm: {
            value: '去登录',
            action: () => {
              this.isLoginMode = true;
              this.password = '';
              this.confirmPassword = '';
            }
          }
        });
      } else {
        AlertDialog.show({ title: '注册失败', message: '用户名已存在，请更换用户名' });
      }
    }

    this.isLoading = false;
  }

  build() {
    Column() {
      // Logo 和标题
      Column() {
        Image($r('app.media.startIcon'))
          .width(100)
          .height(100)
          .objectFit(ImageFit.Contain)
        Text('宠物关爱')
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .margin({ top: 10 })
      }
      .margin({ top: 60, bottom: 40 })

      // 表单
      Column() {
        // 用户名
        Column() {
          Text('用户名')
            .fontSize(14)
            .fontColor('#666')
            .width('100%')
            .margin({ bottom: 5 })
          TextInput({ text: this.username, placeholder: '请输入用户名' })
            .width('100%')
            .height(45)
            .backgroundColor('#F5F5F5')
            .borderRadius(8)
            .onChange((value: string) => { this.username = value; })
        }
        .width('100%')
        .margin({ bottom: 15 })

        // 密码
        Column() {
          Text('密码')
            .fontSize(14)
            .fontColor('#666')
            .width('100%')
            .margin({ bottom: 5 })
          TextInput({ text: this.password, placeholder: '请输入密码' })
            .type(InputType.Password)
            .width('100%')
            .height(45)
            .backgroundColor('#F5F5F5')
            .borderRadius(8)
            .onChange((value: string) => { this.password = value; })
        }
        .width('100%')
        .margin({ bottom: 15 })

        // 注册时显示的字段
        if (!this.isLoginMode) {
          Column() {
            Text('确认密码')
              .fontSize(14)
              .fontColor('#666')
              .width('100%')
              .margin({ bottom: 5 })
            TextInput({ text: this.confirmPassword, placeholder: '请再次输入密码' })
              .type(InputType.Password)
              .width('100%')
              .height(45)
              .backgroundColor('#F5F5F5')
              .borderRadius(8)
              .onChange((value: string) => { this.confirmPassword = value; })
          }
          .width('100%')
          .margin({ bottom: 15 })

          Column() {
            Text('姓名')
              .fontSize(14)
              .fontColor('#666')
              .width('100%')
              .margin({ bottom: 5 })
            TextInput({ text: this.name, placeholder: '请输入您的姓名' })
              .width('100%')
              .height(45)
              .backgroundColor('#F5F5F5')
              .borderRadius(8)
              .onChange((value: string) => { this.name = value; })
          }
          .width('100%')
          .margin({ bottom: 15 })

          Column() {
            Text('手机号')
              .fontSize(14)
              .fontColor('#666')
              .width('100%')
              .margin({ bottom: 5 })
            TextInput({ text: this.phone, placeholder: '请输入手机号' })
              .type(InputType.PhoneNumber)
              .width('100%')
              .height(45)
              .backgroundColor('#F5F5F5')
              .borderRadius(8)
              .onChange((value: string) => { this.phone = value; })
          }
          .width('100%')
          .margin({ bottom: 15 })
        }

        // 提交按钮
        Button(this.isLoginMode ? '登录' : '注册')
          .width('100%')
          .height(50)
          .fontSize(18)
          .backgroundColor('#2196F3')
          .borderRadius(25)
          .enabled(!this.isLoading)
          .onClick(() => this.handleSubmit())
          .margin({ top: 20 })

        // 忘记密码（仅登录模式显示）
        if (this.isLoginMode) {
          Text('忘记密码？')
            .fontSize(14)
            .fontColor('#FF9800')
            .margin({ top: 15 })
            .onClick(() => {
              router.pushUrl({ url: 'pages/ResetPasswordPage' });
            });
        }

        // 切换登录/注册
        Text(this.isLoginMode ? '还没有账号？去注册' : '已有账号？去登录')
          .fontSize(14)
          .fontColor('#2196F3')
          .margin({ top: 20 })
          .onClick(() => {
            this.isLoginMode = !this.isLoginMode;
            this.password = '';
            this.confirmPassword = '';
          })
      }
      .width('85%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
  }
}
