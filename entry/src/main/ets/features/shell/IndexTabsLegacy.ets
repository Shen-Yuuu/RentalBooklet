import { HomeTab } from '../home/HomeTab';
import { RecordsTab } from '../records/RecordsTab';
import { SettingsTab } from '../settings/SettingsTab';

/**
 * 底部导航（兼容路径，API <26 设备）：常规 Tabs + SymbolGlyph 自定义 tabBar。
 * API 26+ 设备使用 IndexTabsModern（悬浮胶囊 + 系统材质），本组件不实例化。
 */
@Component
export struct IndexTabsLegacy {
  @State currentIndex: number = 0;

  build() {
    Tabs({ barPosition: BarPosition.End, index: this.currentIndex }) {
      TabContent() {
        HomeTab()
      }
      .tabBar(this.tabItem(0, '房屋', $r('sys.symbol.house')))

      TabContent() {
        RecordsTab()
      }
      .tabBar(this.tabItem(1, '记录', $r('sys.symbol.doc_text')))

      TabContent() {
        SettingsTab()
      }
      .tabBar(this.tabItem(2, '设置', $r('sys.symbol.gearshape')))
    }
    .onChange((index: number) => {
      this.currentIndex = index;
    })
    .width('100%')
    .height('100%')
  }

  @Builder
  tabItem(index: number, label: string, icon: Resource) {
    Column({ space: 2 }) {
      SymbolGlyph(icon)
        .fontSize(22)
        .fontColor([this.currentIndex === index ? $r('app.color.brand') : $r('app.color.text_ter')])
      Text(label)
        .fontSize(11)
        .fontWeight(this.currentIndex === index ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.currentIndex === index ? $r('app.color.brand') : $r('app.color.text_ter'))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}
