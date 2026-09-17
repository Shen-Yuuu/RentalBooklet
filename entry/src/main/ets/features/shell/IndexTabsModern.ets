import { uiMaterial } from '@kit.ArkUI';
import { HomeTab } from '../home/HomeTab';
import { RecordsTab } from '../records/RecordsTab';
import { SettingsTab } from '../settings/SettingsTab';

/**
 * 底部导航（现代路径，API 26+ 设备）：barFloatingStyle 悬浮胶囊栏 +
 * 沉浸式系统材质（设备不支持时自动降级为普通材质）。
 * 本组件仅在 deviceInfo.sdkApiVersion >= 26 时由 Index 实例化。
 */
@Component
export struct IndexTabsModern {
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
    .barFloatingStyle(this.floatingStyle())
    .width('100%')
    .height('100%')
  }

  private floatingStyle(): FloatingTabBarStyle {
    const style: FloatingTabBarStyle = {
      barSideMargin: 16,
      barBottomMargin: 10,
      maskColor: '#0F000000',
      systemMaterial: uiMaterial.isImmersiveMaterialSupported() ? new uiMaterial.ImmersiveMaterial() : undefined
    };
    return style;
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
