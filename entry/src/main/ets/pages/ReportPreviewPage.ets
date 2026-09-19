import { common } from '@kit.AbilityKit';
import { fileIo as fs, hash } from '@kit.CoreFileKit';
import { pdfService, pdfViewManager, PdfView } from '@kit.PDFKit';
import { ReportPreviewParam } from '../common/NavParams';
import { DateUtil } from '../common/DateUtil';
import { HouseRepo } from '../data/repo/HouseRepo';
import { InspectionRepo } from '../data/repo/InspectionRepo';
import { ManifestRepo } from '../data/repo/ManifestRepo';
import { PhotoRepo } from '../data/repo/PhotoRepo';
import { CompareRepo } from '../data/repo/CompareRepo';
import { ManifestBuilder } from '../domain/manifest/ManifestBuilder';
import {
  ManifestSummaryRow, PdfDocModel, ReportCompareRow, ReportComposer, ReportInput,
  ReportIssue, ReportItem, ReportMeter, ReportParticipant, ReportPhotoRef, ReportRoom
} from '../domain/report/ReportComposer';
import { PdfKitRenderer } from '../infra/report/PdfKitRenderer';
import { ShareOutcome, ShareService } from '../infra/share/ShareService';
import { ExportFile, PickerService } from '../infra/media/PickerService';
import {
  HandoverEntity, House, Inspection, ItemEntity, MeterReadingEntity, PhotoEntity, RoomEntity
} from '../domain/model/Entities';
import { CompareResult, InspectionStatus, ItemStatus, MeterType, PhotoKind, PhotoSource, SceneKey } from '../domain/model/CoreEnums';
import { InspectionLauncher } from '../features/inspection/InspectionLauncher';

/** 参与人 JSON 数组元素（与 ConfirmSignPage 落库结构一致）。 */
class Participant {
  role: string = '';
  name: string = '';
}

/**
 * 报告预览页（L9）：
 * - DRAFT 记录提示"请先冻结记录"，不进入报告流程；
 * - FROZEN 记录组装 ReportInput → ReportComposer → PdfKitRenderer 落盘
 *   {filesDir}/insp/{id}/report/{reportNo}.pdf → hash 小写回填 pdf_sha256 → home_dirty；
 * - PdfView 内嵌预览；PdfKit 失败提示"当前设备不支持生成 PDF"并保留摘要文本兜底；
 * - 分享（PDF+摘要+原图，>30 张裁剪）/ 导出（PDF+manifest.json+原图）。
 */
@Component
struct ReportPreviewPage {
  @State inspectionId: number = 0;
  @State loading: boolean = true;
  @State loadError: string = '';
  @State draft: boolean = false;
  @State pdfPath: string = '';
  @State pdfExists: boolean = false;
  @State generating: boolean = false;
  @State genError: string = '';
  @State reportNo: string = '';
  @State houseName: string = '';
  @State sceneTitle: string = '';
  @State frozenAtText: string = '';
  @State participantsText: string = '';
  @State issueCount: number = 0;
  @State photoCount: number = 0;
  @State photoPaths: string[] = [];
  /** 封面完整地址开关（产品文档 §5.3：默认隐藏，用户主动开启才进封面）。 */
  @State includeFullAddress: boolean = false;
  @State hasFullAddress: boolean = false;
  private docModel: PdfDocModel = new PdfDocModel();
  private pdfController: pdfViewManager.PdfController = new pdfViewManager.PdfController();

  build() {
    NavDestination() {
      Column({ space: 12 }) {
        if (this.loading) {
          Column({ space: 10 }) {
            LoadingProgress().width(36).height(36)
            Text('正在加载报告信息…').fontSize(13).opacity(0.6)
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
        } else if (this.draft) {
          Column({ space: 10 }) {
            Text('该记录尚未冻结').fontSize(16).fontWeight(FontWeight.Medium)
            Text('请先冻结记录，冻结后才能生成报告')
              .fontSize(13)
              .opacity(0.55)
              .textAlign(TextAlign.Center)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          if (this.genError.length > 0) {
            Text(this.genError)
              .fontSize(12)
              .fontColor($r('app.color.danger'))
              .width('100%')
          }
          if (this.generating) {
            Row({ space: 8 }) {
              LoadingProgress().width(20).height(20)
              Text('正在生成 PDF…').fontSize(13).opacity(0.6)
            }
            .width('100%')
          }

          if (this.pdfExists && !this.generating) {
            PdfView({
              controller: this.pdfController,
              pageFit: pdfService.PageFit.FIT_WIDTH,
              showScroll: true
            })
              .layoutWeight(1)
              .width('100%')
              .backgroundColor($r('app.color.card_bg'))
          } else {
            Scroll() {
              Column({ space: 10 }) {
                Column({ space: 8 }) {
                  Text(this.reportNo.length > 0 ? this.reportNo : '租房留证报告')
                    .fontSize(16)
                    .fontWeight(FontWeight.Medium)
                    .width('100%')
                  this.summaryRow('房屋', this.houseName)
                  this.summaryRow('场景', this.sceneTitle)
                  this.summaryRow('冻结时间', this.frozenAtText)
                  this.summaryRow('参与人', this.participantsText)
                  this.summaryRow('问题项', `${this.issueCount} 项`)
                  this.summaryRow('照片', `${this.photoCount} 张`)
                  Text('校验值仅用于检测文件在生成后是否发生变化，不代表司法鉴定或官方存证。')
                    .fontSize(10)
                    .opacity(0.4)
                    .width('100%')
                }
                .padding(14)
                .borderRadius(12)
                .backgroundColor($r('app.color.card_bg'))
                .alignItems(HorizontalAlign.Start)
                .width('100%')
              }
              .width('100%')
            }
            .layoutWeight(1)
            .width('100%')
          }

          if (this.hasFullAddress) {
            Row({ space: 8 }) {
              Text('封面显示完整房屋地址')
                .fontSize(13)
                .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.includeFullAddress })
                .onChange(async (isOn: boolean) => {
                  if (isOn === this.includeFullAddress) {
                    return;
                  }
                  this.includeFullAddress = isOn;
                  await this.refresh();
                  // 已有 PDF 为旧地址设置生成：重新渲染保持一致
                  if (this.pdfExists) {
                    await this.generatePdf();
                  }
                })
            }
            .width('100%')
          }

          Row({ space: 8 }) {
            Button(this.pdfExists ? '重新生成' : '生成 PDF')
              .layoutWeight(2)
              .backgroundColor($r('app.color.brand'))
              .enabled(!this.generating)
              .onClick(() => {
                this.generatePdf();
              })
            Button('分享')
              .layoutWeight(1)
              .enabled(!this.generating)
              .onClick(() => {
                this.share();
              })
            Button('导出')
              .layoutWeight(1)
              .enabled(!this.generating)
              .onClick(() => {
                this.doExport();
              })
          }
          .width('100%')
        }
      }
      .padding(16)
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.bg_page'))
    }
    .title('报告预览')
    .onReady((ctx: NavDestinationContext) => {
      const p = ctx.pathInfo.param as ReportPreviewParam | null;
      if (p !== null && p !== undefined && p.inspectionId > 0) {
        this.inspectionId = p.inspectionId;
        this.refresh();
      } else {
        this.loading = false;
        this.loadError = '页面参数缺失，请从记录页重新进入';
      }
    })
  }

  /** 摘要信息行。 */
  @Builder
  summaryRow(label: string, value: string) {
    Row({ space: 10 }) {
      Text(label).fontSize(13).opacity(0.6).width(72)
      Text(value)
        .fontSize(13)
        .layoutWeight(1)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
  }

  private fileExists(path: string): boolean {
    try {
      return fs.accessSync(path);
    } catch (err) {
      return false;
    }
  }

  /** 系统字体路径（HarmonyOS Sans）：Font 须经 UIContext 获取，失败传空串走渲染器默认字体。 */
  private resolveFontPath(): string {
    try {
      const info = this.getUIContext().getFont().getFontByName('HarmonyOS Sans');
      if (info !== undefined && info !== null && info.path.length > 0) {
        return info.path;
      }
    } catch (ignored) {
    }
    return '';
  }

  /** 参与人 JSON 解析（容错）：结构化参与人列表（确认信息页数据源）。 */
  private parseParticipantList(json: string): ReportParticipant[] {
    const list: ReportParticipant[] = [];
    if (json.length === 0) {
      return list;
    }
    try {
      const parsed: object | null = JSON.parse(json);
      if (parsed === null || !Array.isArray(parsed)) {
        return list;
      }
      const arr = parsed as Participant[];
      for (const p of arr) {
        const name = typeof p.name === 'string' ? p.name : '';
        const role = typeof p.role === 'string' ? p.role : '';
        if (name.length === 0) {
          continue;
        }
        const rp = new ReportParticipant();
        rp.roleText = role === 'TENANT' ? '租客' : '房东';
        rp.name = name;
        list.push(rp);
      }
    } catch (err) {
      // 非法 JSON：按未填写处理
    }
    return list;
  }

  /** 参与人单行文案：'房东：张三　租客：李四'。 */
  private participantsTextOf(list: ReportParticipant[]): string {
    if (list.length === 0) {
      return '未填写';
    }
    const parts: string[] = [];
    for (const p of list) {
      parts.push(`${p.roleText}：${p.name}`);
    }
    return parts.join('　');
  }

  /** 表读数值格式化：无表具 / 已确认读数 / 未登记。确认门闩：未确认记录一律"未登记"。 */
  private meterValue(meters: MeterReadingEntity[], type: string): string {
    for (const m of meters) {
      // 确认门闩红线：confirmed=0 的读数绝不进 PDF
      if (m.meterType !== type || !m.confirmed) {
        continue;
      }
      if (m.naFlag) {
        return '无表具';
      }
      return m.valueText.length > 0 ? m.valueText : '已确认';
    }
    return '未登记';
  }

  /** ReportInput 装配（渲染器无关，纯数据拼装）。 */
  private buildReportInput(ins: Inspection, house: House | null,
    rooms: RoomEntity[], itemsByRoom: Map<number, ItemEntity[]>,
    meters: MeterReadingEntity[], handover: HandoverEntity | null,
    photos: PhotoEntity[], manifestJson: string | null): ReportInput {
    const input = new ReportInput();
    input.houseName = house !== null ? house.name : '';
    input.fullAddress = house !== null ? house.fullAddress : '';
    input.includeFullAddress = this.includeFullAddress;
    input.sceneTitle = InspectionLauncher.sceneTitleOf(ins.sceneKey);
    input.reportNo = ins.reportNo;
    input.frozenAtText = ins.frozenAt > 0 ? DateUtil.formatDateTime(ins.frozenAt) : '';
    input.participants = this.parseParticipantList(ins.participants);
    input.participantsText = this.participantsTextOf(input.participants);
    // v1 单一确认时间：参与人确认时间即记录冻结时间
    input.confirmedAtText = input.frozenAtText;
    input.extraNote = ins.extraNote;
    input.requiredRateText = `${Math.round(ins.completeRequired * 100)}%`;
    input.suggestedRateText = `${Math.round(ins.completeSuggested * 100)}%`;

    // 照片统一编号：按 listByInspection 顺序 1..N，'图 N' 同时用于
    // 逐房间页/问题汇总引用与校验页"编号 ↔ 文件名"映射（flows/03 L269）
    const photoRefs: ReportPhotoRef[] = [];
    const noByFileName = new Map<string, string>();
    for (let i = 0; i < photos.length; i++) {
      const p = photos[i];
      const ref = new ReportPhotoRef();
      ref.thumbPath = p.thumbPath.length > 0 ? p.thumbPath : p.path;
      ref.noText = `图 ${i + 1}`;
      ref.imported = p.source === PhotoSource.IMPORTED;
      photoRefs.push(ref);
      const fileName = p.path.includes('/')
        ? p.path.substring(p.path.lastIndexOf('/') + 1) : p.path;
      noByFileName.set(fileName, ref.noText);
    }

    for (const room of rooms) {
      const rr = new ReportRoom();
      rr.name = room.name;
      const items = itemsByRoom.get(room.id);
      if (items !== undefined) {
        for (const it of items) {
          const ri = new ReportItem();
          ri.name = it.name;
          ri.status = it.status;
          ri.noteFinal = it.noteFinal;
          const itemPhotoNos: string[] = [];
          for (let i = 0; i < photos.length; i++) {
            const p = photos[i];
            if (p.itemId === it.id && p.kind !== PhotoKind.PANORAMA) {
              ri.photoRefs.push(photoRefs[i]);
              itemPhotoNos.push(photoRefs[i].noText);
            }
          }
          rr.items.push(ri);
          if (it.status === ItemStatus.ISSUE) {
            const issue = new ReportIssue();
            issue.room = room.name;
            issue.item = it.name;
            issue.note = it.noteFinal;
            issue.photoNos = itemPhotoNos.join('、');
            input.issueList.push(issue);
          }
        }
      }
      for (let i = 0; i < photos.length; i++) {
        const p = photos[i];
        if (p.roomId !== room.id) {
          continue;
        }
        if (p.kind === PhotoKind.PANORAMA) {
          rr.panoramaRefs.push(photoRefs[i]);
        } else if (p.itemId === 0) {
          // 房间级细节照（未挂接具体检查项）
          rr.extraPhotos.push(photoRefs[i]);
        }
      }
      input.rooms.push(rr);
    }

    const water = new ReportMeter();
    water.label = '水表';
    water.valueText = this.meterValue(meters, MeterType.WATER);
    input.meters.push(water);
    const electric = new ReportMeter();
    electric.label = '电表';
    electric.valueText = this.meterValue(meters, MeterType.ELECTRICITY);
    input.meters.push(electric);
    const gas = new ReportMeter();
    gas.label = '燃气表';
    gas.valueText = this.meterValue(meters, MeterType.GAS);
    input.meters.push(gas);

    if (handover !== null && handover.confirmed) {
      // 确认门闩：仅 confirmed 交接进 PDF；"无需记录"语义原样展示
      input.handoverText = handover.isNoNeed() ? '无需记录'
        : `钥匙 ${handover.keyCount} 把 · 门禁卡 ${handover.accessCardCount} 张`;
    } else {
      input.handoverText = '未登记';
    }

    if (manifestJson !== null && manifestJson.length > 0) {
      try {
        const mc = ManifestBuilder.parse(manifestJson);
        for (const f of mc.files) {
          const row = new ManifestSummaryRow();
          row.fileName = f.relPath.includes('/')
            ? f.relPath.substring(f.relPath.lastIndexOf('/') + 1) : f.relPath;
          row.shaShort = f.sha256.length >= 12 ? f.sha256.substring(0, 12) : f.sha256;
          const no = noByFileName.get(row.fileName);
          row.noText = no !== undefined ? no : '';
          input.manifestSummary.push(row);
        }
      } catch (err) {
        // 非法清单不阻塞报告生成，校验页展示"未找到校验清单"兜底
      }
    }
    return input;
  }

  /** 对比三态 → 报告文案（与 ReportComposer.CHANGED_TEXT 约定一致）。 */
  private compareResultText(r: string): string {
    if (r === CompareResult.UNCHANGED) {
      return '无变化';
    }
    if (r === CompareResult.CHANGED) {
      return '有变化';
    }
    return '待确认';
  }

  /** E3：退租 + 有基线 + compare_result 有数据时，装配对比结论行（房间/项目/结果文案）。 */
  private appendCompareRows(input: ReportInput, rooms: RoomEntity[],
    itemsByRoom: Map<number, ItemEntity[]>, results: Map<number, string>): void {
    for (const room of rooms) {
      const items = itemsByRoom.get(room.id);
      if (items === undefined) {
        continue;
      }
      for (const it of items) {
        const marked = results.get(it.id);
        if (marked === undefined) {
          continue;
        }
        const row = new ReportCompareRow();
        row.room = room.name;
        row.item = it.name;
        row.result = this.compareResultText(marked);
        input.compareRows.push(row);
      }
    }
  }

  private buildSummaryText(): string {
    return `【租房留证报告】${this.reportNo}\n`
      + `${this.houseName} · ${this.sceneTitle}\n`
      + `冻结时间：${this.frozenAtText}\n`
      + `参与人：${this.participantsText}\n`
      + `问题项：${this.issueCount} 项 · 照片：${this.photoCount} 张\n`
      + '校验值仅用于检测文件在生成后是否发生变化，不代表司法鉴定或官方存证。';
  }

  private async refresh(): Promise<void> {
    this.loading = true;
    this.loadError = '';
    this.genError = '';
    const uiCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try {
      const repo = new InspectionRepo(uiCtx);
      const ins = await repo.getById(this.inspectionId);
      if (ins === null) {
        this.loading = false;
        this.loadError = '未找到该检查记录，可能已被删除';
        return;
      }
      if (ins.status === InspectionStatus.DRAFT) {
        this.loading = false;
        this.draft = true;
        return;
      }
      this.draft = false;
      const agg = await repo.getAggregate(this.inspectionId);
      if (agg === null) {
        this.loading = false;
        this.loadError = '未找到该检查记录，可能已被删除';
        return;
      }
      const house = await new HouseRepo(uiCtx).getById(ins.houseId);
      const meters = await repo.listMeters(this.inspectionId);
      const handover = await repo.getHandover(this.inspectionId);
      const photos = await new PhotoRepo(uiCtx).listByInspection(this.inspectionId);
      const manifestJson = await new ManifestRepo(uiCtx).latest(this.inspectionId);

      const input = this.buildReportInput(ins, house, agg.rooms, agg.itemsByRoom,
        meters, handover, photos, manifestJson);

      // E3：退租报告附加前后对比结论（有基线且已有确认数据时）
      if (ins.sceneKey === SceneKey.MOVE_OUT && ins.baselineInspectionId > 0) {
        const compareResults = await new CompareRepo(uiCtx).listResults(this.inspectionId);
        if (compareResults.size > 0) {
          this.appendCompareRows(input, agg.rooms, agg.itemsByRoom, compareResults);
        }
      }

      this.docModel = ReportComposer.compose(input);

      this.reportNo = ins.reportNo;
      this.houseName = input.houseName;
      this.hasFullAddress = input.fullAddress.length > 0;
      this.sceneTitle = input.sceneTitle;
      this.frozenAtText = input.frozenAtText;
      this.participantsText = input.participantsText;
      this.issueCount = input.issueList.length;
      this.photoCount = photos.length;
      this.photoPaths = [];
      for (const p of photos) {
        this.photoPaths.push(p.path);
      }

      this.pdfPath = `${ManifestRepo.inspectionDir(uiCtx, this.inspectionId)}/report/${ins.reportNo}.pdf`;
      this.pdfExists = this.fileExists(this.pdfPath);
      this.loading = false;
      if (this.pdfExists) {
        await this.loadPdfView();
      }
    } catch (err) {
      this.loading = false;
      this.loadError = '报告数据加载失败，请稍后重试';
    }
  }

  private async loadPdfView(): Promise<void> {
    try {
      const result = await this.pdfController.loadDocument(this.pdfPath);
      if (result !== pdfService.ParseResult.PARSE_SUCCESS) {
        this.genError = 'PDF 预览加载失败，可尝试重新生成';
      }
    } catch (err) {
      this.genError = 'PDF 预览加载失败，可尝试重新生成';
    }
  }

  /** 生成/重新生成：渲染 → pdf sha256（小写）回填 → home_dirty → PdfView 加载。 */
  private async generatePdf(): Promise<void> {
    if (this.generating || this.draft) {
      return;
    }
    this.generating = true;
    this.genError = '';
    const uiCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try {
      await PdfKitRenderer.render(this.docModel, this.pdfPath, this.resolveFontPath());
      const sha = (await hash.hash(this.pdfPath, 'sha256')).toLowerCase();
      await new InspectionRepo(uiCtx).updatePdfSha256(this.inspectionId, sha);
      AppStorage.setOrCreate('home_dirty', Date.now());
      this.pdfExists = true;
      this.getUIContext().getPromptAction().showToast({ message: 'PDF 已生成' });
      await this.loadPdfView();
    } catch (err) {
      const e = err as Error;
      this.genError = e.message.length > 0 ? e.message : 'PDF 生成失败，请重试';
    } finally {
      this.generating = false;
    }
  }

  private async share(): Promise<void> {
    if (!this.pdfExists) {
      this.getUIContext().getPromptAction().showToast({ message: '请先生成 PDF 报告' });
      return;
    }
    const uiCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try {
      const manifestPath = `${ManifestRepo.inspectionDir(uiCtx, this.inspectionId)}/manifest.json`;
      const outcome: ShareOutcome = await ShareService.shareReport(uiCtx, this.pdfPath,
        this.buildSummaryText(), this.photoPaths, manifestPath);
      if (outcome.photoShared < outcome.photoTotal) {
        this.getUIContext().getPromptAction()
          .showToast({ message: `照片较多，本次分享报告与前 ${outcome.photoShared} 张原图，其余可在导出中逐文件保存` });
      }
    } catch (err) {
      const e = err as Error;
      this.getUIContext().getPromptAction()
        .showToast({ message: e.message.length > 0 ? e.message : '分享失败，请重试' });
    }
  }

  /** 导出：PDF + manifest.json + 原图（DocumentViewPicker 免权限逐文件保存）。 */
  private async doExport(): Promise<void> {
    if (!this.pdfExists) {
      this.getUIContext().getPromptAction().showToast({ message: '请先生成 PDF 报告' });
      return;
    }
    const uiCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const files: ExportFile[] = [];
    files.push(new ExportFile(this.pdfPath, `${this.reportNo}.pdf`));
    const manifestPath = `${ManifestRepo.inspectionDir(uiCtx, this.inspectionId)}/manifest.json`;
    if (this.fileExists(manifestPath)) {
      files.push(new ExportFile(manifestPath, 'manifest.json'));
    }
    for (const p of this.photoPaths) {
      const idx = p.lastIndexOf('/');
      files.push(new ExportFile(p, idx >= 0 ? p.substring(idx + 1) : p));
    }
    if (files.length > PickerService.MAX_SAVE_FILES) {
      files.length = 2;
      this.getUIContext().getPromptAction()
        .showToast({ message: '文件较多，本次仅导出报告与校验清单' });
    }
    try {
      const count = await PickerService.exportFiles(uiCtx, files);
      if (count > 0) {
        this.getUIContext().getPromptAction().showToast({ message: `已导出 ${count} 个文件` });
      }
    } catch (err) {
      const e = err as Error;
      this.getUIContext().getPromptAction()
        .showToast({ message: e.message.length > 0 ? e.message : '导出失败，请重试' });
    }
  }
}

@Builder
export function reportPreviewBuilder() {
  ReportPreviewPage();
}
