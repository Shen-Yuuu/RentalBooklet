import { common } from '@kit.AbilityKit';
import { Routes } from '../common/Routes';
import { ConfirmSignParam, MeterOcrParam, ReviewParam } from '../common/NavParams';
import { CompletenessEngine, CompletenessIssue, CompletenessResult } from '../domain/completeness/CompletenessEngine';
import { HandoverEntity } from '../domain/model/Entities';
import { InspectionStatus, MeterType } from '../domain/model/CoreEnums';
import { InspectionRepo } from '../data/repo/InspectionRepo';
import { HandoverRepo } from '../data/repo/HandoverRepo';
import { TemplateEngine } from '../domain/template/TemplateEngine';

/** R4「说明原因通过」弹窗：原因必填，空则内联提示。 */
@CustomDialog
struct WaiverDialog {
  controller?: CustomDialogController;
  @State reason: string = '';
  @State reasonError: boolean = false;
  onConfirm: (reason: string) => void = () => {};

  build() {
    Column({ space: 14 }) {
      Text('说明原因通过')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)

      Text('请说明该项无需补充照片或备注的原因，原因会随记录保存')
        .fontSize(12)
        .opacity(0.6)

      TextInput({ placeholder: '原因（必填）', text: this.reason })
        .onChange((value: string) => {
          this.reason = value;
          this.reasonError = false;
        })

      if (this.reasonError) {
        Text('请填写原因后再通过')
          .fontSize(11)
          .fontColor($r('app.color.warning'))
          .width('100%')
      }

      Row({ space: 10 }) {
        Button('取消')
          .layoutWeight(1)
          .onClick(() => {
            this.controller?.close();
          })
        Button('确定')
          .layoutWeight(1)
          .backgroundColor($r('app.color.brand'))
          .onClick(() => {
            if (this.reason.trim().length === 0) {
              this.reasonError = true;
              return;
            }
            this.onConfirm(this.reason);
            this.controller?.close();
          })
      }
      .width('100%')
    }
    .padding(20)
    .width('100%')
  }
}

/**
 * 记录完整度页（产品文档 §5.2）。
 * 措辞红线：标题「记录完整度」；副文案「反映本次记录的齐全程度，不代表证据效力」。
 */
@Component
struct ReviewPage {
  @State inspectionId: number = 0;
  @State loading: boolean = true;
  @State loadError: string = '';
  @State frozen: boolean = false;
  @State result: CompletenessResult = new CompletenessResult();
  @State issues: CompletenessIssue[] = [];
  @State requiredPct: number = 100;
  @State suggestedPct: number = 100;
  @State hasRequiredIssues: boolean = false;
  @State roomNames: Map<number, string> = new Map();
  // 交接数据编辑区（D4）：模板含交接时展示，R3 通过条件是 confirmed==true
  @State hasHandover: boolean = false;
  @State keyCount: number = 0;
  @State cardCount: number = 0;
  @State parkingText: string = '';
  @State handoverNote: string = '';
  @State noNeedChecked: boolean = false;
  @State handoverConfirmed: boolean = false;
  @State handoverBusy: boolean = false;
  private pathStack: NavPathStack = new NavPathStack();
  private waiverItemId: number = 0;
  /** 首次 onShown 不重复刷新（onReady 已加载），仅此后每次回到本页时重算完整度。 */
  private everShown: boolean = false;
  private waiverDialogController: CustomDialogController = new CustomDialogController({
    builder: WaiverDialog({
      onConfirm: (reason: string) => {
        this.applyWaiver(reason);
      }
    }),
    autoCancel: true
  });

  build() {
    NavDestination() {
      Column({ space: 12 }) {
        Text('反映本次记录的齐全程度，不代表证据效力')
          .fontSize(12)
          .opacity(0.55)
          .width('100%')

        if (!this.loading && this.loadError.length === 0 && this.hasHandover) {
          Column({ space: 10 }) {
            Row({ space: 8 }) {
              Text('交接数据')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .layoutWeight(1)
              Text(this.handoverConfirmed ? '已确认' : '未登记')
                .fontSize(11)
                .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                .borderRadius(10)
                .backgroundColor(this.handoverConfirmed ? $r('app.color.success') : $r('app.color.warning'))
                .fontColor(Color.White)
            }
            .width('100%')

            if (this.frozen) {
              Text(this.handoverSummaryText())
                .fontSize(13)
                .opacity(0.7)
                .width('100%')
            } else {
              this.keyStepperRow()
              this.cardStepperRow()

              TextInput({ placeholder: '车位/储物凭证（选填）', text: this.parkingText })
                .fontSize(13)
                .onChange((value: string) => {
                  this.parkingText = value;
                })

              TextInput({ placeholder: '备注（选填）', text: this.handoverNote })
                .fontSize(13)
                .onChange((value: string) => {
                  this.handoverNote = value;
                })

              Row({ space: 8 }) {
                Checkbox()
                  .select(this.noNeedChecked)
                  .onChange((value: boolean) => {
                    this.noNeedChecked = value;
                  })
                Text('无需记录')
                  .fontSize(14)
                  .onClick(() => {
                    this.noNeedChecked = !this.noNeedChecked;
                  })
              }
              .width('100%')

              Button('确认交接')
                .width('100%')
                .height(36)
                .fontSize(13)
                .backgroundColor($r('app.color.brand'))
                .enabled(!this.handoverBusy)
                .onClick(() => {
                  this.confirmHandover();
                })
            }
          }
          .width('100%')
          .padding(12)
          .borderRadius(12)
          .backgroundColor($r('app.color.card_bg'))
        }

        if (this.loading) {
          Column({ space: 10 }) {
            LoadingProgress().width(36).height(36)
            Text('正在统计完整度…').fontSize(13).opacity(0.6)
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
          Row({ space: 10 }) {
            Column({ space: 4 }) {
              Text('必须项').fontSize(13).opacity(0.6)
              Text(`${this.requiredPct}%`)
                .fontSize(28)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.danger'))
            }
            .layoutWeight(1)
            .padding({ top: 14, bottom: 14 })
            .borderRadius(12)
            .backgroundColor($r('app.color.card_bg'))
            .alignItems(HorizontalAlign.Center)

            Column({ space: 4 }) {
              Text('建议项').fontSize(13).opacity(0.6)
              Text(`${this.suggestedPct}%`)
                .fontSize(28)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.brand'))
            }
            .layoutWeight(1)
            .padding({ top: 14, bottom: 14 })
            .borderRadius(12)
            .backgroundColor($r('app.color.card_bg'))
            .alignItems(HorizontalAlign.Center)
          }
          .width('100%')

          if (this.issues.length === 0) {
            Column({ space: 8 }) {
              Text('没有遗漏项').fontSize(15)
              Text('本次记录已覆盖全部检查要求').fontSize(12).opacity(0.5)
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else {
            List({ space: 8 }) {
              ForEach(this.issues, (issue: CompletenessIssue) => {
                ListItem() {
                  Row({ space: 10 }) {
                    Column()
                      .width(8)
                      .height(8)
                      .borderRadius(4)
                      .backgroundColor(CompletenessEngine.isRequiredRule(issue.ruleId) ? $r('app.color.danger') : $r('app.color.text_ter'))
                      .margin({ top: 6 })

                    Column({ space: 3 }) {
                      Text(issue.message)
                        .fontSize(14)
                        .maxLines(2)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      if (this.roomLabelOf(issue).length > 0) {
                        Text(this.roomLabelOf(issue))
                          .fontSize(11)
                          .opacity(0.55)
                      }
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)

                    if (issue.ruleId === 'R4' && !this.frozen) {
                      Button('说明原因通过')
                        .fontSize(11)
                        .height(28)
                        .padding({ left: 8, right: 8 })
                        .backgroundColor($r('app.color.warning'))
                        .onClick(() => {
                          this.openWaiver(issue);
                        })
                    }
                  }
                  .width('100%')
                  .padding(12)
                  .borderRadius(12)
                  .backgroundColor($r('app.color.card_bg'))
                  .onClick(() => {
                    this.jumpToRoom(issue);
                  })
                }
              }, (issue: CompletenessIssue) => `${issue.ruleId}-${issue.roomId}-${issue.itemId}-${issue.message.length}`)
            }
            .layoutWeight(1)
            .width('100%')
          }

          if (this.frozen) {
            Button('该记录已冻结')
              .width('100%')
              .enabled(false)
          } else {
            Button('去确认冻结')
              .width('100%')
              .backgroundColor($r('app.color.brand'))
              .onClick(() => {
                this.onFreezeClick();
              })
          }
        }
      }
      .padding(16)
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.bg_page'))
    }
    .title('记录完整度')
    .onShown(() => {
      // 从表读数页确认返回后重算完整度，否则完成率与遗漏清单停留在旧数据
      if (this.everShown && this.inspectionId > 0) {
        this.refresh();
      }
      this.everShown = true;
    })
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
      const p = ctx.pathInfo.param as ReviewParam | null;
      if (p !== null && p !== undefined && p.inspectionId > 0) {
        this.inspectionId = p.inspectionId;
        this.refresh();
      } else {
        this.loading = false;
        this.loadError = '页面参数缺失，请从检查页重新进入';
      }
    })
  }

  /** 钥匙数量步进器（DRAFT 可编辑，数量 ≥ 0）。 */
  @Builder
  keyStepperRow() {
    Row({ space: 10 }) {
      Text('钥匙数量').fontSize(14).layoutWeight(1)
      Button('－')
        .fontSize(14)
        .width(32)
        .height(32)
        .padding(0)
        .borderRadius(16)
        .enabled(this.keyCount > 0)
        .onClick(() => {
          if (this.keyCount > 0) {
            this.keyCount--;
          }
        })
      Text(`${this.keyCount}`)
        .fontSize(15)
        .width(40)
        .textAlign(TextAlign.Center)
      Button('＋')
        .fontSize(14)
        .width(32)
        .height(32)
        .padding(0)
        .borderRadius(16)
        .onClick(() => {
          this.keyCount++;
        })
    }
    .width('100%')
  }

  /** 门禁卡数量步进器。 */
  @Builder
  cardStepperRow() {
    Row({ space: 10 }) {
      Text('门禁卡数量').fontSize(14).layoutWeight(1)
      Button('－')
        .fontSize(14)
        .width(32)
        .height(32)
        .padding(0)
        .borderRadius(16)
        .enabled(this.cardCount > 0)
        .onClick(() => {
          if (this.cardCount > 0) {
            this.cardCount--;
          }
        })
      Text(`${this.cardCount}`)
        .fontSize(15)
        .width(40)
        .textAlign(TextAlign.Center)
      Button('＋')
        .fontSize(14)
        .width(32)
        .height(32)
        .padding(0)
        .borderRadius(16)
        .onClick(() => {
          this.cardCount++;
        })
    }
    .width('100%')
  }

  /** FROZEN 只读摘要。 */
  private handoverSummaryText(): string {
    if (!this.handoverConfirmed) {
      return '交接数据未登记';
    }
    if (this.noNeedChecked) {
      return '无需记录';
    }
    return `钥匙 ${this.keyCount} 把 · 门禁卡 ${this.cardCount} 张`
      + (this.parkingText.length > 0 ? ` · ${this.parkingText}` : '');
  }

  /** 确认交接：勾选"无需记录"走 markNoNeed，否则 upsert；confirmed=1 后 R3 即时重算。 */
  private async confirmHandover(): Promise<void> {
    if (this.frozen || this.handoverBusy) {
      return;
    }
    this.handoverBusy = true;
    try {
      const uiCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const repo = new HandoverRepo(uiCtx);
      if (this.noNeedChecked) {
        await repo.markNoNeed(this.inspectionId);
      } else {
        await repo.upsert(this.inspectionId, this.keyCount, this.cardCount,
          this.parkingText.trim(), this.handoverNote.trim(), true);
      }
      this.getUIContext().getPromptAction().showToast({ message: '交接数据已确认' });
      await this.refresh();
    } catch (err) {
      this.getUIContext().getPromptAction().showToast({ message: '保存失败，请重试' });
    } finally {
      this.handoverBusy = false;
    }
  }

  /** 副文案行：R1/R5/R6 的 message 已含位置描述，其余补充所在房间名。 */
  private roomLabelOf(issue: CompletenessIssue): string {
    if (issue.roomId <= 0) {
      return '';
    }
    if (issue.ruleId === 'R1' || issue.ruleId === 'R5' || issue.ruleId === 'R6') {
      return '';
    }
    const name = this.roomNames.get(issue.roomId);
    return name === undefined || name.length === 0 ? '' : `所在房间：${name}`;
  }

  private async refresh(): Promise<void> {
    this.loading = true;
    this.loadError = '';
    const uiCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const repo = new InspectionRepo(uiCtx);
    try {
      const ins = await repo.getById(this.inspectionId);
      if (ins === null) {
        this.loading = false;
        this.loadError = '未找到该检查记录，可能已被删除';
        return;
      }
      // 数据装配复用 InspectionRepo.buildCompletenessInput（与确认冻结页共用）
      const input = await repo.buildCompletenessInput(this.inspectionId);
      if (input === null) {
        this.loading = false;
        this.loadError = '未找到该检查记录，可能已被删除';
        return;
      }
      const roomNames = new Map<number, string>();
      for (const room of input.rooms) {
        roomNames.set(room.id, room.name);
      }

      const r = CompletenessEngine.check(input);
      this.result = r;
      this.issues = r.issues;
      this.requiredPct = Math.round(r.requiredRate * 100);
      this.suggestedPct = Math.round(r.suggestedRate * 100);
      this.roomNames = roomNames;
      let hasRequired = false;
      for (const issue of r.issues) {
        if (CompletenessEngine.isRequiredRule(issue.ruleId)) {
          hasRequired = true;
          break;
        }
      }
      this.hasRequiredIssues = hasRequired;
      this.frozen = ins.status === InspectionStatus.FROZEN;

      // 交接数据编辑区装配：模板含交接时展示（custom 等场景回退为不展示）
      let hasHandover = false;
      try {
        hasHandover = TemplateEngine.getBuiltin(ins.sceneKey).handover;
      } catch (err) {
        hasHandover = false;
      }
      this.hasHandover = hasHandover;
      if (hasHandover) {
        const handover = await new HandoverRepo(uiCtx).get(this.inspectionId);
        this.keyCount = handover !== null ? Math.max(0, handover.keyCount) : 0;
        this.cardCount = handover !== null ? Math.max(0, handover.accessCardCount) : 0;
        this.parkingText = handover !== null ? handover.parkingOrStorage : '';
        this.handoverNote = handover !== null && !handover.isNoNeed() ? handover.note : '';
        this.noNeedChecked = handover !== null && handover.isNoNeed();
        this.handoverConfirmed = handover !== null && handover.confirmed;
      }
      this.loading = false;
    } catch (err) {
      this.loading = false;
      this.loadError = '完整度数据加载失败，请稍后重试';
    }
  }

  /** 遗漏条目点击：R2 直达表读数确认页，R3 交接区在本页顶部，其余回检查执行页定位。 */
  private jumpToRoom(issue: CompletenessIssue): void {
    if (issue.ruleId === 'R2' && this.isValidMeterType(issue.meterType)) {
      this.pathStack.pushPathByName(Routes.METER_OCR,
        { inspectionId: this.inspectionId, meterType: issue.meterType } as MeterOcrParam);
      return;
    }
    if (issue.ruleId === 'R3') {
      return; // 交接数据编辑区位于本页顶部，无需跳转
    }
    if (issue.roomId <= 0) {
      return;
    }
    // 经 AppStorage 投递定位信号并 pop 回已有检查执行页实例：
    // replace 会把栈顶 review 换成新执行页而栈中仍留旧实例，返回键回到陈旧状态
    if (issue.itemId > 0) {
      AppStorage.setOrCreate('inspection_focus_item', issue.itemId);
    } else {
      AppStorage.setOrCreate('inspection_focus_room', issue.roomId);
    }
    this.pathStack.pop();
  }

  private isValidMeterType(t: string): boolean {
    return t === MeterType.WATER || t === MeterType.ELECTRICITY || t === MeterType.GAS;
  }

  private openWaiver(issue: CompletenessIssue): void {
    this.waiverItemId = issue.itemId;
    this.waiverDialogController.open();
  }

  /** R4 豁免：写库后重新计算完整度。 */
  private async applyWaiver(reason: string): Promise<void> {
    const uiCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try {
      await new InspectionRepo(uiCtx).updateItemWaiver(this.waiverItemId, true, reason);
      AppStorage.setOrCreate('home_dirty', Date.now());
      await this.refresh();
    } catch (err) {
      this.getUIContext().getPromptAction().showToast({ message: '操作失败，请重试' });
    }
  }

  /** 去确认冻结：存在必须级遗漏时二次确认（遗漏将记入完整度快照）。 */
  private onFreezeClick(): void {
    if (this.hasRequiredIssues) {
      this.getUIContext().showAlertDialog({
        title: '存在必须级遗漏',
        message: '仍有未处理的必须级遗漏，遗漏将记入完整度快照。确定继续前往确认冻结吗？',
        autoCancel: true,
        alignment: DialogAlignment.Bottom,
        primaryButton: {
          value: '再看看',
          action: () => {
          }
        },
        secondaryButton: {
          value: '继续冻结',
          fontColor: $r('app.color.warning'),
          action: () => {
            this.goConfirm();
          }
        }
      });
    } else {
      this.goConfirm();
    }
  }

  private goConfirm(): void {
    this.pathStack.pushPathByName(Routes.CONFIRM_SIGN, { inspectionId: this.inspectionId } as ConfirmSignParam);
  }
}

@Builder
export function reviewBuilder() {
  ReviewPage();
}
