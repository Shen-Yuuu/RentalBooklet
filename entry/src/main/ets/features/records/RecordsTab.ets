import { common } from '@kit.AbilityKit';
import { SegmentButton, SegmentButtonOptions, CapsuleSegmentButtonConstructionOptions } from '@kit.ArkUI';
import { Routes } from '../../common/Routes';
import { CompareParam, InspectionParam } from '../../common/NavParams';
import { RecordSummary } from '../../domain/model/Entities';
import { InspectionStatus, SceneKey } from '../../domain/model/CoreEnums';
import { InspectionRepo } from '../../data/repo/InspectionRepo';
import { InspectionLauncher } from '../inspection/InspectionLauncher';
import { DateUtil } from '../../common/DateUtil';
import { Theme, PressCard, Chevron, StatusBadge, IconBadge, SceneIcons } from '../../common/ui/Theme';

/** 记录 Tab：搜索 + 分段筛选（全部/进行中/已冻结），草稿可续作、冻结可查看归档。 */
@Component
export struct RecordsTab {
  @Consume('navPathStack') pathStack: NavPathStack;
  @StorageProp('home_dirty') @Watch('reload') homeDirty: number = 0;
  @State drafts: RecordSummary[] = [];
  @State frozenList: RecordSummary[] = [];
  /** 搜索关键字（房屋名/场景/报告号模糊匹配）。 */
  @State keyword: string = '';
  /** 分段筛选选中项：0=全部 1=进行中 2=已冻结。 */
  @State filterIndexes: number[] = [0];
  @State filterOptions: SegmentButtonOptions = RecordsTab.buildFilterOptions();

  private static buildFilterOptions(): SegmentButtonOptions {
    const opts: CapsuleSegmentButtonConstructionOptions = {
      buttons: [
        { text: '全部' },
        { text: '进行中' },
        { text: '已冻结' }
      ],
      multiply: false,
      selectedBackgroundColor: $r('app.color.brand')
    };
    return SegmentButtonOptions.capsule(opts);
  }

  aboutToAppear(): void {
    this.reload();
  }

  reload(): void {
    const uiCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    new InspectionRepo(uiCtx).listSummaries().then((list: RecordSummary[]) => {
      const drafts: RecordSummary[] = [];
      const frozen: RecordSummary[] = [];
      for (const s of list) {
        if (s.status === InspectionStatus.FROZEN) {
          frozen.push(s);
        } else {
          drafts.push(s);
        }
      }
      this.drafts = drafts;
      this.frozenList = frozen;
    });
  }

  private filterOf(): number {
    return this.filterIndexes.length > 0 ? this.filterIndexes[0] : 0;
  }

  private showDrafts(): boolean {
    return this.filterOf() !== 2;
  }

  private showFrozen(): boolean {
    return this.filterOf() !== 1;
  }

  private matchKeyword(s: RecordSummary): boolean {
    if (this.keyword.trim().length === 0) {
      return true;
    }
    const k = this.keyword.trim();
    return s.houseName.includes(k) || this.sceneTitle(s.sceneKey).includes(k)
      || s.reportNo.includes(k) || s.reportNo.toLowerCase().includes(k.toLowerCase());
  }

  private filteredDrafts(): RecordSummary[] {
    const list: RecordSummary[] = [];
    for (const s of this.drafts) {
      if (this.matchKeyword(s)) {
        list.push(s);
      }
    }
    return list;
  }

  private filteredFrozen(): RecordSummary[] {
    const list: RecordSummary[] = [];
    for (const s of this.frozenList) {
      if (this.matchKeyword(s)) {
        list.push(s);
      }
    }
    return list;
  }

  /** 场景 key → 中文名：custom 等无内置模板场景回退为 key 本身。 */
  sceneTitle(sceneKey: string): string {
    return InspectionLauncher.sceneTitleOf(sceneKey);
  }

  private openRecord(s: RecordSummary): void {
    if (s.status === InspectionStatus.FROZEN) {
      this.pathStack.pushPathByName(Routes.ARCHIVE_DETAIL, { inspectionId: s.inspectionId } as InspectionParam);
    } else {
      this.pathStack.pushPathByName(Routes.INSPECTION, { inspectionId: s.inspectionId } as InspectionParam);
    }
  }

  /** E1/E2 对比入口：含基线的退租检查（草稿进行中/已冻结均可对照）。 */
  private hasCompare(s: RecordSummary): boolean {
    return s.sceneKey === SceneKey.MOVE_OUT && s.baselineInspectionId > 0;
  }

  private openCompare(s: RecordSummary): void {
    this.pathStack.pushPathByName(Routes.COMPARE, { inspectionId: s.inspectionId } as CompareParam);
  }

  @Builder
  sectionHeader(label: string, count: number) {
    Text(`${label}（${count}）`)
      .fontSize(Theme.fontBody)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.text_sec'))
      .width('100%')
      .margin({ top: 4 })
  }

  /** 卡片标题行：房屋名 + 修订版徽标。 */
  @Builder
  cardTitleRow(s: RecordSummary) {
    Row({ space: 6 }) {
      Text(s.houseName)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_pri'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (s.revisionNo > 0) {
        StatusBadge('修订版', $r('app.color.warning'), $r('app.color.warning_light'))
      }
    }
  }

  @Builder
  compareButton(s: RecordSummary) {
    Text('前后对比')
      .fontSize(Theme.fontCaption)
      .fontColor($r('app.color.brand'))
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .borderRadius(14)
      .backgroundColor($r('app.color.brand_light'))
      .onClick(() => {
        this.openCompare(s);
      })
  }

  @Builder
  draftItem(s: RecordSummary) {
    ListItem() {
      PressCard({
        onTap: () => {
          this.openRecord(s);
        }
      }) {
        Row({ space: 12 }) {
          IconBadge($r('sys.symbol.timer'), $r('app.color.warning'), $r('app.color.warning_light'))
          Column({ space: 3 }) {
            this.cardTitleRow(s)
            Text(`${this.sceneTitle(s.sceneKey)} · 已完成 ${s.doneItems}/${s.totalItems} 项`)
              .fontSize(Theme.fontCaption)
              .fontColor($r('app.color.text_sec'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          if (this.hasCompare(s)) {
            this.compareButton(s)
          }

          Text('继续')
            .fontSize(13)
            .fontColor($r('app.color.brand'))
            .fontWeight(FontWeight.Medium)
          Chevron()
        }
      }
    }
  }

  @Builder
  frozenItem(s: RecordSummary) {
    ListItem() {
      PressCard({
        onTap: () => {
          this.openRecord(s);
        }
      }) {
        Row({ space: 12 }) {
          IconBadge(SceneIcons.iconOf(s.sceneKey), $r('app.color.success'), $r('app.color.success_light'))
          Column({ space: 3 }) {
            this.cardTitleRow(s)
            Text(`${s.reportNo.length > 0 ? s.reportNo : this.sceneTitle(s.sceneKey)} · ${DateUtil.formatDate(s.frozenAt)} 冻结`)
              .fontSize(Theme.fontCaption)
              .fontColor($r('app.color.text_sec'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          if (this.hasCompare(s)) {
            this.compareButton(s)
          }

          StatusBadge('已冻结', $r('app.color.success'), $r('app.color.success_light'))
          Chevron()
        }
      }
    }
  }

  build() {
    Column({ space: 10 }) {
      Text('记录')
        .fontSize(Theme.fontTitle)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_pri'))
        .width('100%')

      Search({ placeholder: '搜索房屋、场景或报告号', value: this.keyword })
        .height(40)
        .backgroundColor($r('app.color.bg_card'))
        .onChange((value: string) => {
          this.keyword = value;
        })

      SegmentButton({ options: this.filterOptions, selectedIndexes: this.filterIndexes })
        .width('100%')

      if (this.drafts.length === 0 && this.frozenList.length === 0) {
        Column({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.doc_text'))
            .fontSize(52)
            .fontColor([$r('app.color.text_ter')])
          Text('暂无检查记录')
            .fontSize(15)
            .fontColor($r('app.color.text_sec'))
          Text('完成第一次检查后，冻结的报告会出现在这里')
            .fontSize(13)
            .fontColor($r('app.color.text_ter'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 8 }) {
          if (this.showDrafts() && this.filteredDrafts().length > 0) {
            ListItem() {
              this.sectionHeader('进行中（草稿）', this.filteredDrafts().length)
            }
            ForEach(this.filteredDrafts(), (s: RecordSummary) => {
              this.draftItem(s)
            }, (s: RecordSummary) => `draft-${s.inspectionId}-${s.doneItems}`)
          }

          if (this.showFrozen() && this.filteredFrozen().length > 0) {
            ListItem() {
              this.sectionHeader('已冻结', this.filteredFrozen().length)
            }
            ForEach(this.filteredFrozen(), (s: RecordSummary) => {
              this.frozenItem(s)
            }, (s: RecordSummary) => `frozen-${s.inspectionId}-${s.revisionNo}`)
          }
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
      }
    }
    .padding(16)
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
  }
}
