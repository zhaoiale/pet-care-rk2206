// LoginPage.ets — 登录/注册页面（UI 优化版）
import router from '@ohos.router';
import { registerUser, loginUser, isLoggedIn, getCurrentUser } from '../utils/UserDataManager';
import { ensureDefaultPet } from '../utils/PetDataManager';
import { Theme } from '../common/Theme';

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
    if (isLoggedIn()) {
      try {
        const user = await getCurrentUser();
        if (user !== null) {
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

  // 带图标的输入框
  @Builder
  IconInput(placeholder: string, icon: Resource, text: string, isPassword: boolean,
    onChange: (v: string) => void, inputType?: InputType) {
    Row() {
      Image(icon)
        .width(20)
        .height(20)
        .fillColor(Theme.TEXT_TERTIARY)
        .margin({ right: 10 });
      TextInput({ text: text, placeholder: placeholder })
        .type(isPassword ? InputType.Password : (inputType ?? InputType.Normal))
        .layoutWeight(1)
        .height(48)
        .backgroundColor(Color.Transparent)
        .placeholderColor(Theme.TEXT_TERTIARY)
        .fontSize(15)
        .onChange(onChange);
    }
    .width('100%')
    .height(52)
    .padding({ left: 16, right: 16 })
    .backgroundColor(Theme.CARD_SOFT)
    .borderRadius(Theme.RADIUS_MD)
  }

  build() {
    Scroll() {
      Column() {
        // 品牌区
        Column() {
          Image($rawfile('image/foreground.png'))
            .width(84)
            .height(84)
            .borderRadius(22)
            .backgroundColor(Theme.PRIMARY_SOFT)
            .margin({ top: 56, bottom: 16 });

          Text('智宠管家')
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.TEXT_PRIMARY);

          Text(this.isLoginMode ? '欢迎回来，请登录您的账户' : '创建新账户，开启宠物守护')
            .fontSize(13)
            .fontColor(Theme.TEXT_TERTIARY)
            .margin({ top: 6 });
        }
        .margin({ bottom: 36 });

        // 表单卡片
        Column({ space: 14 }) {
          this.IconInput('请输入用户名', $rawfile('image/ic_username.svg'),
            this.username, false, (v: string) => { this.username = v; });

          this.IconInput('请输入密码', $rawfile('image/ic_lock.svg'),
            this.password, true, (v: string) => { this.password = v; });

          if (!this.isLoginMode) {
            this.IconInput('请再次输入密码', $rawfile('image/ic_lock.svg'),
              this.confirmPassword, true, (v: string) => { this.confirmPassword = v; });

            this.IconInput('请输入您的姓名', $rawfile('image/ic_user.svg'),
              this.name, false, (v: string) => { this.name = v; });

            this.IconInput('请输入手机号', $rawfile('image/ic_phone.svg'),
              this.phone, false, (v: string) => { this.phone = v; }, InputType.PhoneNumber);
          }

          // 提交按钮
          Button(this.isLoginMode ? '登 录' : '注 册')
            .width('100%')
            .height(52)
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .backgroundColor(Theme.PRIMARY)
            .borderRadius(Theme.RADIUS_PILL)
            .enabled(!this.isLoading)
            .margin({ top: 8 })
            .onClick(() => this.handleSubmit());

          // 忘记密码
          if (this.isLoginMode) {
            Text('忘记密码？')
              .fontSize(13)
              .fontColor(Theme.PRIMARY)
              .margin({ top: 4 })
              .onClick(() => {
                router.pushUrl({ url: 'pages/ResetPasswordPage' });
              });
          }

          // 切换登录/注册
          Text(this.isLoginMode ? '还没有账号？去注册' : '已有账号？去登录')
            .fontSize(13)
            .fontColor(Theme.TEXT_SECONDARY)
            .margin({ top: 12, bottom: 8 })
            .onClick(() => {
              this.isLoginMode = !this.isLoginMode;
              this.password = '';
              this.confirmPassword = '';
            });
        }
        .width('86%')
        .padding(20)
        .backgroundColor(Theme.CARD)
        .borderRadius(Theme.RADIUS_XL)
        .shadow({
          radius: 16,
          color: '#12000000',
          offsetX: 0,
          offsetY: 4
        });
      }
      .width('100%');
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.BG)
    .scrollBar(BarState.Off);
  }
}
