import { common } from '@kit.AbilityKit';
import { DisclaimerDialog } from './DisclaimerDialog';
import { ExportOutcome, PickerService } from '../../infra/media/PickerService';
import { WidgetService } from '../../infra/widget/WidgetService';
import { DB_NAME } from '../../data/db/DbManager';
import { InspectionRepo } from '../../data/repo/InspectionRepo';
import { StorageStat } from '../../common/StorageStat';
import { SizeFormat } from '../../common/SizeFormat';
import { RecordSummary } from '../../domain/model/Entities';
import { InspectionStatus } from '../../domain/model/CoreEnums';
import { DateUtil } from '../../common/DateUtil';
import { Theme, PressCard, Chevron, IconBadge, StatusBadge } from '../../common/ui/Theme';

/** 存储进度条参考上限（实际占用超过时以实际值为准）。 */
const STORAGE_PROGRESS_BASE: number = 100 * 1024 * 1024;

@Component
export struct SettingsTab {
  @State showDisclaimer: boolean = false;
  @State exporting: boolean = false;
  /** F3：草稿清理列表（home_dirty 变化即重载）。 */
  @StorageProp('home_dirty') @Watch('reloadDrafts') homeDirty: number = 0;
  @State drafts: RecordSummary[] = [];
  @State storageText: string = '正在统计存储占用…';
  @State storageBytes: number = 0;
  @State storageMax: number = STORAGE_PROGRESS_BASE;
  @State deletingDraftId: number = 0;

  aboutToAppear(): void {
    this.reloadDrafts();
    this.refreshStorage();
  }

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message });
  }

  /** F3 存储看板：检查数据 = 照片目录 + 数据库（含 wal/shm）。 */
  private refreshStorage(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const dbBytes = StorageStat.dbSize(ctx.databaseDir, DB_NAME);
    const mediaBytes = StorageStat.dirSize(`${ctx.filesDir}/insp`);
    const total = mediaBytes + dbBytes;
    this.storageBytes = total;
    this.storageMax = Math.max(STORAGE_PROGRESS_BASE, total);
    this.storageText = `检查数据共 ${SizeFormat.format(total)}`
      + `（照片 ${SizeFormat.format(mediaBytes)} · 数据库 ${SizeFormat.format(dbBytes)}）`;
  }

  private reloadDrafts(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    new InspectionRepo(ctx).listSummaries().then((list: RecordSummary[]) => {
      const drafts: RecordSummary[] = [];
      for (const s of list) {
        if (s.status !== InspectionStatus.FROZEN) {
          drafts.push(s);
        }
      }
      this.drafts = drafts;
    });
  }

  /** F3 删除确认：危险操作二次确认，删除按钮红色。 */
  private confirmDeleteDraft(s: RecordSummary): void {
    this.getUIContext().showAlertDialog({
      title: '删除草稿',
      message: `确定删除「${s.houseName}」的检查草稿吗？相关照片与记录将被清除，且无法恢复。`,
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: $r('app.color.danger'),
        action: () => {
          this.deleteDraft(s);
        }
      }
    });
  }

  private deleteDraft(s: RecordSummary): void {
    if (this.deletingDraftId !== 0) {
      return;
    }
    this.deletingDraftId = s.inspectionId;
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    new InspectionRepo(ctx).deleteDraft(s.inspectionId).then(() => {
      this.deletingDraftId = 0;
      this.toast('草稿已删除');
      this.reloadDrafts();
      this.refreshStorage();
      // 绑定该记录的服务卡片转为"记录不存在"提示态
      WidgetService.refreshProgress(ctx);
    }).catch((err: Error) => {
      this.deletingDraftId = 0;
      this.toast(err.message.length > 0 ? err.message : '删除失败，请重试');
    });
  }

  /** 数据逃生口：数据库 + 照片一次性导出到用户选择目录（免权限）。 */
  private exportAllData(): void {
    if (this.exporting) {
      return;
    }
    this.exporting = true;
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const dbPath = `${ctx.databaseDir}/${DB_NAME}`;
    PickerService.exportAllData(ctx, dbPath).then((outcome: ExportOutcome) => {
      this.exporting = false;
      if (outcome.exportedCount === 0) {
        return; // 用户取消，静默返回
      }
      if (outcome.degraded) {
        this.toast(`已导出数据库 ${outcome.exportedCount} 个文件（照片较多，请通过报告分享导出）`);
      } else {
        this.toast(`导出成功，共 ${outcome.exportedCount} 个文件`);
      }
    }).catch((err: Error) => {
      this.exporting = false;
      this.toast(`导出失败：${err.message}`);
    });
  }

  @Builder
  storageCard() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        IconBadge($r('sys.symbol.archivebox'), $r('app.color.brand'), $r('app.color.brand_light'))
        Text('存储占用')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_pri'))
          .layoutWeight(1)
      }
      .width('100%')
      Progress({ value: this.storageBytes, total: this.storageMax, type: ProgressType.Linear })
        .color($r('app.color.brand'))
        .backgroundColor($r('app.color.bg_disabled'))
        .width('100%')
        .height(6)
      Text(this.storageText)
        .fontSize(Theme.fontCaption)
        .fontColor($r('app.color.text_sec'))
        .width('100%')
      Text('数据仅存本机，建议定期导出到安全位置')
        .fontSize(11)
        .fontColor($r('app.color.text_ter'))
        .width('100%')
    }
    .padding(16)
    .borderRadius(Theme.radiusCard)
    .backgroundColor($r('app.color.card_bg'))
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  draftItem(s: RecordSummary) {
    Row({ space: 10 }) {
      IconBadge($r('sys.symbol.timer'), $r('app.color.warning'), $r('app.color.warning_light'))
      Column({ space: 3 }) {
        Text(s.houseName)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_pri'))
          .maxLines(1)
        Text(`${DateUtil.formatDate(s.startedAt)} 开始 · 已完成 ${s.doneItems}/${s.totalItems} 项`)
          .fontSize(Theme.fontCaption)
          .fontColor($r('app.color.text_sec'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.deletingDraftId === s.inspectionId) {
        LoadingProgress()
          .width(18)
          .height(18)
      } else {
        Button('删除')
          .fontSize(12)
          .height(28)
          .padding({ left: 12, right: 12 })
          .backgroundColor($r('app.color.danger'))
          .onClick(() => {
            this.confirmDeleteDraft(s);
          })
      }
    }
    .width('100%')
    .padding(14)
    .borderRadius(Theme.radiusCard)
    .backgroundColor($r('app.color.card_bg'))
  }

  @Builder
  entryRow(label: string, icon: Resource, onTap: () => void) {
    Row({ space: 12 }) {
      IconBadge(icon, $r('app.color.text_sec'), $r('app.color.bg_disabled'))
      Text(label)
        .fontSize(16)
        .fontColor($r('app.color.text_pri'))
        .layoutWeight(1)
      Chevron()
    }
    .width('100%')
    .padding(14)
    .borderRadius(Theme.radiusCard)
    .backgroundColor($r('app.color.card_bg'))
    .onClick(() => {
      onTap();
    })
  }

  /** 导出行：进行中显示 Loading，否则显示 Chevron。 */
  @Builder
  exportRow() {
    Row({ space: 12 }) {
      IconBadge($r('sys.symbol.share'), $r('app.color.text_sec'), $r('app.color.bg_disabled'))
      Text('导出全部数据（数据库与照片）')
        .fontSize(16)
        .fontColor($r('app.color.text_pri'))
        .layoutWeight(1)
      if (this.exporting) {
        LoadingProgress()
          .width(18)
          .height(18)
      } else {
        Chevron()
      }
    }
    .width('100%')
    .padding(14)
    .borderRadius(Theme.radiusCard)
    .backgroundColor($r('app.color.card_bg'))
    .onClick(() => {
      this.exportAllData();
    })
  }

  /** 说明行：右侧固定小字说明、不可点击。 */
  @Builder
  noteRow(label: string, icon: Resource, note: string) {
    Row({ space: 12 }) {
      IconBadge(icon, $r('app.color.text_sec'), $r('app.color.bg_disabled'))
      Text(label)
        .fontSize(16)
        .fontColor($r('app.color.text_pri'))
        .layoutWeight(1)
      Text(note)
        .fontSize(13)
        .fontColor($r('app.color.text_ter'))
    }
    .width('100%')
    .padding(14)
    .borderRadius(Theme.radiusCard)
    .backgroundColor($r('app.color.card_bg'))
  }

  build() {
    Column({ space: 12 }) {
      Text('设置')
        .fontSize(Theme.fontTitle)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_pri'))
        .width('100%')

      List({ space: 8 }) {
        ListItem() {
          this.exportRow()
        }

        ListItem() {
          this.storageCard()
        }

        if (this.drafts.length > 0) {
          ListItem() {
            Text(`草稿清理（${this.drafts.length}）`)
              .fontSize(Theme.fontBody)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_sec'))
              .width('100%')
              .margin({ top: 4 })
          }

          ForEach(this.drafts, (s: RecordSummary) => {
            ListItem() {
              this.draftItem(s)
            }
          }, (s: RecordSummary) => `draft-${s.inspectionId}-${s.doneItems}-${this.deletingDraftId}`)
        }

        ListItem() {
          this.entryRow('关于与免责声明', $r('sys.symbol.info_circle'), () => {
            this.showDisclaimer = true;
          })
        }

        ListItem() {
          this.noteRow('位置记录', $r('sys.symbol.map'), '默认关闭 · M2 里程碑提供')
        }

        ListItem() {
          this.noteRow('版本', $r('sys.symbol.doc_text'), '1.0.0 (M0)')
        }
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .padding(16)
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
    .bindContentCover($$this.showDisclaimer, this.disclaimerView(), {
      onWillDismiss: (action: DismissContentCoverAction) => {
        // 必须通过按钮关闭
      }
    })
  }

  @Builder
  disclaimerView() {
    DisclaimerDialog({
      onAccept: () => {
        this.showDisclaimer = false;
      },
      onDecline: () => {
        this.showDisclaimer = false;
      }
    })
  }
}
