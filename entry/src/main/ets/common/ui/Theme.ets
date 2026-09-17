import { curves } from '@kit.ArkUI';
import { SceneKey } from '../../domain/model/CoreEnums';

/** 设计令牌：字号/圆角/尺寸常量（颜色令牌见 base/dark element/color.json）。 */
export class Theme {
  static readonly fontTitle: number = 22;
  static readonly fontSection: number = 16;
  static readonly fontBody: number = 14;
  static readonly fontCaption: number = 12;
  static readonly fontMicro: number = 11;
  static readonly radiusCard: number = 16;
  static readonly radiusChip: number = 12;
  static readonly radiusBadge: number = 10;
  static readonly radiusIconBg: number = 10;
  static readonly iconBgSize: number = 38;
  static readonly iconSize: number = 20;
}

/** 场景 key → SymbolGlyph 图标（记录/场景/历史页共用）。 */
export class SceneIcons {
  static iconOf(sceneKey: string): Resource {
    if (sceneKey === SceneKey.MOVE_IN) {
      return $r('sys.symbol.house_fill');
    }
    if (sceneKey === SceneKey.MOVE_OUT) {
      return $r('sys.symbol.arrow_2_circlepath');
    }
    if (sceneKey === SceneKey.REPAIR) {
      return $r('sys.symbol.wrench_and_screwdriver');
    }
    if (sceneKey === SceneKey.CLEANING) {
      return $r('sys.symbol.paintbrush');
    }
    if (sceneKey === SceneKey.APPLIANCE) {
      return $r('sys.symbol.bolt');
    }
    return $r('sys.symbol.square_and_pencil');
  }
}

@Builder
export function EmptyContent() {
}

/** 列表/卡片右侧 chevron（替代 Text('›')）。 */
@Builder
export function Chevron() {
  SymbolGlyph($r('sys.symbol.chevron_right'))
    .fontSize(16)
    .fontColor([$r('app.color.text_ter')])
}

/** 状态徽标：文字 + 前景/背景色（浅深色由资源切换）。 */
@Builder
export function StatusBadge(label: string, color: ResourceColor, bg: ResourceColor) {
  Text(label)
    .fontSize(Theme.fontMicro)
    .fontColor(color)
    .padding({ left: 8, right: 8, top: 3, bottom: 3 })
    .borderRadius(Theme.radiusBadge)
    .backgroundColor(bg)
}

/** 卡片左侧图标容器（品牌底圆角方块 + SymbolGlyph）。 */
@Builder
export function IconBadge(icon: Resource, color: ResourceColor, bg: ResourceColor) {
  Column() {
    SymbolGlyph(icon)
      .fontSize(Theme.iconSize)
      .fontColor([color])
  }
  .width(Theme.iconBgSize)
  .height(Theme.iconBgSize)
  .borderRadius(Theme.radiusIconBg)
  .backgroundColor(bg)
  .justifyContent(FlexAlign.Center)
}

/**
 * 通用按压卡片：白底 + 大圆角 + 细阴影 + springMotion 按压缩放。
 * 内容通过 @BuilderParam 注入，onClick 透传。
 */
@Component
export struct PressCard {
  @BuilderParam content: () => void = EmptyContent;
  @State pressed: boolean = false;
  onTap: () => void = () => {};

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(14)
    .borderRadius(Theme.radiusCard)
    .backgroundColor($r('app.color.card_bg'))
    .shadow(ShadowStyle.OUTER_DEFAULT_SM)
    .scale({ x: this.pressed ? 0.97 : 1, y: this.pressed ? 0.97 : 1 })
    .animation({ curve: curves.springMotion(0.4, 0.85) })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.pressed = true;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.pressed = false;
      }
    })
    .onClick(() => {
      this.onTap();
    })
  }
}
