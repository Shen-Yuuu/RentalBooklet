import { common } from '@kit.AbilityKit';
import { InspectionParam } from '../common/NavParams';
import { Routes } from '../common/Routes';
import { DateUtil } from '../common/DateUtil';
import { HouseRepo } from '../data/repo/HouseRepo';
import { InspectionRepo } from '../data/repo/InspectionRepo';
import { ManifestRepo, VerifyItemResult, VerifyReport } from '../data/repo/ManifestRepo';
import { Inspection } from '../domain/model/Entities';
import { InspectionLauncher } from '../features/inspection/InspectionLauncher';

/** 归档详情信息行。 */
class ArchiveRow {
  label: string = '';
  value: string = '';
}

/**
 * 归档详情页（L10）：报告号/完整度快照/参与人/pdf 哈希展示 + 校验复查（manifest 重算比对）。
 * 措辞红线：复查结果不定性"篡改"，差异时提示人工核对。
 */
@Component
struct ArchiveDetailPage {
  @State inspectionId: number = 0;
  @State loading: boolean = true;
  @State loadError: string = '';
  @State houseName: string = '';
  @State rows: ArchiveRow[] = [];
  @State verifying: boolean = false;
  @State verifyReport: VerifyReport | null = null;
  @State verifyError: string = '';
  @State revisionBusy: boolean = false;
  private pathStack: NavPathStack = new NavPathStack();

  build() {
    NavDestination() {
      Column({ space: 12 }) {
        if (this.loading) {
          Column({ space: 10 }) {
            LoadingProgress().width(36).height(36)
            Text('正在加载归档信息…').fontSize(13).opacity(0.6)
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
                this.refresh();
              })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Column({ space: 12 }) {
              Column({ space: 8 }) {
                ForEach(this.rows, (row: ArchiveRow) => {
                  Row({ space: 10 }) {
                    Text(row.label).fontSize(13).opacity(0.6).width(92)
                    Text(row.value)
                      .fontSize(13)
                      .layoutWeight(1)
                      .maxLines(3)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .width('100%')
                }, (row: ArchiveRow) => `${row.label}-${row.value}`)
              }
              .padding(14)
              .borderRadius(12)
              .backgroundColor($r('app.color.card_bg'))
              .alignItems(HorizontalAlign.Start)
              .width('100%')

              Column({ space: 8 }) {
                Text('校验复查').fontSize(15).fontWeight(FontWeight.Medium).width('100%')
                Text('重新计算校验清单内每个文件的 SHA-256 并与登记值比对')
                  .fontSize(11)
                  .opacity(0.5)
                  .width('100%')

                if (this.verifying) {
                  Row({ space: 8 }) {
                    LoadingProgress().width(20).height(20)
                    Text('正在复查…').fontSize(13).opacity(0.6)
                  }
                  .width('100%')
                } else {
                  Button('校验复查')
                    .width('100%')
                    .backgroundColor($r('app.color.brand'))
                    .onClick(() => {
                      this.runVerify();
                    })
                }

                if (this.verifyError.length > 0) {
                  Text(this.verifyError).fontSize(13).fontColor($r('app.color.danger')).width('100%')
                }

                if (this.verifyReport !== null) {
                  this.verifyResultView(this.verifyReport)
                }
              }
              .padding(14)
              .borderRadius(12)
              .backgroundColor($r('app.color.card_bg'))
              .alignItems(HorizontalAlign.Start)
              .width('100%')

              Column({ space: 4 }) {
                Button(this.revisionBusy ? '正在创建修订…' : '创建修订版本')
                  .width('100%')
                  .backgroundColor($r('app.color.warning'))
                  .enabled(!this.revisionBusy)
                  .onClick(() => {
                    this.createRevision();
                  })
                Text('复制本记录生成修订草稿（R+1）进入检查执行页；原记录保持冻结原样，照片与表读数需重新采集')
                  .fontSize(11)
                  .opacity(0.45)
                  .width('100%')
                  .textAlign(TextAlign.Center)
              }
              .width('100%')
            }
            .width('100%')
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
    .title('归档详情')
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
      const p = ctx.pathInfo.param as InspectionParam | null;
      if (p !== null && p !== undefined && p.inspectionId > 0) {
        this.inspectionId = p.inspectionId;
        this.refresh();
      } else {
        this.loading = false;
        this.loadError = '页面参数缺失，请从记录页重新进入';
      }
    })
  }

  /** 校验复查结果区：全一致绿色；差异/缺失红色列出文件 + 固定人工核对文案；无清单提示。 */
  @Builder
  verifyResultView(report: VerifyReport) {
    Column({ space: 8 }) {
      if (!report.found) {
        Text('未找到校验清单')
          .fontSize(13)
          .fontColor($r('app.color.amber'))
          .width('100%')
      } else if (report.ok) {
        Text(`文件未发生变化（已比对 ${report.total} 个文件）`)
          .fontSize(13)
          .fontColor($r('app.color.success'))
          .width('100%')
      } else {
        Text('检测到文件变化，无法自动判断原因（也可能是正常转存失败），请人工核对')
          .fontSize(12)
          .fontColor($r('app.color.danger'))
          .width('100%')
        ForEach(this.badItemsOf(report), (item: VerifyItemResult) => {
          Text(this.badItemLabel(item))
            .fontSize(12)
            .fontColor($r('app.color.danger'))
            .width('100%')
        }, (item: VerifyItemResult) => `${item.relPath}-${item.status}`)
      }
      Text('校验值仅用于检测文件在生成后是否发生变化，不代表司法鉴定或官方存证。')
        .fontSize(10)
        .opacity(0.4)
        .width('100%')
    }
    .width('100%')
  }

  private badItemsOf(report: VerifyReport): VerifyItemResult[] {
    const list: VerifyItemResult[] = [];
    for (const item of report.items) {
      if (item.status !== 'OK') {
        list.push(item);
      }
    }
    return list;
  }

  private badItemLabel(item: VerifyItemResult): string {
    return item.status === 'MISSING' ? `文件缺失：${item.relPath}` : `内容已变化：${item.relPath}`;
  }

  /** 参与人 JSON 解析（容错）：'房东：张三　租客：李四'。 */
  private participantsText(json: string): string {
    if (json.length === 0) {
      return '未填写';
    }
    try {
      const parsed: object | null = JSON.parse(json);
      if (parsed === null || !Array.isArray(parsed)) {
        return '未填写';
      }
      const arr = parsed as Record<string, string>[];
      const parts: string[] = [];
      for (const p of arr) {
        const name = typeof p['name'] === 'string' ? p['name'] : '';
        const role = typeof p['role'] === 'string' ? p['role'] : '';
        if (name.length === 0) {
          continue;
        }
        parts.push(`${role === 'TENANT' ? '租客' : '房东'}：${name}`);
      }
      return parts.length > 0 ? parts.join('　') : '未填写';
    } catch (err) {
      return '未填写';
    }
  }

  private buildRows(ins: Inspection, houseName: string, sceneTitle: string): ArchiveRow[] {
    const rows: ArchiveRow[] = [];

    const reportRow = new ArchiveRow();
    reportRow.label = '报告号';
    reportRow.value = ins.reportNo.length > 0 ? ins.reportNo : '未生成';
    rows.push(reportRow);

    const houseRow = new ArchiveRow();
    houseRow.label = '房屋';
    houseRow.value = houseName;
    rows.push(houseRow);

    const sceneRow = new ArchiveRow();
    sceneRow.label = '场景';
    sceneRow.value = sceneTitle;
    rows.push(sceneRow);

    const frozenRow = new ArchiveRow();
    frozenRow.label = '冻结时间';
    frozenRow.value = ins.frozenAt > 0 ? DateUtil.formatDateTime(ins.frozenAt) : '未冻结';
    rows.push(frozenRow);

    const requiredRow = new ArchiveRow();
    requiredRow.label = '必须项完整度';
    requiredRow.value = `${Math.round(ins.completeRequired * 100)}%`;
    rows.push(requiredRow);

    const suggestedRow = new ArchiveRow();
    suggestedRow.label = '建议项完整度';
    suggestedRow.value = `${Math.round(ins.completeSuggested * 100)}%`;
    rows.push(suggestedRow);

    const participantsRow = new ArchiveRow();
    participantsRow.label = '参与人';
    participantsRow.value = this.participantsText(ins.participants);
    rows.push(participantsRow);

    const noteRow = new ArchiveRow();
    noteRow.label = '补充说明';
    noteRow.value = ins.extraNote.length > 0 ? ins.extraNote : '无';
    rows.push(noteRow);

    const pdfRow = new ArchiveRow();
    pdfRow.label = 'PDF 校验值';
    pdfRow.value = ins.pdfSha256.length > 0 ? ins.pdfSha256 : '未生成';
    rows.push(pdfRow);

    return rows;
  }

  private async refresh(): Promise<void> {
    this.loading = true;
    this.loadError = '';
    const uiCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try {
      const repo = new InspectionRepo(uiCtx);
      const ins = await repo.getById(this.inspectionId);
      if (ins === null) {
        this.loading = false;
        this.loadError = '未找到该检查记录，可能已被删除';
        return;
      }
      const house = await new HouseRepo(uiCtx).getById(ins.houseId);
      this.houseName = house !== null ? house.name : '';
      this.rows = this.buildRows(ins, this.houseName, InspectionLauncher.sceneTitleOf(ins.sceneKey));
      this.loading = false;
    } catch (err) {
      this.loading = false;
      this.loadError = '归档信息加载失败，请稍后重试';
    }
  }

  private async runVerify(): Promise<void> {
    if (this.verifying) {
      return;
    }
    this.verifying = true;
    this.verifyError = '';
    this.verifyReport = null;
    const uiCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try {
      const report = await new ManifestRepo(uiCtx).verify(this.inspectionId);
      this.verifyReport = report;
    } catch (err) {
      this.verifyError = '校验复查失败，请稍后重试';
    } finally {
      this.verifying = false;
    }
  }

  /** 创建修订版本（L10）：复制结构生成新 DRAFT，直接进入检查执行页。 */
  private async createRevision(): Promise<void> {
    if (this.revisionBusy) {
      return;
    }
    this.revisionBusy = true;
    const uiCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try {
      const newId = await new InspectionRepo(uiCtx).createRevision(this.inspectionId);
      this.getUIContext().getPromptAction().showToast({ message: '修订版本已创建' });
      this.pathStack.pushPathByName(Routes.INSPECTION, { inspectionId: newId } as InspectionParam);
    } catch (err) {
      const e = err as Error;
      this.getUIContext().getPromptAction()
        .showToast({ message: e.message.length > 0 ? e.message : '修订创建失败，请重试' });
    } finally {
      this.revisionBusy = false;
    }
  }
}

@Builder
export function archiveDetailBuilder() {
  ArchiveDetailPage();
}
