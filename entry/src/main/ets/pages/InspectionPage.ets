import { common } from '@kit.AbilityKit';
import { Routes } from '../common/Routes';
import { InspectionParam, MeterOcrParam, ReviewParam } from '../common/NavParams';
import { HandoverEntity, ItemEntity, MeterReadingEntity, RoomEntity } from '../domain/model/Entities';
import { InspectionStatus, ItemStatus, MeterType } from '../domain/model/CoreEnums';
import { InspectionRepo } from '../data/repo/InspectionRepo';
import { PhotoRepo } from '../data/repo/PhotoRepo';
import { TemplateEngine } from '../domain/template/TemplateEngine';
import { InspectionLauncher } from '../features/inspection/InspectionLauncher';
import { ItemEditSheet } from '../features/inspection/ItemEditSheet';
import { WideBreakpointWatcher } from '../common/BreakpointUtil';
import { WidgetService } from '../infra/widget/WidgetService';
import { Chevron } from '../common/ui/Theme';

@Builder
export function inspectionBuilder() {
  InspectionPage();
}

@Component
struct InspectionPage {
  @State inspectionId: number = 0;
  @State houseName: string = '';
  @State sceneTitle: string = '';
  @State frozen: boolean = false;
  @State rooms: RoomEntity[] = [];
  @State itemsByRoom: Map<number, ItemEntity[]> = new Map();
  @State currentRoom: number = 0;
  @State showSheet: boolean = false;
  @State editingItem: ItemEntity = new ItemEntity();
  @State editingNote: string = '';
  @State photoCounts: Map<number, number> = new Map();
  @State recordLocation: boolean = false;
  @State meterTypes: string[] = [];
  @State hasHandover: boolean = false;
  @State meterRows: Map<string, MeterReadingEntity> = new Map();
  @State handover: HandoverEntity | null = null;
  /** F2：宽屏（≥840vp）双栏布局开关。 */
  @State isWide: boolean = false;
  private pathStack: NavPathStack = new NavPathStack();
  private focusRoomId: number = 0;
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
      Column({ space: 10 }) {
        this.headerBlock()

        if (this.isWide) {
          Row({ space: 12 }) {
            this.wideRoomList()
            Column({ space: 10 }) {
              this.handoverCard()
              this.itemsArea()
            }
            .layoutWeight(1)
            .height('100%')
          }
          .width('100%')
          .layoutWeight(1)
          .alignItems(VerticalAlign.Top)
        } else {
          this.roomChips()
          this.handoverCard()
          this.itemsArea()
        }

        this.bottomButtons()
      }
      .padding(16)
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.bg_page'))
    }
    .title('检查执行')
    .onShown(() => {
      // 从表读数/完整度页返回时刷新徽标与数据，并消费"一键跳转"定位信号
      this.reloadHandoverEntries();
      this.consumeFocusSignal();
    })
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
      const p = ctx.pathInfo.param as InspectionParam | null;
      if (p !== null && p !== undefined) {
        this.inspectionId = p.inspectionId;
        this.focusRoomId = p.focusRoomId === undefined ? 0 : p.focusRoomId;
        this.load();
      }
    })
    .bindSheet($$this.showSheet, this.sheetBuilder(), { height: 380 })
  }

  /** 标题 + 总进度条（宽窄屏共用）。 */
  @Builder
  headerBlock() {
    Column({ space: 10 }) {
      Text(`${this.houseName} · ${this.sceneTitle}`)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .width('100%')

      Row({ space: 10 }) {
        Text(this.frozen ? '已冻结 · 只读' : `完成 ${this.doneTotal()}/${this.itemTotal()}`)
          .fontSize(13)
          .opacity(0.7)
        Progress({ value: this.doneTotal(), total: Math.max(1, this.itemTotal()), type: ProgressType.Linear })
          .layoutWeight(1)
      }
      .width('100%')
    }
    .width('100%')
  }

  /** 窄屏：房间横向胶囊滚动条。 */
  @Builder
  roomChips() {
    Scroll() {
      Row({ space: 8 }) {
        ForEach(this.rooms, (room: RoomEntity, idx: number) => {
          Text(`${room.name} ${this.doneOf(room.id)}/${this.countOf(room.id)}`)
            .fontSize(13)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(16)
            .backgroundColor(this.currentRoom === idx ? $r('app.color.brand') : $r('app.color.card_bg'))
            .fontColor(this.currentRoom === idx ? Color.White : $r('app.color.text_pri'))
            .onClick(() => {
              this.currentRoom = idx;
            })
        }, (room: RoomEntity) => `${room.id}`)
      }
    }
    .scrollable(ScrollDirection.Horizontal)
    .width('100%')
  }

  /** 宽屏左栏：房间垂直列表（名称 + 完成小字）。 */
  @Builder
  wideRoomList() {
    List({ space: 6 }) {
      ForEach(this.rooms, (room: RoomEntity, idx: number) => {
        ListItem() {
          Column({ space: 2 }) {
            Text(room.name)
              .fontSize(14)
              .fontWeight(this.currentRoom === idx ? FontWeight.Medium : FontWeight.Normal)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(`${this.doneOf(room.id)}/${this.countOf(room.id)} 项`)
              .fontSize(11)
              .opacity(0.6)
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding(10)
          .borderRadius(10)
          .backgroundColor(this.currentRoom === idx ? $r('app.color.brand') : $r('app.color.card_bg'))
          .onClick(() => {
            this.currentRoom = idx;
          })
        }
      }, (room: RoomEntity) => `${room.id}`)
    }
    .width(180)
    .height('100%')
  }

  /** 交接数据入口卡（表读数 + 钥匙门禁）。 */
  @Builder
  handoverCard() {
    if (this.meterTypes.length > 0 || this.hasHandover) {
      Column({ space: 0 }) {
        Text('交接数据')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .opacity(0.7)
          .width('100%')
          .padding({ bottom: 4 })

        ForEach(this.meterTypes, (mt: string) => {
          this.meterEntryRow(mt)
        }, (mt: string) => mt)

        if (this.hasHandover) {
          this.handoverEntryRow()
        }
      }
      .width('100%')
      .padding(10)
      .borderRadius(12)
      .backgroundColor($r('app.color.card_bg'))
    }
  }

  /** 当前房间检查项列表（或空态占位）。 */
  @Builder
  itemsArea() {
    if (this.currentRoomItems().length === 0) {
      Column({ space: 8 }) {
        Text('该房间没有检查项').fontSize(14).opacity(0.6)
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    } else {
      List({ space: 8 }) {
        ForEach(this.currentRoomItems(), (item: ItemEntity) => {
          ListItem() {
            Row({ space: 8 }) {
              Column({ space: 2 }) {
                Row({ space: 6 }) {
                  Text(item.name).fontSize(15)
                  if (!item.required) {
                    Text('选').fontSize(10).opacity(0.5)
                      .border({ width: 1, color: $r('app.color.divider'), radius: 4 })
                      .padding({ left: 3, right: 3 })
                  }
                }
                Row({ space: 6 }) {
                  if (item.noteRaw.length > 0) {
                    Text(`备注：${item.noteRaw}`)
                      .fontSize(11)
                      .opacity(0.6)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  if (this.photoCountOf(item.id) > 0) {
                    Text(`照片${this.photoCountOf(item.id)}`).fontSize(11).fontColor($r('app.color.brand'))
                  }
                }
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              .onClick(() => {
                this.openSheet(item);
              })

              this.miniChip('正常', ItemStatus.OK, item, $r('app.color.success'))
              this.miniChip('问题', ItemStatus.ISSUE, item, $r('app.color.warning'))
              this.miniChip('不适用', ItemStatus.NA, item, $r('app.color.text_ter'))
            }
            .width('100%')
            .padding(12)
            .borderRadius(12)
            .backgroundColor($r('app.color.card_bg'))
          }
        }, (item: ItemEntity) => `${item.id}-${item.status}`)
      }
      .layoutWeight(1)
      .width('100%')
    }
  }

  /** 底部操作区：完整度检查按钮 + 房间导航按钮。 */
  @Builder
  bottomButtons() {
    Column({ space: 8 }) {
      if (!this.frozen) {
        Button('完整度检查')
          .width('100%')
          .height(36)
          .fontSize(13)
          .onClick(() => {
            this.pathStack.pushPathByName(Routes.REVIEW, { inspectionId: this.inspectionId } as ReviewParam);
          })
      }

      Row({ space: 8 }) {
        Button('上一间')
          .layoutWeight(1)
          .enabled(this.currentRoom > 0 && !this.frozen)
          .onClick(() => {
            this.currentRoom--;
          })
        Button('下一个未检查')
          .layoutWeight(2)
          .enabled(!this.frozen)
          .backgroundColor($r('app.color.brand'))
          .onClick(() => {
            this.jumpNextPending();
          })
        Button('下一间')
          .layoutWeight(1)
          .enabled(this.currentRoom < this.rooms.length - 1 && !this.frozen)
          .onClick(() => {
            this.currentRoom++;
          })
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  sheetBuilder() {
    // 以 showSheet 条件挂载：每次打开都是全新实例（修复复用残留——上一项备注写入下一项），
    // 关闭（含下滑）即卸载触发 aboutToDisappear 停止录音
    if (this.showSheet && this.editingItem.id > 0) {
      ItemEditSheet({
        itemName: this.editingItem.name,
        itemStatus: this.editingItem.status,
        initNote: this.editingNote,
        inspectionId: this.inspectionId,
        itemId: this.editingItem.id,
        roomId: this.editingItem.roomId,
        recordLocation: this.recordLocation,
        frozen: this.frozen,
        onStatus: (s: ItemStatus) => {
          this.setItemStatus(this.editingItem, s);
        },
        onSaveNote: (raw: string, final: string) => {
          this.saveNote(this.editingItem, raw, final);
        },
        onPhotosChanged: () => {
          this.reloadPhotoCounts();
        }
      })
    }
  }

  @Builder
  miniChip(label: string, st: ItemStatus, item: ItemEntity, color: ResourceColor) {
    Text(label)
      .fontSize(11)
      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
      .borderRadius(12)
      .backgroundColor(item.status === st ? color : Color.Transparent)
      .fontColor(item.status === st ? Color.White : $r('app.color.text_sec'))
      .border({ width: 1, color: item.status === st ? color : $r('app.color.divider'), radius: 12 })
      .enabled(!this.frozen)
      .onClick(() => {
        this.setItemStatus(item, st);
      })
  }

  /** 表读数入口行：类型名 + 状态徽标，点击进表读数确认页（FROZEN 禁用）。 */
  @Builder
  meterEntryRow(mt: string) {
    Row({ space: 8 }) {
      Text(this.meterNameOf(mt))
        .fontSize(14)
        .layoutWeight(1)
      Text(this.meterStatusOf(mt))
        .fontSize(11)
        .padding({ left: 8, right: 8, top: 3, bottom: 3 })
        .borderRadius(10)
        .backgroundColor(this.meterBadgeColorOf(mt))
        .fontColor(Color.White)
      Chevron()
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
    .opacity(this.frozen ? 0.55 : 1)
    .enabled(!this.frozen)
    .onClick(() => {
      if (this.frozen) {
        return;
      }
      this.pathStack.pushPathByName(Routes.METER_OCR,
        { inspectionId: this.inspectionId, meterType: mt } as MeterOcrParam);
    })
  }

  /** 钥匙门禁入口行：点击跳完整度页（交接数据编辑区在页顶）。 */
  @Builder
  handoverEntryRow() {
    Row({ space: 8 }) {
      Text('钥匙门禁')
        .fontSize(14)
        .layoutWeight(1)
      Text(this.handoverStatusOf())
        .fontSize(11)
        .padding({ left: 8, right: 8, top: 3, bottom: 3 })
        .borderRadius(10)
        .backgroundColor(this.handoverBadgeColorOf())
        .fontColor(Color.White)
      Chevron()
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
    .opacity(this.frozen ? 0.55 : 1)
    .enabled(!this.frozen)
    .onClick(() => {
      if (this.frozen) {
        return;
      }
      this.pathStack.pushPathByName(Routes.REVIEW, { inspectionId: this.inspectionId } as ReviewParam);
    })
  }

  private meterNameOf(mt: string): string {
    if (mt === MeterType.WATER) {
      return '水表';
    }
    if (mt === MeterType.ELECTRICITY) {
      return '电表';
    }
    if (mt === MeterType.GAS) {
      return '燃气表';
    }
    return mt;
  }

  /** 状态徽标：无表具(灰) > 已确认(绿) > 未登记(橙)。 */
  private meterStatusOf(mt: string): string {
    const m = this.meterRows.get(mt);
    if (m !== undefined) {
      if (m.naFlag) {
        return '无表具';
      }
      if (m.confirmed) {
        return '已确认';
      }
    }
    return '未登记';
  }

  private meterBadgeColorOf(mt: string): ResourceColor {
    const m = this.meterRows.get(mt);
    if (m !== undefined) {
      if (m.naFlag) {
        return $r('app.color.text_ter');
      }
      if (m.confirmed) {
        return $r('app.color.success');
      }
    }
    return $r('app.color.warning');
  }

  private handoverStatusOf(): string {
    return this.handover !== null && this.handover.confirmed ? '已确认' : '未登记';
  }

  private handoverBadgeColorOf(): ResourceColor {
    return this.handover !== null && this.handover.confirmed
      ? $r('app.color.success') : $r('app.color.warning');
  }

  /** 表读数/交接状态轻量重载：从子页返回时刷新入口徽标。 */
  private reloadHandoverEntries(): void {
    if (this.inspectionId <= 0) {
      return;
    }
    const uiCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const repo = new InspectionRepo(uiCtx);
    repo.listMeters(this.inspectionId).then((list: MeterReadingEntity[]) => {
      const map = new Map<string, MeterReadingEntity>();
      for (const m of list) {
        const cur = map.get(m.meterType);
        if (cur === undefined || cur.id < m.id) {
          map.set(m.meterType, m);
        }
      }
      this.meterRows = map;
    });
    repo.getHandover(this.inspectionId).then((h: HandoverEntity | null) => {
      this.handover = h;
    });
  }

  private currentRoomItems(): ItemEntity[] {
    if (this.rooms.length === 0 || this.currentRoom >= this.rooms.length) {
      return [];
    }
    const list = this.itemsByRoom.get(this.rooms[this.currentRoom].id);
    return list === undefined ? [] : list;
  }

  private itemTotal(): number {
    let n = 0;
    this.itemsByRoom.forEach((list: ItemEntity[]) => {
      n += list.length;
    });
    return n;
  }

  private doneTotal(): number {
    let n = 0;
    this.itemsByRoom.forEach((list: ItemEntity[]) => {
      for (const it of list) {
        if (it.status !== ItemStatus.PENDING) {
          n++;
        }
      }
    });
    return n;
  }

  private doneOf(roomId: number): number {
    const list = this.itemsByRoom.get(roomId);
    if (list === undefined) {
      return 0;
    }
    let n = 0;
    for (const it of list) {
      if (it.status !== ItemStatus.PENDING) {
        n++;
      }
    }
    return n;
  }

  private countOf(roomId: number): number {
    const list = this.itemsByRoom.get(roomId);
    return list === undefined ? 0 : list.length;
  }

  private photoCountOf(itemId: number): number {
    const c = this.photoCounts.get(itemId);
    return c === undefined ? 0 : c;
  }

  private reloadPhotoCounts(): void {
    const uiCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    new PhotoRepo(uiCtx).countsByInspection(this.inspectionId).then((map: Map<number, number>) => {
      this.photoCounts = map;
    });
  }

  private jumpNextPending(): void {
    const n = this.rooms.length;
    for (let step = 0; step < n; step++) {
      const idx = (this.currentRoom + step) % n;
      const list = this.itemsByRoom.get(this.rooms[idx].id);
      if (list === undefined) {
        continue;
      }
      for (const it of list) {
        if (it.status === ItemStatus.PENDING) {
          this.currentRoom = idx;
          this.openSheet(it);
          return;
        }
      }
    }
  }

  private openSheet(item: ItemEntity): void {
    if (this.frozen) {
      return;
    }
    this.editingItem = item;
    this.editingNote = item.noteRaw;
    this.showSheet = true;
  }

  private setItemStatus(item: ItemEntity, status: ItemStatus): void {
    if (this.frozen) {
      return;
    }
    const uiCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    new InspectionRepo(uiCtx).updateItemStatus(item.id, status).then(() => {
      const list = this.itemsByRoom.get(item.roomId);
      if (list !== undefined) {
        for (const it of list) {
          if (it.id === item.id) {
            it.status = status;
          }
        }
      }
      this.itemsByRoom = new Map(this.itemsByRoom);
      AppStorage.setOrCreate('home_dirty', Date.now());
      // F1：进度变化主动刷新绑定的服务卡片（静默容错）
      WidgetService.refreshProgress(uiCtx, this.inspectionId);
    });
  }

  private saveNote(item: ItemEntity, raw: string, final: string): void {
    if (this.frozen) {
      return;
    }
    const uiCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    new InspectionRepo(uiCtx).updateItemNote(item.id, raw, final).then(() => {
      const list = this.itemsByRoom.get(item.roomId);
      if (list !== undefined) {
        for (const it of list) {
          if (it.id === item.id) {
            it.noteRaw = raw;
            it.noteFinal = final;
          }
        }
      }
      this.itemsByRoom = new Map(this.itemsByRoom);
      this.showSheet = false;
      AppStorage.setOrCreate('home_dirty', Date.now());
    });
  }

  private load(): void {
    const uiCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    new InspectionRepo(uiCtx).getAggregate(this.inspectionId).then((agg) => {
      if (agg === null) {
        return;
      }
      this.rooms = agg.rooms;
      this.itemsByRoom = agg.itemsByRoom;
      this.houseName = agg.house.name;
      this.recordLocation = agg.house.recordLocation;
      this.sceneTitle = InspectionLauncher.sceneTitleOf(agg.inspection.sceneKey);
      this.frozen = agg.inspection.status === InspectionStatus.FROZEN;
      // 模板含 meters/handover 时展示「交接数据」入口卡片区（custom 等场景回退为不展示）
      let meters: string[] = [];
      let hasHandover = false;
      try {
        const tpl = TemplateEngine.getBuiltin(agg.inspection.sceneKey);
        for (const m of tpl.meters) {
          meters.push(m);
        }
        hasHandover = tpl.handover;
      } catch (err) {
        meters = [];
        hasHandover = false;
      }
      this.meterTypes = meters;
      this.hasHandover = hasHandover;
      this.reloadHandoverEntries();
      this.applyFocusRoom();
    });
    this.reloadPhotoCounts();
  }

  /** 完整度页跳转回传：定位到指定房间（一次性）。 */
  private applyFocusRoom(): void {
    if (this.focusRoomId <= 0) {
      return;
    }
    for (let idx = 0; idx < this.rooms.length; idx++) {
      if (this.rooms[idx].id === this.focusRoomId) {
        this.currentRoom = idx;
        break;
      }
    }
    this.focusRoomId = 0;
  }

  /**
   * 完整度页"一键跳转"回传：ReviewPage pop 回本页前经 AppStorage 投递目标信号
   * （inspection_focus_item 指定项 → 定位所在房间；inspection_focus_room 房间级遗漏），
   * 定位后重载数据。替代旧的 replace 方案，避免栈内残留旧执行页实例。
   */
  private consumeFocusSignal(): void {
    const focusItem = AppStorage.get<number>('inspection_focus_item');
    const focusRoom = AppStorage.get<number>('inspection_focus_room');
    const hasItem = focusItem !== undefined && focusItem > 0;
    const hasRoom = focusRoom !== undefined && focusRoom > 0;
    if (!hasItem && !hasRoom) {
      return;
    }
    AppStorage.setOrCreate('inspection_focus_item', 0);
    AppStorage.setOrCreate('inspection_focus_room', 0);
    if (hasItem) {
      let roomId: number = 0;
      this.itemsByRoom.forEach((list: ItemEntity[], rid: number) => {
        if (roomId === 0) {
          for (const it of list) {
            if (it.id === focusItem) {
              roomId = rid;
              break;
            }
          }
        }
      });
      if (roomId > 0) {
        this.focusRoomId = roomId;
      }
    } else if (focusRoom !== undefined && focusRoom > 0) {
      this.focusRoomId = focusRoom;
    }
    this.load();
  }
}
