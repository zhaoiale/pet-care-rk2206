// BottomTabBar.ets — 通用底部导航栏（用于非 Tab 内页面，保持全局导航一致）
import { Theme } from './Theme';

@Component
export struct BottomTabBar {
  // 当前高亮 tab 索引（-1 表示不高亮，用于非 tab 页面如历史记录）
  @Prop currentIndex: number = 0;
  // tab 点击回调
  onSelect: (index: number) => void = (index: number) => {};

  @Builder
  TabItem(index: number, label: string, icon: Resource) {
    Column() {
      Image(icon)
        .width(24)
        .height(24)
        .fillColor(this.currentIndex === index ? Theme.PRIMARY : Theme.TEXT_TERTIARY)
        .margin({ bottom: 2 })
      Text(label)
        .fontSize(11)
        .fontColor(this.currentIndex === index ? Theme.PRIMARY : Theme.TEXT_TERTIARY)
        .fontWeight(this.currentIndex === index ? FontWeight.Medium : FontWeight.Normal)
    }
    .layoutWeight(1)
    .padding({ top: 8, bottom: 6 })
    .justifyContent(FlexAlign.Center)
    .onClick(() => this.onSelect(index))
  }

  build() {
    Row() {
      this.TabItem(0, '首页', $rawfile('image/tab_home.svg'))
      this.TabItem(1, '安抚', $rawfile('image/tab_comfort.svg'))
      this.TabItem(2, '投喂', $rawfile('image/tab_feeding.svg'))
      this.TabItem(3, '档案', $rawfile('image/tab_profile.svg'))
      this.TabItem(4, '看板', $rawfile('image/tab_dashboard.svg'))
      this.TabItem(5, '萌宠', $rawfile('image/tab_pet.svg'))
    }
    .width('100%')
    .height(60)
    .backgroundColor(Theme.CARD)
    .shadow({ radius: 14, color: '#18000000', offsetX: 0, offsetY: -3 })
  }
}
