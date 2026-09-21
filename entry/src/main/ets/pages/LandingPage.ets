// LandingPage.ets — 应用主入口页面（UI 优化版）
import router from '@ohos.router';
import { isLoggedIn } from '../utils/UserDataManager';
import { Theme } from '../common/Theme';

@Entry
@Component
struct LandingPage {
  @State isUserLoggedIn: boolean = false;

  aboutToAppear() {
    this.checkLoginStatus();
  }

  checkLoginStatus() {
    this.isUserLoggedIn = isLoggedIn();
  }

  build() {
    Column() {
      // 顶部品牌区
      Column() {
        // App 图标
        Image($rawfile('image/foreground.png'))
          .width(88)
          .height(88)
          .borderRadius(22)
          .backgroundColor(Theme.PRIMARY_SOFT)
          .margin({ top: 72, bottom: 18 });

        Text('智宠管家')
          .fontSize(34)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.TEXT_PRIMARY)
          .margin({ bottom: 8 });

        Text('宠物健康监护与领养管理平台')
          .fontSize(14)
          .fontColor(Theme.TEXT_TERTIARY)
          .margin({ bottom: 36 });
      }
      .width('100%');

      // 已登录：快速进入
      if (this.isUserLoggedIn) {
        Button('进入监控中心')
          .width('85%')
          .height(54)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .backgroundColor(Theme.PRIMARY)
          .borderRadius(Theme.RADIUS_PILL)
          .margin({ bottom: 28 })
          .onClick(() => {
            router.replaceUrl({ url: 'pages/Index' });
          });
      }

      // 功能卡片
      Column({ space: 14 }) {
        this.FeatureCard(
          '宠物信息管理',
          '管理所有宠物档案，查看领养状态',
          $rawfile('image/tab_pet.svg'),
          Theme.PRIMARY,
          () => {
            router.pushUrl({ url: 'pages/PetManagePage' });
          }
        );

        this.FeatureCard(
          '领养人信息管理',
          '管理领养人档案，查看领养关系',
          $rawfile('image/ic_user.svg'),
          Theme.INFO,
          () => {
            router.pushUrl({ url: 'pages/AdopterManagePage' });
          }
        );

        this.FeatureCard(
          '领养人登录',
          '登录后查看宠物监控数据',
          $rawfile('image/ic_lock.svg'),
          Theme.SUCCESS,
          () => {
            router.pushUrl({ url: 'pages/LoginPage' });
          }
        );
      }
      .width('100%')
      .padding({ left: 20, right: 20 });

      Blank();
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.BG);
  }

  @Builder
  FeatureCard(title: string, desc: string, icon: Resource, tint: string, onClick: () => void) {
    Row() {
      // 图标圆底
      Column() {
        Image(icon)
          .width(26)
          .height(26)
          .fillColor(tint);
      }
      .width(48)
      .height(48)
      .borderRadius(Theme.RADIUS_MD)
      .backgroundColor(tint + '18')
      .margin({ right: 14 });

      Column() {
        Text(title)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.TEXT_PRIMARY);

        Text(desc)
          .fontSize(12)
          .fontColor(Theme.TEXT_TERTIARY)
          .margin({ top: 4 });
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1);

      Image($rawfile('image/ic_arrow_right.svg'))
        .width(18)
        .height(18)
        .fillColor(Theme.TEXT_TERTIARY);
    }
    .width('100%')
    .padding(16)
    .backgroundColor(Theme.CARD)
    .borderRadius(Theme.RADIUS_LG)
    .shadow({
      radius: 12,
      color: '#12000000',
      offsetX: 0,
      offsetY: 3
    })
    .onClick(onClick);
  }
}
