// LandingPage.ets — 应用主入口页面
import router from '@ohos.router';
import { isLoggedIn } from '../utils/UserDataManager';

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
      // 标题区域
      Column() {
        Text('智宠管家')
          .fontSize(36)
          .fontWeight(FontWeight.Bold)
          .fontColor('#2196F3')
          .margin({ top: 60, bottom: 10 });
        
        Text('宠物健康监护与领养管理平台')
          .fontSize(14)
          .fontColor('#999')
          .margin({ bottom: 40 });
      }
      .width('100%');

      // 如果已登录，显示快速进入监控中心按钮
      if (this.isUserLoggedIn) {
        Button('进入监控中心')
          .width('85%')
          .height(60)
          .fontSize(20)
          .backgroundColor('#4CAF50')
          .borderRadius(15)
          .margin({ bottom: 30 })
          .onClick(() => {
            router.replaceUrl({ url: 'pages/Index' });
          });
      }

      // 功能卡片区域
      Column({ space: 20 }) {
        // 宠物信息管理
        this.FeatureCard(
          '宠物信息管理',
          '管理所有宠物档案，查看领养状态',
          '#FF9800',
          '🐾',
          () => {
            router.pushUrl({ url: 'pages/PetManagePage' });
          }
        );

        // 领养人信息管理
        this.FeatureCard(
          '领养人信息管理',
          '管理领养人档案，查看领养关系',
          '#2196F3',
          '👤',
          () => {
            router.pushUrl({ url: 'pages/AdopterManagePage' });
          }
        );

        // 领养人登录
        this.FeatureCard(
          '领养人登录',
          '登录后查看宠物监控数据',
          '#4CAF50',
          '🔐',
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
    .backgroundColor('#F5F5F5');
  }

  @Builder
  FeatureCard(title: string, desc: string, color: string, icon: string, onClick: () => void) {
    Column() {
      Row() {
        Text(icon)
          .fontSize(40)
          .margin({ right: 15 });
        
        Column() {
            Text(title)
              .fontSize(20)
              .fontWeight(FontWeight.Medium)
              .fontColor('#333');
            
            Text(desc)
              .fontSize(12)
              .fontColor('#999')
              .margin({ top: 5 });
          }
          .alignItems(HorizontalAlign.Start);
        
        Blank();
        
        Text('>')
          .fontSize(24)
          .fontColor('#CCC');
      }
      .width('100%')
      .padding(20);
    }
    .width('100%')
    .backgroundColor('#FFFFFF')
    .borderRadius(15)
    .shadow({
      radius: 10,
      color: '#1F000000',
      offsetX: 0,
      offsetY: 2
    })
    .onClick(onClick);
  }
}
