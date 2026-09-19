import { common } from '@kit.AbilityKit';
import { Routes } from '../common/Routes';
import { CompareParam, HouseDetailParam, HousePrepareParam, InspectionParam, SceneSelectParam } from '../common/NavParams';
import { House, InspectionSummary } from '../domain/model/Entities';
import { InspectionStatus, SceneKey } from '../domain/model/CoreEnums';
import { HouseRepo } from '../data/repo/HouseRepo';
import { InspectionRepo } from '../data/repo/InspectionRepo';
import { InspectionLauncher } from '../features/inspection/InspectionLauncher';
import { DateUtil } from '../common/DateUtil';
import { LayoutUtil } from '../common/LayoutUtil';
import { Chevron } from '../common/ui/Theme';

@Builder
export function houseDetailBuilder() {
  HouseDetailPage();
}

@Component
struct HouseDetailPage {
  @State houseId: number = 0;
  @State house: House = new House();
  @State summaries: InspectionSummary[] = [];
  @State showAddress: boolean = false;
  private pathStack: NavPathStack = new NavPathStack();

  build() {
    NavDestination() {
      Column({ space: 12 }) {
        Column({ space: 6 }) {
          Row({ space: 10 }) {
            Text(this.house.name).fontSize(20).fontWeight(FontWeight.Bold).layoutWeight(1)
            Text('编辑').fontSize(13).fontColor($r('app.color.brand'))
              .onClick(() => {
                this.pathStack.pushPathByName(Routes.HOUSE_EDIT,
                  { sceneKey: '', houseId: this.houseId } as HousePrepareParam);
              })
          }
          .width('100%')
          Text(LayoutUtil.describeText(this.house.layout)).fontSize(13).opacity(0.6).width('100%')
          if (this.house.fullAddress.length > 0) {
            Text(this.showAddress ? `完整地址：${this.house.fullAddress}` : '完整地址已隐藏（点击查看）')
              .fontSize(12)
              .opacity(0.5)
              .width('100%')
              .onClick(() => {
                this.showAddress = !this.showAddress;
              })
          }
          if (this.house.landlordName.length > 0 || this.house.tenantName.length > 0) {
            Text(`房东：${this.house.landlordName.length > 0 ? this.house.landlordName : '—'} · 租客：${this.house.tenantName.length > 0 ? this.house.tenantName : '—'}`)
              .fontSize(12)
              .opacity(0.6)
              .width('100%')
          }
        }
        .alignItems(HorizontalAlign.Start)
        .padding(14)
        .borderRadius(12)
        .backgroundColor($r('app.color.card_bg'))
        .width('100%')

        Button('开始新检查（复用本档案）')
          .width('100%')
          .backgroundColor($r('app.color.brand'))
          .onClick(() => {
            this.pathStack.pushPathByName(Routes.SCENE_SELECT, { houseId: this.houseId } as SceneSelectParam);
          })

        Text('检查记录')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .width('100%')

        if (this.summaries.length === 0) {
          Text('还没有检查记录').fontSize(13).opacity(0.5).width('100%')
        } else {
          List({ space: 8 }) {
            ForEach(this.summaries, (s: InspectionSummary) => {
              ListItem() {
                Row({ space: 10 }) {
                  Column({ space: 3 }) {
                    Text(InspectionLauncher.sceneTitleOf(s.inspection.sceneKey))
                      .fontSize(15)
                      .fontWeight(FontWeight.Medium)
                    Text(`${DateUtil.formatDateTime(s.inspection.startedAt)}`)
                      .fontSize(12)
                      .opacity(0.6)
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  Column({ space: 2 }) {
                    Text(s.inspection.status === InspectionStatus.FROZEN ? '已冻结' : '草稿')
                      .fontSize(12)
                      .fontColor(s.inspection.status === InspectionStatus.FROZEN
                        ? $r('app.color.success') : $r('app.color.warning'))
                    Text(`${s.doneItems}/${s.totalItems} 项`).fontSize(12).opacity(0.6)
                  }

                  if (s.inspection.sceneKey === SceneKey.MOVE_OUT && s.inspection.baselineInspectionId > 0) {
                    Text('前后对比')
                      .fontSize(12)
                      .fontColor($r('app.color.brand'))
                      .padding({ left: 8, right: 2, top: 4, bottom: 4 })
                      .onClick(() => {
                        this.pathStack.pushPathByName(Routes.COMPARE,
                          { inspectionId: s.inspection.id } as CompareParam);
                      })
                  }

                  Chevron()
                }
                .width('100%')
                .padding(14)
                .borderRadius(12)
                .backgroundColor($r('app.color.card_bg'))
                .onClick(() => {
                  if (s.inspection.status === InspectionStatus.FROZEN) {
                    this.pathStack.pushPathByName(Routes.ARCHIVE_DETAIL,
                      { inspectionId: s.inspection.id } as InspectionParam);
                  } else {
                    this.pathStack.pushPathByName(Routes.INSPECTION,
                      { inspectionId: s.inspection.id } as InspectionParam);
                  }
                })
              }
            }, (s: InspectionSummary) => `${s.inspection.id}-${s.doneItems}`)
          }
          .layoutWeight(1)
          .width('100%')
        }
      }
      .padding(16)
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.bg_page'))
    }
    .title('房屋详情')
    .onShown(() => {
      // 从检查执行/档案编辑页返回时刷新时间线与记录状态（onReady 仅首次加载）
      if (this.houseId > 0) {
        this.load();
      }
    })
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
      const p = ctx.pathInfo.param as HouseDetailParam | null;
      if (p !== null && p !== undefined) {
        this.houseId = p.houseId;
        this.load();
      }
    })
  }

  private load(): void {
    const uiCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    new HouseRepo(uiCtx).getById(this.houseId).then((h) => {
      if (h !== null) {
        this.house = h;
      }
    });
    new InspectionRepo(uiCtx).listByHouse(this.houseId).then((list: InspectionSummary[]) => {
      this.summaries = list;
    });
  }
}
