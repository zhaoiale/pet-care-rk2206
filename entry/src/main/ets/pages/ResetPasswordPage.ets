// ResetPasswordPage.ets — 密码重置页面（UI 优化版）
import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import { getUserByUsername, getUserById, updateUser } from '../utils/UserDataManager';
import { User } from '../model/User';
import { Theme } from '../common/Theme';

@Entry
@Component
struct ResetPasswordPage {
  @State step: number = 1;
  @State username: string = '';
  @State verifyCode: string = '';
  @State newPassword: string = '';
  @State confirmPassword: string = '';
  @State currentUser: User | null = null;
  @State userPhone: string = '';
  @State generatedCode: string = '';

  async aboutToAppear() {
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
        title: '提示', message: '请输入用户名',
        buttons: [{ text: '确定', color: Theme.PRIMARY }]
      });
      return;
    }
    const user = await getUserByUsername(this.username.trim());
    if (user !== null) {
      this.currentUser = user;
      this.userPhone = user.phone;
      this.generatedCode = Math.floor(1000 + Math.random() * 9000).toString();
      this.step = 2;
      await promptAction.showDialog({
        title: '验证码提示',
        message: `您的验证码是：${this.generatedCode}\n\n（实际应用中会发送到手机：${this.userPhone.replace(this.userPhone.substring(3, 7), '****')}）`,
        buttons: [{ text: '确定', color: Theme.PRIMARY }]
      });
    } else {
      await promptAction.showDialog({
        title: '用户不存在', message: '未找到该用户名，请检查输入是否正确',
        buttons: [{ text: '确定', color: Theme.PRIMARY }]
      });
    }
  }

  async verifyAndReset() {
    if (this.verifyCode.trim() === '') {
      await promptAction.showDialog({ title: '提示', message: '请输入验证码',
        buttons: [{ text: '确定', color: Theme.PRIMARY }] }); return;
    }
    if (this.verifyCode.trim() !== this.generatedCode) {
      await promptAction.showDialog({ title: '验证码错误', message: '您输入的验证码不正确，请重新输入',
        buttons: [{ text: '确定', color: Theme.PRIMARY }] }); return;
    }
    if (this.newPassword.trim() === '') {
      await promptAction.showDialog({ title: '提示', message: '请输入新密码',
        buttons: [{ text: '确定', color: Theme.PRIMARY }] }); return;
    }
    if (this.newPassword.length < 6) {
      await promptAction.showDialog({ title: '密码太短', message: '密码至少需要6个字符',
        buttons: [{ text: '确定', color: Theme.PRIMARY }] }); return;
    }
    if (this.newPassword !== this.confirmPassword) {
      await promptAction.showDialog({ title: '密码不一致', message: '两次输入的密码不一致，请重新输入',
        buttons: [{ text: '确定', color: Theme.PRIMARY }] }); return;
    }
    try {
      if (this.currentUser) {
        this.currentUser.password = this.newPassword;
        const rows = await updateUser(this.currentUser);
        if (rows > 0) { this.step = 3; }
        else {
          await promptAction.showDialog({ title: '修改失败', message: '密码修改失败，请稍后重试',
            buttons: [{ text: '确定', color: Theme.DANGER }] });
        }
      }
    } catch (err) {
      console.error('[ResetPasswordPage] error:', JSON.stringify(err as Object));
      await promptAction.showDialog({ title: '修改失败', message: '密码修改失败，请稍后重试',
        buttons: [{ text: '确定', color: Theme.DANGER }] });
    }
  }

  @Builder
  IconInput(placeholder: string, icon: Resource, text: string, isPassword: boolean,
    onChange: (v: string) => void, inputType?: InputType) {
    Row() {
      Image(icon).width(20).height(20).fillColor(Theme.TEXT_TERTIARY).margin({ right: 10 });
      TextInput({ text: text, placeholder: placeholder })
        .type(isPassword ? InputType.Password : (inputType ?? InputType.Normal))
        .layoutWeight(1).height(48).backgroundColor(Color.Transparent)
        .placeholderColor(Theme.TEXT_TERTIARY).fontSize(15).onChange(onChange);
    }
    .width('100%').height(52).padding({ left: 16, right: 16 })
    .backgroundColor(Theme.CARD_SOFT).borderRadius(Theme.RADIUS_MD);
  }

  // 步骤指示器
  @Builder
  StepIndicator() {
    Row({ space: 8 }) {
      this.StepDot(1, '验证身份');
      Text('—').fontColor(Theme.BORDER).fontSize(12);
      this.StepDot(2, '重置密码');
      Text('—').fontColor(Theme.BORDER).fontSize(12);
      this.StepDot(3, '完成');
    }
    .width('100%').justifyContent(FlexAlign.Center).margin({ bottom: 28, top: 8 });
  }

  @Builder
  StepDot(step: number, label: string) {
    Column() {
      Text(step.toString())
        .width(26).height(26).borderRadius(13)
        .fontSize(13).fontWeight(FontWeight.Medium)
        .textAlign(TextAlign.Center)
        .fontColor(this.step >= step ? Theme.TEXT_WHITE : Theme.TEXT_TERTIARY)
        .backgroundColor(this.step >= step ? Theme.PRIMARY : Theme.BORDER);
      Text(label).fontSize(10).fontColor(Theme.TEXT_TERTIARY).margin({ top: 4 });
    }
  }

  build() {
    Column() {
      // 顶部导航
      Row() {
        Image($rawfile('image/ic_back.svg'))
          .width(22).height(22).fillColor(Theme.TEXT_PRIMARY)
          .onClick(() => {
            if (this.step > 1 && this.step < 3) {
              this.step = 1; this.verifyCode = ''; this.newPassword = ''; this.confirmPassword = '';
            } else { router.back(); }
          });
        Blank();
        Text('找回密码').fontSize(18).fontWeight(FontWeight.Bold).fontColor(Theme.TEXT_PRIMARY);
        Blank();
        Text('').width(22);
      }
      .width('100%').padding({ left: 16, right: 16, top: 16, bottom: 12 });

      this.StepIndicator();

      if (this.step === 1) {
        Column({ space: 16 }) {
          Text('请输入您的用户名').fontSize(15).fontColor(Theme.TEXT_SECONDARY);
          this.IconInput('请输入用户名', $rawfile('image/ic_username.svg'),
            this.username, false, (v: string) => { this.username = v; });
          Button('下一步')
            .width('100%').height(50).fontSize(16).fontWeight(FontWeight.Medium)
            .backgroundColor(Theme.PRIMARY).borderRadius(Theme.RADIUS_PILL).margin({ top: 8 })
            .onClick(() => this.checkUser());
          Text('验证通过后将发送验证码到您的注册手机号')
            .fontSize(11).fontColor(Theme.TEXT_TERTIARY).margin({ top: 4 });
        }
        .width('86%').padding(24).backgroundColor(Theme.CARD)
        .borderRadius(Theme.RADIUS_XL)
        .shadow({ radius: 14, color: '#10000000', offsetX: 0, offsetY: 3 });
      }

      if (this.step === 2) {
        Column({ space: 14 }) {
          Text(`验证码已发送至 ${this.userPhone.replace(this.userPhone.substring(3, 7), '****')}`)
            .fontSize(13).fontColor(Theme.TEXT_SECONDARY);
          this.IconInput('请输入4位验证码', $rawfile('image/ic_check.svg'),
            this.verifyCode, false, (v: string) => { this.verifyCode = v; }, InputType.Number);
          this.IconInput('请输入新密码（至少6位）', $rawfile('image/ic_lock.svg'),
            this.newPassword, true, (v: string) => { this.newPassword = v; });
          this.IconInput('请再次输入新密码', $rawfile('image/ic_lock.svg'),
            this.confirmPassword, true, (v: string) => { this.confirmPassword = v; });
          Button('重置密码')
            .width('100%').height(50).fontSize(16).fontWeight(FontWeight.Medium)
            .backgroundColor(Theme.PRIMARY).borderRadius(Theme.RADIUS_PILL).margin({ top: 6 })
            .onClick(() => this.verifyAndReset());
          Button('重新获取验证码')
            .width('100%').height(44).fontSize(14)
            .backgroundColor(Theme.CARD_SOFT).fontColor(Theme.PRIMARY)
            .borderRadius(Theme.RADIUS_PILL)
            .onClick(async () => {
              this.generatedCode = Math.floor(1000 + Math.random() * 9000).toString();
              await promptAction.showDialog({
                title: '新验证码', message: `您的新验证码是：${this.generatedCode}`,
                buttons: [{ text: '确定', color: Theme.PRIMARY }]
              });
            });
        }
        .width('86%').padding(24).backgroundColor(Theme.CARD)
        .borderRadius(Theme.RADIUS_XL)
        .shadow({ radius: 14, color: '#10000000', offsetX: 0, offsetY: 3 });
      }

      if (this.step === 3) {
        Column() {
          Column() {
            Image($rawfile('image/ic_check.svg'))
              .width(56).height(56).fillColor(Theme.SUCCESS);
          }
          .width(96).height(96).borderRadius(48)
          .backgroundColor(Theme.SUCCESS + '18').margin({ top: 40 });

          Text('密码重置成功').fontSize(22).fontWeight(FontWeight.Bold)
            .fontColor(Theme.TEXT_PRIMARY).margin({ top: 24 });
          Text('请使用新密码登录').fontSize(14).fontColor(Theme.TEXT_TERTIARY).margin({ top: 8 });

          Button('返回登录')
            .width('70%').height(50).fontSize(16).fontWeight(FontWeight.Medium)
            .backgroundColor(Theme.PRIMARY).borderRadius(Theme.RADIUS_PILL).margin({ top: 40 })
            .onClick(() => { router.replaceUrl({ url: 'pages/LoginPage' }); });
        }
        .width('100%');
      }

      Blank();
    }
    .width('100%').height('100%').backgroundColor(Theme.BG);
  }
}
