import { common } from '@kit.AbilityKit';
import { Routes } from '../../common/Routes';
import { HouseDetailParam } from '../../common/NavParams';
import { House } from '../../domain/model/Entities';
import { HouseRepo } from '../../data/repo/HouseRepo';
import { InspectionRepo } from '../../data/repo/InspectionRepo';
import { LayoutUtil } from '../../common/LayoutUtil';
import { Theme, PressCard, Chevron, IconBadge } from '../../common/ui/Theme';

@Component
export struct HomeTab {
  @Consume('navPathStack') pathStack: NavPathStack;
  @StorageProp('home_dirty') @Watch('reload') homeDirty: number = 0;
  @State houses: House[] = [];
  @State counts: Map<number, number> = new Map();

  aboutToAppear(): void {
    this.reload();
  }

  reload(): void {
    const uiCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    new HouseRepo(uiCtx).listAll().then((list: House[]) => {
      this.houses = list;
    });
    new InspectionRepo(uiCtx).countsByHouse().then((map: Map<number, number>) => {
      this.counts = map;
    });
  }

  countOf(id: number): number {
    const c = this.counts.get(id);
    return c === undefined ? 0 : c;
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column({ space: 12 }) {
        Text('我的房屋')
          .fontSize(Theme.fontTitle)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_pri'))
          .width('100%')

        if (this.houses.length === 0) {
          Column({ space: 10 }) {
            SymbolGlyph($r('sys.symbol.house'))
              .fontSize(52)
              .fontColor([$r('app.color.text_ter')])
            Text('还没有房屋档案')
              .fontSize(15)
              .fontColor($r('app.color.text_sec'))
            Text('点击下方按钮，开始第一次入住检查')
              .fontSize(13)
              .fontColor($r('app.color.text_ter'))
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            GridRow({ columns: { xs: 1, md: 2 }, gutter: { x: 12, y: 12 } }) {
              ForEach(this.houses, (h: House) => {
                GridCol() {
                  PressCard({
                    onTap: () => {
                      this.pathStack.pushPathByName(Routes.HOUSE_DETAIL, { houseId: h.id } as HouseDetailParam);
                    }
                  }) {
                    Row({ space: 12 }) {
                      IconBadge($r('sys.symbol.house'), $r('app.color.brand'), $r('app.color.brand_light'))
                      Column({ space: 3 }) {
                        Text(h.name)
                          .fontSize(16)
                          .fontWeight(FontWeight.Medium)
                          .fontColor($r('app.color.text_pri'))
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                        Text(LayoutUtil.describeText(h.layout))
                          .fontSize(Theme.fontCaption)
                          .fontColor($r('app.color.text_sec'))
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                      }
                      .alignItems(HorizontalAlign.Start)
                      .layoutWeight(1)

                      Column({ space: 2 }) {
                        Text(`${this.countOf(h.id)} 次`)
                          .fontSize(Theme.fontCaption)
                          .fontColor($r('app.color.text_sec'))
                        Chevron()
                      }
                      .alignItems(HorizontalAlign.End)
                    }
                  }
                }
              }, (h: House) => `${h.id}-${h.updatedAt}`)
            }
            .width('100%')
          }
          .layoutWeight(1)
          .width('100%')
          .scrollBar(BarState.Off)
        }
      }
      .padding(16)
      .width('100%')
      .height('100%')

      Button({ type: ButtonType.Capsule }) {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(18)
            .fontColor([Color.White])
          Text('开始检查')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
        }
      }
      .height(46)
      .padding({ left: 32, right: 32 })
      .backgroundColor($r('app.color.brand'))
      .shadow(ShadowStyle.OUTER_DEFAULT_MD)
      .margin({ bottom: 16 })
      .onClick(() => {
        this.pathStack.pushPathByName(Routes.SCENE_SELECT, null);
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
  }
}
