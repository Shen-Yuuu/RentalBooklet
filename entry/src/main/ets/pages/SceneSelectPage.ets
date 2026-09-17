import { common } from '@kit.AbilityKit';
import { Routes } from '../common/Routes';
import { HousePrepareParam, SceneSelectParam } from '../common/NavParams';
import { BUILTIN_TEMPLATES } from '../domain/template/BuiltinTemplates';
import { SceneTemplate } from '../domain/model/TemplateModels';
import { SceneKey } from '../domain/model/CoreEnums';
import { House, Inspection } from '../domain/model/Entities';
import { HouseRepo } from '../data/repo/HouseRepo';
import { InspectionLauncher } from '../features/inspection/InspectionLauncher';
import { BaselinePickerSheet } from '../features/inspection/BaselinePickerSheet';
import { Theme, PressCard, Chevron, IconBadge, SceneIcons } from '../common/ui/Theme';

@Builder
export function sceneSelectBuilder() {
  SceneSelectPage();
}

@Component
struct SceneSelectPage {
  @State houseId: number = 0;
  @State houseName: string = '';
  @State busy: boolean = false;
  @State errorText: string = '';
  /** E1 基线选择：候选与半模态开关。 */
  @State baselineCandidates: Inspection[] = [];
  @State showBaselineSheet: boolean = false;
  private pendingSceneKey: string = '';
  private pathStack: NavPathStack = new NavPathStack();

  build() {
    NavDestination() {
      Column({ space: 12 }) {
        Text('选择留证场景')
          .fontSize(Theme.fontTitle)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_pri'))
          .width('100%')
        Text('不同场景加载不同模板，跟着路线走即可')
          .fontSize(13)
          .fontColor($r('app.color.text_sec'))
          .width('100%')

        if (this.errorText.length > 0) {
          Text(this.errorText)
            .fontSize(13)
            .fontColor($r('app.color.danger'))
            .width('100%')
        }

        List({ space: 10 }) {
          ForEach(BUILTIN_TEMPLATES, (tpl: SceneTemplate) => {
            ListItem() {
              PressCard({
                onTap: () => {
                  this.onSceneTap(tpl);
                }
              }) {
                Row({ space: 12 }) {
                  IconBadge(SceneIcons.iconOf(tpl.sceneKey), $r('app.color.brand'), $r('app.color.brand_light'))
                  Column({ space: 4 }) {
                    Text(tpl.title)
                      .fontSize(17)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.text_pri'))
                    Text(tpl.description)
                      .fontSize(13)
                      .fontColor($r('app.color.text_sec'))
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  Chevron()
                }
              }
            }
          }, (tpl: SceneTemplate) => tpl.sceneKey)
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
      }
      .padding(16)
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.bg_page'))
      .bindSheet($$this.showBaselineSheet, this.baselineSheetBuilder(), { height: 380 })
    }
    .title(this.houseId > 0 ? '选择场景' : '开始检查')
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
      const p = ctx.pathInfo.param as SceneSelectParam | null;
      if (p !== null && p !== undefined && p.houseId !== undefined) {
        this.houseId = p.houseId;
        this.loadHouseName();
      }
    })
  }

  @Builder
  baselineSheetBuilder() {
    BaselinePickerSheet({
      candidates: this.baselineCandidates,
      houseName: this.houseName,
      onConfirm: (baselineId: number) => {
        this.confirmBaseline(baselineId);
      },
      onCancel: () => {
        this.showBaselineSheet = false;
      }
    })
  }

  private loadHouseName(): void {
    const uiCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    new HouseRepo(uiCtx).getById(this.houseId).then((h: House | null) => {
      if (h !== null) {
        this.houseName = h.name;
      }
    });
  }

  private async onSceneTap(tpl: SceneTemplate): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.errorText = '';
    try {
      const uiCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (this.houseId <= 0) {
        this.pathStack.pushPathByName(Routes.HOUSE_EDIT, { sceneKey: tpl.sceneKey } as HousePrepareParam);
        return;
      }
      // E1：仅退租场景弹基线选择；无已冻结入住记录则跳过（baseline 为空）
      if (tpl.sceneKey === SceneKey.MOVE_OUT) {
        const candidates = await InspectionLauncher.listBaselines(uiCtx, this.houseId);
        if (candidates.length > 0) {
          this.baselineCandidates = candidates;
          this.pendingSceneKey = tpl.sceneKey;
          this.showBaselineSheet = true;
          return;
        }
      }
      await this.launch(uiCtx, tpl.sceneKey, 0);
    } catch (err) {
      const e = err as Error;
      this.errorText = e.message;
    } finally {
      this.busy = false;
    }
  }

  private confirmBaseline(baselineId: number): void {
    this.showBaselineSheet = false;
    const uiCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const sceneKey = this.pendingSceneKey;
    this.launch(uiCtx, sceneKey, baselineId).catch((err: Error) => {
      this.errorText = err.message;
    });
  }

  private async launch(uiCtx: common.UIAbilityContext, sceneKey: string, baselineId: number): Promise<void> {
    await InspectionLauncher.startForHouse(uiCtx, this.pathStack, this.houseId, sceneKey, false, baselineId);
  }
}
