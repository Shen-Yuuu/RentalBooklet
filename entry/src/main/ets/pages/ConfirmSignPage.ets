import { common } from '@kit.AbilityKit';
import { Routes } from '../common/Routes';
import { ConfirmSignParam, ReportPreviewParam } from '../common/NavParams';
import { DateUtil } from '../common/DateUtil';
import { InspectionRepo } from '../data/repo/InspectionRepo';
import { WidgetService } from '../infra/widget/WidgetService';
import { CompletenessEngine, CompletenessResult } from '../domain/completeness/CompletenessEngine';
import { HandoverEntity, Inspection, ItemEntity, MeterReadingEntity } from '../domain/model/Entities';
import { InspectionStatus, ItemStatus, MeterType } from '../domain/model/CoreEnums';
import { InspectionLauncher } from '../features/inspection/InspectionLauncher';

/** 参与人条目（participants JSON 数组元素，v1 为文本姓名确认，签名画板随 v1.1）。 */
class Participant {
  role: string = '';
  name: string = '';
}

/** 摘要行：label + 值。 */
class SummaryRow {
  label: string = '';
  value: string = '';
}

/**
 * 确认与冻结页（L8，v1.1：参与人文本姓名确认，签名画板推迟 v1.1+）。
 * 冻结成功跳报告预览；FROZEN 态进入时只读展示。
 */
@Component
struct ConfirmSignPage {
  @State inspectionId: number = 0;
  @State loading: boolean = true;
  @State loadError: string = '';
  @State frozen: boolean = false;
  @State houseName: string = '';
  @State sceneTitle: string = '';
  @State startedAtText: string = '';
  @State issueCount: number = 0;
  @State summaryRows: SummaryRow[] = [];
  @State landlordName: string = '';
  @State tenantName: string = '';
  @State extraNote: string = '';
  @State requiredPct: number = 100;
  @State suggestedPct: number = 100;
  @State freezing: boolean = false;
  private pathStack: NavPathStack = new NavPathStack();

  build() {
    NavDestination() {
      Column({ space: 12 }) {
        if (this.loading) {
          Column({ space: 10 }) {
            LoadingProgress().width(36).height(36)
            Text('正在加载摘要…').fontSize(13).opacity(0.6)
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
              Text(`${this.houseName} · ${this.sceneTitle}`)
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .width('100%')

              Column({ space: 8 }) {
                Text('记录摘要').fontSize(15).fontWeight(FontWeight.Medium).width('100%')
                ForEach(this.summaryRows, (row: SummaryRow) => {
                  Row({ space: 10 }) {
                    Text(row.label).fontSize(13).opacity(0.6).width(92)
                    Text(row.value)
                      .fontSize(13)
                      .layoutWeight(1)
                      .maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .width('100%')
                }, (row: SummaryRow) => `${row.label}-${row.value}`)
              }
              .padding(14)
              .borderRadius(12)
              .backgroundColor($r('app.color.card_bg'))
              .alignItems(HorizontalAlign.Start)
              .width('100%')

              Column({ space: 8 }) {
                Text('参与人确认').fontSize(15).fontWeight(FontWeight.Medium).width('100%')
                Text('填写双方姓名即完成确认（选填），签名画板将在后续版本开放')
                  .fontSize(11)
                  .opacity(0.5)
                  .width('100%')
                TextInput({ placeholder: '房东姓名（选填）', text: this.landlordName })
                  .enabled(!this.frozen)
                  .onChange((v: string) => {
                    this.landlordName = v;
                  })
                TextInput({ placeholder: '租客姓名（选填）', text: this.tenantName })
                  .enabled(!this.frozen)
                  .onChange((v: string) => {
                    this.tenantName = v;
                  })
              }
              .padding(14)
              .borderRadius(12)
              .backgroundColor($r('app.color.card_bg'))
              .alignItems(HorizontalAlign.Start)
              .width('100%')

              Column({ space: 8 }) {
                Text('补充说明').fontSize(15).fontWeight(FontWeight.Medium).width('100%')
                TextArea({ text: this.extraNote, placeholder: '其他需要随记录保存的说明（选填）' })
                  .enabled(!this.frozen)
                  .height(72)
                  .width('100%')
                  .onChange((v: string) => {
                    this.extraNote = v;
                  })
              }
              .padding(14)
              .borderRadius(12)
              .backgroundColor($r('app.color.card_bg'))
              .alignItems(HorizontalAlign.Start)
              .width('100%')

              Column({ space: 4 }) {
                Text(`完整度快照：必须项 ${this.requiredPct}% · 建议项 ${this.suggestedPct}%`)
                  .fontSize(12)
                  .opacity(0.55)
                  .width('100%')
                Text('冻结后记录不可修改，校验值不代表司法鉴定或官方存证')
                  .fontSize(11)
                  .opacity(0.4)
                  .width('100%')
              }
              .width('100%')
            }
            .width('100%')
          }
          .layoutWeight(1)
          .width('100%')

          if (this.frozen) {
            Button('该记录已冻结')
              .width('100%')
              .enabled(false)
          } else if (this.freezing) {
            Row({ space: 8 }) {
              LoadingProgress().width(20).height(20)
              Text('正在冻结…').fontSize(14)
            }
            .width('100%')
            .height(40)
            .borderRadius(20)
            .backgroundColor($r('app.color.card_bg'))
            .justifyContent(FlexAlign.Center)
          } else {
            Button('冻结本次记录')
              .width('100%')
              .backgroundColor($r('app.color.brand'))
              .onClick(() => {
                this.confirmFreeze();
              })
          }
        }
      }
      .padding(16)
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.bg_page'))
    }
    .title('确认与签名')
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
      const p = ctx.pathInfo.param as ConfirmSignParam | null;
      if (p !== null && p !== undefined && p.inspectionId > 0) {
        this.inspectionId = p.inspectionId;
        this.refresh();
      } else {
        this.loading = false;
        this.loadError = '页面参数缺失，请从完整度页重新进入';
      }
    })
  }

  /** 摘要区装配：检查时间/问题总数/三表读数/钥匙门禁。 */
  private buildSummaryRows(inspection: Inspection, issueCount: number,
    meters: MeterReadingEntity[], handover: HandoverEntity | null): SummaryRow[] {
    const rows: SummaryRow[] = [];
    const timeRow = new SummaryRow();
    timeRow.label = '检查时间';
    timeRow.value = DateUtil.formatDateTime(inspection.startedAt);
    rows.push(timeRow);

    const issueRow = new SummaryRow();
    issueRow.label = '问题总数';
    issueRow.value = `${issueCount} 项`;
    rows.push(issueRow);

    const meterTypes: string[] = [MeterType.WATER, MeterType.ELECTRICITY, MeterType.GAS];
    const meterNames: string[] = ['水表', '电表', '燃气表'];
    for (let i = 0; i < meterTypes.length; i++) {
      const row = new SummaryRow();
      row.label = meterNames[i];
      let value = '未登记';
      for (const m of meters) {
        // 确认门闩红线：confirmed=0 的读数绝不进摘要
        if (m.meterType !== meterTypes[i] || !m.confirmed) {
          continue;
        }
        if (m.naFlag) {
          value = '无表具';
          break;
        }
        value = m.valueText.length > 0 ? m.valueText : '已确认';
        break;
      }
      row.value = value;
      rows.push(row);
    }

    const handoverRow = new SummaryRow();
    handoverRow.label = '钥匙门禁';
    if (handover !== null && handover.confirmed) {
      // 确认门闩：仅 confirmed 交接进摘要；"无需记录"语义原样展示
      handoverRow.value = handover.isNoNeed() ? '无需记录'
        : `钥匙 ${handover.keyCount} 把 · 门禁卡 ${handover.accessCardCount} 张`;
    } else {
      handoverRow.value = '未登记';
    }
    rows.push(handoverRow);
    return rows;
  }

  private async refresh(): Promise<void> {
    this.loading = true;
    this.loadError = '';
    const uiCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const repo = new InspectionRepo(uiCtx);
    try {
      const agg = await repo.getAggregate(this.inspectionId);
      if (agg === null) {
        this.loading = false;
        this.loadError = '未找到该检查记录，可能已被删除';
        return;
      }
      const meters = await repo.listMeters(this.inspectionId);
      const handover = await repo.getHandover(this.inspectionId);

      let issueCount = 0;
      agg.itemsByRoom.forEach((list: ItemEntity[]) => {
        for (const it of list) {
          if (it.status === ItemStatus.ISSUE) {
            issueCount++;
          }
        }
      });
      this.issueCount = issueCount;
      this.houseName = agg.house.name;
      this.sceneTitle = InspectionLauncher.sceneTitleOf(agg.inspection.sceneKey);
      this.startedAtText = DateUtil.formatDateTime(agg.inspection.startedAt);
      this.summaryRows = this.buildSummaryRows(agg.inspection, issueCount, meters, handover);
      this.extraNote = agg.inspection.extraNote;
      this.frozen = agg.inspection.status === InspectionStatus.FROZEN;
      if (this.frozen) {
        this.prefillParticipants(agg.inspection.participants);
      }

      // 完整度快照：进入页面现算一次，随冻结写入
      const input = await repo.buildCompletenessInput(this.inspectionId);
      if (input !== null) {
        const r: CompletenessResult = CompletenessEngine.check(input);
        this.requiredPct = Math.round(r.requiredRate * 100);
        this.suggestedPct = Math.round(r.suggestedRate * 100);
      }
      this.loading = false;
    } catch (err) {
      this.loading = false;
      this.loadError = '摘要加载失败，请稍后重试';
    }
  }

  /** FROZEN 只读态：解析 participants JSON 回填姓名（容错）。 */
  private prefillParticipants(json: string): void {
    if (json.length === 0) {
      return;
    }
    try {
      const parsed: object | null = JSON.parse(json);
      if (parsed === null || !Array.isArray(parsed)) {
        return;
      }
      const arr = parsed as Participant[];
      for (const p of arr) {
        const name = typeof p.name === 'string' ? p.name : '';
        const role = typeof p.role === 'string' ? p.role : '';
        if (name.length === 0) {
          continue;
        }
        if (role === 'TENANT') {
          this.tenantName = name;
        } else if (role === 'LANDLORD') {
          this.landlordName = name;
        }
      }
    } catch (err) {
      // participants 非法 JSON 时保持空值
    }
  }

  /** participants 组装为 JSON 字符串 [{role,name}]，仅含非空姓名。 */
  private buildParticipants(): string {
    const parts: Participant[] = [];
    if (this.landlordName.trim().length > 0) {
      const p = new Participant();
      p.role = 'LANDLORD';
      p.name = this.landlordName.trim();
      parts.push(p);
    }
    if (this.tenantName.trim().length > 0) {
      const p = new Participant();
      p.role = 'TENANT';
      p.name = this.tenantName.trim();
      parts.push(p);
    }
    if (parts.length === 0) {
      return '';
    }
    return JSON.stringify(parts);
  }

  /** 冻结是不可逆操作（之后只能创建修订版本）：先二次确认再执行（设计 §5.3 / L8）。 */
  private confirmFreeze(): void {
    if (this.freezing || this.frozen) {
      return;
    }
    this.getUIContext().showAlertDialog({
      title: '冻结本次记录',
      message: '冻结后记录进入只读状态，校验清单随之固化，修改只能创建修订版本。确定冻结吗？',
      autoCancel: true,
      alignment: DialogAlignment.Bottom,
      primaryButton: {
        value: '再看看',
        action: () => {
        }
      },
      secondaryButton: {
        value: '确定冻结',
        fontColor: $r('app.color.brand'),
        action: () => {
          this.doFreeze();
        }
      }
    });
  }

  /** 冻结：完整度快照随事务写入；成功跳报告预览，失败 Toast 错误。 */
  private async doFreeze(): Promise<void> {
    if (this.freezing || this.frozen) {
      return;
    }
    this.freezing = true;
    const uiCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const repo = new InspectionRepo(uiCtx);
    try {
      const input = await repo.buildCompletenessInput(this.inspectionId);
      if (input === null) {
        this.freezing = false;
        this.getUIContext().getPromptAction().showToast({ message: '检查记录不存在，无法冻结' });
        return;
      }
      const r = CompletenessEngine.check(input);
      await repo.freeze(this.inspectionId, this.buildParticipants(), this.extraNote,
        r.requiredRate, r.suggestedRate);
      this.getUIContext().getPromptAction().showToast({ message: '已冻结' });
      // F1：状态变化后刷新绑定的服务卡片（静默容错）
      WidgetService.refreshProgress(uiCtx);
      this.pathStack.replacePathByName(Routes.REPORT_PREVIEW,
        { inspectionId: this.inspectionId } as ReportPreviewParam);
    } catch (err) {
      const e = err as Error;
      this.getUIContext().getPromptAction().showToast({ message: e.message.length > 0 ? e.message : '冻结失败，请重试' });
    } finally {
      this.freezing = false;
    }
  }
}

@Builder
export function confirmSignBuilder() {
  ConfirmSignPage();
}
