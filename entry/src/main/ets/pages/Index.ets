// Index.ets
import router from '@ohos.router';
import { HomePage } from './HomePage';
import { ComfortPage } from './ComfortPage';
import { FeedingPage } from './FeedingPage';
import { ProfilePage } from './ProfilePage';
import { DashboardPage } from './DashboardPage';
import { VirtualPetPage } from './VirtualPetPage';
import { FloatingPet } from './FloatingPet';
import { ensureDefaultPet } from '../utils/PetDataManager';
import { isLoggedIn } from '../utils/UserDataManager';
import { startMqttService } from '../services/MqttService';
import { getLatestRecord } from '../database/DatabaseService';
import { Theme } from '../common/Theme';

const DATA_UPDATE_KEY: string = 'dataUpdateKey';

// 传感器状态初始化
AppStorage.SetOrCreate('anxietyIndex', 0);
AppStorage.SetOrCreate('temperature', 0);
AppStorage.SetOrCreate('humidity', 0);
AppStorage.SetOrCreate('activityLevel', '--');
AppStorage.SetOrCreate('currentPetId', -1);
AppStorage.SetOrCreate(DATA_UPDATE_KEY, 0);
AppStorage.SetOrCreate('currentTabIndex', 0);

// 应用启动时初始化本地存储
AppStorage.SetOrCreate('isAppReady', false);

@Entry
@Component
struct Index {
  @StorageLink('currentTabIndex') currentTabIndex: number = 0;
  private appTimerId: number = -1;

  async aboutToAppear() {
    // 检查是否登录
    if (!isLoggedIn()) {
      router.replaceUrl({ url: 'pages/LoginPage' });
      return;
    }
    await ensureDefaultPet();
    console.info('[Index] about to start MQTT service...');
    try {
      await startMqttService();
      console.info('[Index] MQTT service started OK');
    } catch (e) {
      console.error('[Index] MQTT start failed: ' + JSON.stringify(e));
    }

    // 启动应用级别的自动刷新
    this.startAppAutoRefresh();
  }

  aboutToDisappear() {
    if (this.appTimerId !== -1) {
      clearInterval(this.appTimerId);
      this.appTimerId = -1;
    }
  }

  startAppAutoRefresh() {
    console.info('[Index] Starting app-level auto-refresh timer');
    this.appTimerId = setInterval(async () => {
      try {
        const latest = await getLatestRecord();
        
        // 只有有真实数据时才更新
        if (latest !== null) {
          console.info('[Index] Found real data, updating UI');
          
          // 更新 AppStorage
          AppStorage.SetOrCreate('anxietyIndex', latest.anxietyLevel);
          AppStorage.SetOrCreate('temperature', latest.temperature);
          AppStorage.SetOrCreate('humidity', latest.humidity);
          
          const activityLevel = latest.anxietyLevel >= 80 ? '焦躁' :
            latest.anxietyLevel <= 20 ? '安静' : '正常';
          AppStorage.SetOrCreate('activityLevel', activityLevel);
          
          // 触发全局刷新信号
          const currentKey = AppStorage.Get<number>(DATA_UPDATE_KEY) ?? 0;
          AppStorage.SetOrCreate(DATA_UPDATE_KEY, currentKey + 1);
          
          console.info('[Index] Data updated: Lv=' + latest.anxietyLevel.toString() + 
            ' T=' + latest.temperature.toString() + 
            ' H=' + latest.humidity.toString());
        } else {
          console.info('[Index] No real data available, skipping update');
        }
        
      } catch (err) {
        console.error('[Index] Auto-refresh error: ' + JSON.stringify(err));
      }
    }, 5000);
    console.info('[Index] Timer started, ID:', this.appTimerId);
  }

  @Builder
  TabBuilder(title: string, index: number, icon: Resource) {
    Column() {
      Image(icon)
        .width(24)
        .height(24)
        .fillColor(this.currentTabIndex === index ? Theme.PRIMARY : Theme.TEXT_TERTIARY)
        .margin({ bottom: 2 })
      Text(title)
        .fontSize(11)
        .fontColor(this.currentTabIndex === index ? Theme.PRIMARY : Theme.TEXT_TERTIARY)
        .fontWeight(this.currentTabIndex === index ? FontWeight.Medium : FontWeight.Normal)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ top: 6, bottom: 4 })
  }

  build() {
    Stack() {
      Tabs({ barPosition: BarPosition.End, index: this.currentTabIndex }) {
        TabContent() {
          HomePage()
        }.tabBar(this.TabBuilder('首页', 0, $rawfile('image/tab_home.svg')))

        TabContent() {
          ComfortPage()
        }.tabBar(this.TabBuilder('安抚', 1, $rawfile('image/tab_comfort.svg')))

        TabContent() {
          FeedingPage()
        }.tabBar(this.TabBuilder('投喂', 2, $rawfile('image/tab_feeding.svg')))

        TabContent() {
          ProfilePage()
        }.tabBar(this.TabBuilder('档案', 3, $rawfile('image/tab_profile.svg')))

        TabContent() {
          DashboardPage()
        }.tabBar(this.TabBuilder('看板', 4, $rawfile('image/tab_dashboard.svg')))

        TabContent() {
          VirtualPetPage()
        }.tabBar(this.TabBuilder('萌宠', 5, $rawfile('image/tab_pet.svg')))
      }
      .barHeight(64)
      .barBackgroundColor(Theme.CARD)
      .onChange((index: number) => {
        this.currentTabIndex = index;
        AppStorage.SetOrCreate('currentTabIndex', index);
      })

      // Floating pet overlay — all tabs
      FloatingPet()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.BG)
  }
}
