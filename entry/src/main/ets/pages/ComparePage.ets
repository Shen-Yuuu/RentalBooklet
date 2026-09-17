import { common } from '@kit.AbilityKit';
import { CompareParam } from '../common/NavParams';
import { DateUtil } from '../common/DateUtil';
import { WideBreakpointWatcher } from '../common/BreakpointUtil';
import { CompareRepo } from '../data/repo/CompareRepo';
import { InspectionRepo } from '../data/repo/InspectionRepo';
import { PhotoRepo } from '../data/repo/PhotoRepo';
import { BaselineOnlyItem, CompareAligner } from '../domain/compare/CompareAligner';
import { CompareResult, InspectionStatus, ItemStatus } from '../domain/model/CoreEnums';
import { Inspection, ItemEntity, PhotoEntity } from '../domain/model/Entities';

/** 对比页行视图：配对结果 + 双方照片/状态/备注（页面内装配）。 */
class CompareRowView {
  roomId: number = 0;
  roomName: string = '';
  itemId: number = 0;
  itemName: string = '';
  newItem: boolean = false;
  baselineStatus: ItemStatus = ItemStatus.PENDING;
  baselineNote: string = '';
  baselineThumb: string = '';
  currentStatus: ItemStatus = ItemStatus.PENDING;
  currentNote: string = '';
  currentThumb: string = '';
  /** 三态结果（''=未标记）。 */
  result: string = '';
}

@Builder
export function compareBuilder() {
  ComparePage();
}

/**
 * 前后对比页（E2，产品文档 §5.6 / 链路 L11）：
 * - 入参 inspectionId（退租检查）；按 (room_key,item_key) 对齐基线（入住）与本次检查；
 * - 逐项卡片：基线照片/状态/备注 ↔ 本次照片/状态/备注；三态确认即时落库（compare_result）；
 * - 对不上的当前项标「新增项」；基线独有项单列「基线独有（本次未包含）」；
 * - FROZEN 只读；措辞红线：仅客观呈现，不出现任何归因/责任文案。
 */
@Component
struct ComparePage {
  @State inspectionId: number = 0;
  @State loading: boolean = true;
  @State loadError: string = '';
  @State noBaseline: boolean = false;
  @State readonly: boolean = false;
  @State rows: CompareRowView[] = [];
  @State baselineOnly: BaselineOnlyItem[] = [];
  @State baselineInfoText: string = '';
  @State confirmedCount: number = 0;
  @State changedCount: number = 0;
  @State busyItemId: number = 0;
  /** F2：宽屏（≥840vp）放大对比照片。 */
  @State isWide: boolean = false;
  private wideWatcher: WideBreakpointWatcher | undefined = undefined;

  aboutToAppear(): void {
    this.wideWatcher = new WideBreakpointWatcher(this.getUIContext(), (wide: boolean) => {
      this.isWide = wide;
    });
    this.wideWatcher.attach();
  }

  aboutToDisappear(): void {
    if (this.wideWatcher !== undefined) {
      this.wideWatcher.detach();
      this.wideWatcher = undefined;
    }
  }

  build() {
    NavDestination() {
      Column({ space: 12 }) {
        if (this.loading) {
          Column({ space: 10 }) {
            LoadingProgress().width(36).height(36)
            Text('正在加载对比数据…').fontSize(13).opacity(0.6)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.loadError.length > 0) {
          Column({ space: 10 }) {
            Text(this.loadError).fontSize(14).opacity(0.6)
            Button('重新加载')
              .fontSize(13)
              .height(32)
              .backgroundColor($r('app.color.brand'))
              .onClick(() => {
                this.load();
              })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.noBaseline) {
          Column({ space: 10 }) {
            Text('未设置基线，无法对比。')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
            Text('创建退租检查时选择入住报告即可自动对比。')
              .fontSize(13)
              .opacity(0.55)
              .textAlign(TextAlign.Center)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          this.summaryBar()

          List({ space: 10 }) {
            ForEach(this.rows, (v: CompareRowView) => {
              ListItem() {
                this.pairCard(v)
              }
            }, (v: CompareRowView) => `${v.itemId}-${v.result}`)

            if (this.baselineOnly.length > 0) {
              ListItem() {
                this.baselineOnlyBlock()
              }
            }
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
    .title('前后对比')
    .onReady((ctx: NavDestinationContext) => {
      const p = ctx.pathInfo.param as CompareParam | null;
      if (p !== null && p !== undefined && p.inspectionId > 0) {
        this.inspectionId = p.inspectionId;
        this.load();
      } else {
        this.loading = false;
        this.loadError = '页面参数缺失，请从记录页重新进入';
      }
    })
  }

  /** 顶部汇总条：已确认 x/总数 + "有变化"数（客观计数，无归因文案）。 */
  @Builder
  summaryBar() {
    Column({ space: 4 }) {
      Text(`已确认 ${this.confirmedCount}/${this.rows.length}，其中"有变化" ${this.changedCount} 项`)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .width('100%')
      Text(this.baselineInfoText)
        .fontSize(12)
        .opacity(0.6)
        .width('100%')
      if (this.readonly) {
        Text('该记录已冻结，对比结果仅可查看')
          .fontSize(12)
          .fontColor($r('app.color.success'))
          .width('100%')
      }
    }
    .padding(14)
    .borderRadius(12)
    .backgroundColor($r('app.color.card_bg'))
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  /** 逐项卡片：标题行 + 基线↔本次双栏 + 三态按钮。 */
  @Builder
  pairCard(v: CompareRowView) {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text(`${v.roomName} · ${v.itemName}`)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
        if (v.newItem) {
          Text('新增项')
            .fontSize(11)
            .fontColor($r('app.color.warning'))
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(6)
            .backgroundColor($r('app.color.warning_light'))
        }
      }
      .width('100%')

      Row({ space: 10 }) {
        this.sideBlock('入住时', this.statusText(v.baselineStatus), v.baselineNote, v.baselineThumb, v.newItem,
          this.sideImageHeight())
        Text('↔').fontSize(14).opacity(0.4)
        this.sideBlock('本次', this.statusText(v.currentStatus), v.currentNote, v.currentThumb, false,
          this.sideImageHeight())
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      this.stateButtons(v)
    }
    .padding(14)
    .borderRadius(12)
    .backgroundColor($r('app.color.card_bg'))
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  /** 单侧信息块：首张缩略图（无图灰底）+ 状态 + 备注摘要。宽屏放大图片（F2）。 */
  @Builder
  sideBlock(label: string, statusText: string, note: string, thumb: string, missing: boolean, imgHeight: number) {
    Column({ space: 6 }) {
      Text(label).fontSize(11).opacity(0.5)
      if (thumb.length > 0) {
        Image(`file://${thumb}`)
          .width('100%')
          .height(imgHeight)
          .borderRadius(8)
          .objectFit(ImageFit.Cover)
      } else {
        Column() {
          Text(missing ? '基线无此项' : '无照片')
            .fontSize(12)
            .opacity(0.4)
        }
        .width('100%')
        .height(imgHeight)
        .borderRadius(8)
        .backgroundColor($r('app.color.bg_disabled'))
        .justifyContent(FlexAlign.Center)
      }
      Text(statusText).fontSize(13)
      if (note.length > 0) {
        Text(note)
          .fontSize(11)
          .opacity(0.6)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .layoutWeight(1)
    .width('100%')
  }

  /** F2：宽屏对比照片 160vp，窄屏 88vp。 */
  private sideImageHeight(): number {
    return this.isWide ? 160 : 88;
  }

  /** 三态按钮组：点击即 upsert 落库；FROZEN 禁用仅查看。 */
  @Builder
  stateButtons(v: CompareRowView) {
    Row({ space: 8 }) {
      this.stateButton(v, CompareResult.UNCHANGED, '无变化', $r('app.color.success'))
      this.stateButton(v, CompareResult.CHANGED, '有变化', $r('app.color.danger'))
      this.stateButton(v, CompareResult.PENDING, '待确认', $r('app.color.warning'))
    }
    .width('100%')
  }

  @Builder
  stateButton(v: CompareRowView, value: string, label: string, color: ResourceColor) {
    Button(label)
      .layoutWeight(1)
      .height(32)
      .fontSize(13)
      .backgroundColor(v.result === value ? color : $r('app.color.card_bg'))
      .fontColor(v.result === value ? Color.White : $r('app.color.text_sec'))
      .border({ width: 1, color: v.result === value ? color : $r('app.color.divider'), radius: 16 })
      .enabled(!this.readonly && this.busyItemId !== v.itemId)
      .onClick(() => {
        this.onResult(v, value);
      })
  }

  /** 基线独有（本次未包含）分组：仅列出，不做任何判断。 */
  @Builder
  baselineOnlyBlock() {
    Column({ space: 8 }) {
      Text('基线独有（本次未包含）')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .opacity(0.7)
        .width('100%')
      ForEach(this.baselineOnly, (o: BaselineOnlyItem) => {
        Text(`${o.roomName} · ${o.itemName}`)
          .fontSize(13)
          .opacity(0.6)
          .width('100%')
      }, (o: BaselineOnlyItem) => `${o.roomName}-${o.itemName}`)
    }
    .padding(14)
    .borderRadius(12)
    .backgroundColor($r('app.color.card_bg'))
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  private statusText(st: ItemStatus): string {
    if (st === ItemStatus.OK) {
      return '正常';
    }
    if (st === ItemStatus.ISSUE) {
      return '有问题';
    }
    if (st === ItemStatus.NA) {
      return '不适用';
    }
    return '待检查';
  }

  /** itemId → 首张照片路径（缩略图优先）。 */
  private static firstThumbByItem(photos: PhotoEntity[]): Map<number, string> {
    const map = new Map<number, string>();
    for (const p of photos) {
      if (p.itemId <= 0 || map.has(p.itemId)) {
        continue;
      }
      map.set(p.itemId, p.thumbPath.length > 0 ? p.thumbPath : p.path);
    }
    return map;
  }

  private recount(): void {
    let confirmed = 0;
    let changed = 0;
    for (const r of this.rows) {
      if (r.result.length > 0) {
        confirmed++;
        if (r.result === CompareResult.CHANGED) {
          changed++;
        }
      }
    }
    this.confirmedCount = confirmed;
    this.changedCount = changed;
  }

  private async load(): Promise<void> {
    this.loading = true;
    this.loadError = '';
    const uiCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try {
      const repo = new InspectionRepo(uiCtx);
      const ins: Inspection | null = await repo.getById(this.inspectionId);
      if (ins === null) {
        this.loading = false;
        this.loadError = '未找到该检查记录，可能已被删除';
        return;
      }
      this.readonly = ins.status === InspectionStatus.FROZEN;
      const agg = await repo.getAggregate(this.inspectionId);
      if (agg === null) {
        this.loading = false;
        this.loadError = '未找到该检查记录，可能已被删除';
        return;
      }
      if (ins.baselineInspectionId <= 0) {
        this.noBaseline = true;
        this.loading = false;
        return;
      }
      const baseAgg = await repo.getAggregate(ins.baselineInspectionId);
      if (baseAgg === null) {
        // 基线记录不存在（可能被删除）：视同未设置基线
        this.noBaseline = true;
        this.loading = false;
        return;
      }

      const alignment = CompareAligner.align(baseAgg.rooms, baseAgg.itemsByRoom, agg.rooms, agg.itemsByRoom);
      const photoRepo = new PhotoRepo(uiCtx);
      const baseThumbs = ComparePage.firstThumbByItem(await photoRepo.listByInspection(ins.baselineInspectionId));
      const curThumbs = ComparePage.firstThumbByItem(await photoRepo.listByInspection(this.inspectionId));

      // 当前检查项 id → 实体（状态/备注回显）
      const curItemById = new Map<number, ItemEntity>();
      for (const list of agg.itemsByRoom.values()) {
        for (const it of list) {
          curItemById.set(it.id, it);
        }
      }

      const results = await new CompareRepo(uiCtx).listResults(this.inspectionId);
      const views: CompareRowView[] = [];
      for (const pair of alignment.pairs) {
        const v = new CompareRowView();
        v.roomId = pair.roomId;
        v.roomName = pair.roomName;
        v.itemId = pair.itemId;
        v.itemName = pair.itemName;
        v.newItem = pair.newItem;
        v.baselineStatus = pair.baselineStatus as ItemStatus;
        v.baselineNote = pair.baselineNote;
        if (pair.baselineItemId > 0) {
          const thumb = baseThumbs.get(pair.baselineItemId);
          v.baselineThumb = thumb !== undefined ? thumb : '';
        }
        const cur = curItemById.get(pair.itemId);
        if (cur !== undefined) {
          v.currentStatus = cur.status;
          v.currentNote = cur.noteFinal.length > 0 ? cur.noteFinal : cur.noteRaw;
        }
        const curThumb = curThumbs.get(pair.itemId);
        v.currentThumb = curThumb !== undefined ? curThumb : '';
        const marked = results.get(pair.itemId);
        v.result = marked !== undefined ? marked : '';
        views.push(v);
      }

      this.rows = views;
      this.baselineOnly = alignment.baselineOnly;
      const baseIns = baseAgg.inspection;
      this.baselineInfoText = `基线：${baseIns.reportNo.length > 0 ? baseIns.reportNo : '入住检查'}`
        + `${baseIns.frozenAt > 0 ? ` · ${DateUtil.formatDate(baseIns.frozenAt)} 冻结` : ''}`;
      this.recount();
      this.loading = false;
    } catch (err) {
      this.loading = false;
      this.loadError = '对比数据加载失败，请稍后重试';
    }
  }

  /** 三态确认：即时 upsert 落库并回显（FROZEN 只读不响应）。 */
  private async onResult(v: CompareRowView, value: string): Promise<void> {
    if (this.readonly || this.busyItemId !== 0 || v.result === value) {
      return;
    }
    this.busyItemId = v.itemId;
    const uiCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try {
      await new CompareRepo(uiCtx).upsert(this.inspectionId, v.itemId, value, '');
      v.result = value;
      // 数组引用更新 + ForEach key 含 result → 触发对应卡片重渲染
      this.rows = this.rows.slice();
      this.recount();
    } catch (err) {
      this.getUIContext().getPromptAction().showToast({ message: '保存失败，请重试' });
    } finally {
      this.busyItemId = 0;
    }
  }
}
