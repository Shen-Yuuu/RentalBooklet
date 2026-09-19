/**
 * PDF 文档模型与报告组装器（技术设计文档 §7.4，产品设计文档 §5.5）。
 * 纯 TS 渲染器无关模型：只产出坐标/文本/图片引用，不触碰任何 Kit；
 * 由 infra/report/PdfKitRenderer 负责真正落盘。
 * 页面结构：封面 / 交接数据 / 逐房间（自动分页）/ 问题汇总 / 前后对比结论（有数据时）
 * / 确认信息 / 文件校验信息。
 * 措辞红线：免责文案复用 ManifestBuilder.DISCLAIMER 固定文案，不得改动；
 * 相册导入照片强制标注"从相册导入"（产品文档 §3.4），绝不伪装成即时拍摄。
 */

import { MeasureFn, TextLineBreaker } from './TextLineBreaker';
import { ManifestBuilder } from '../manifest/ManifestBuilder';
import { ItemStatus } from '../model/CoreEnums';

/** 单行文本（pdfService.addTextObject 只可按行添加）。 */
export class PdfTextLine {
  text: string = '';
  x: number = 0;
  y: number = 0;
  fontSize: number = 10;
  /** BGR 数字色值（pdfService TextStyle.textColor 口径），0x000000=黑。 */
  color: number = 0;
  bold: boolean = false;
}

/** 图片引用：path 为沙箱绝对路径（JPEG），compose 只放引用不读文件。 */
export class PdfImage {
  path: string = '';
  x: number = 0;
  y: number = 0;
  w: number = 0;
  h: number = 0;
}

/** 一页内容：文本行 + 图片。 */
export class PdfPageModel {
  texts: PdfTextLine[] = [];
  images: PdfImage[] = [];
}

/** 文档模型：A4 595x842pt 页序列。 */
export class PdfDocModel {
  pages: PdfPageModel[] = [];
}

/** 照片引用：缩略图路径 + 原图编号 + 来源标注（从相册导入必须在 PDF 中体现）。 */
export class ReportPhotoRef {
  thumbPath: string = '';
  /** 原图编号文案，如 '图 3'；与校验页"编号 ↔ 文件名"映射一致。 */
  noText: string = '';
  /** true = 从相册导入（PDF 中强制标注，产品文档 §3.4）。 */
  imported: boolean = false;
}

/** 检查项行。 */
export class ReportItem {
  name: string = '';
  status: string = ItemStatus.PENDING;
  noteFinal: string = '';
  /** 该检查项的细节照引用（缩略 + 原图编号）。 */
  photoRefs: ReportPhotoRef[] = [];
}

/** 房间：全景照引用（嵌入第一张）+ 检查项 + 未挂接检查项的房间级近照。 */
export class ReportRoom {
  name: string = '';
  items: ReportItem[] = [];
  panoramaRefs: ReportPhotoRef[] = [];
  /** 房间级细节照（未挂到具体检查项）。 */
  extraPhotos: ReportPhotoRef[] = [];
}

/** 问题汇总行。 */
export class ReportIssue {
  room: string = '';
  item: string = '';
  note: string = '';
  /** 关联照片编号（如 '3、5'），空串表示无照片。 */
  photoNos: string = '';
}

/** 表读数行（valueText 已由调用方格式化：读数值 / 未登记 / 无表具）。 */
export class ReportMeter {
  label: string = '';
  valueText: string = '';
}

/** 校验清单摘要行（原图编号 + 文件名 + sha256 前 12 位）。 */
export class ManifestSummaryRow {
  fileName: string = '';
  shaShort: string = '';
  /** 原图编号（如 '图 3'），与逐房间页/问题汇总引用一致；未匹配到照片时为空。 */
  noText: string = '';
}

/** 前后对比结论行（E3）：result 为已格式化文案（无变化/有变化/待确认）。 */
export class ReportCompareRow {
  room: string = '';
  item: string = '';
  result: string = '';
}

/** 确认信息页参与人行（v1 文本确认，签名画板随 v1.1）。 */
export class ReportParticipant {
  roleText: string = '';
  name: string = '';
}

/** 组装输入：全部为已格式化文本，compose 不做 IO。 */
export class ReportInput {
  houseName: string = '';
  /** 完整地址（默认隐藏，仅当 includeFullAddress 时进入封面，产品文档 §5.3）。 */
  fullAddress: string = '';
  includeFullAddress: boolean = false;
  sceneTitle: string = '';
  reportNo: string = '';
  frozenAtText: string = '';
  participantsText: string = '';
  /** 确认信息页结构化参与人（与 participantsText 同源）。 */
  participants: ReportParticipant[] = [];
  /** 参与人确认时间（v1 为记录冻结时间）。 */
  confirmedAtText: string = '';
  extraNote: string = '';
  requiredRateText: string = '';
  suggestedRateText: string = '';
  rooms: ReportRoom[] = [];
  issueList: ReportIssue[] = [];
  compareRows: ReportCompareRow[] = [];
  meters: ReportMeter[] = [];
  handoverText: string = '';
  manifestSummary: ManifestSummaryRow[] = [];
}

/** 排版游标：跨方法续页时保持 page/y 同步。 */
class LayoutCursor {
  page: PdfPageModel = new PdfPageModel();
  y: number = 0;
}

export class ReportComposer {
  /** A4 纵向 595x842pt（一英寸 72pt）。 */
  static readonly PAGE_W: number = 595;
  static readonly PAGE_H: number = 842;
  static readonly MARGIN_X: number = 40;
  static readonly TOP_Y: number = 56;
  static readonly BOTTOM_Y: number = 812;
  static readonly LINE_H: number = 16;
  static readonly CONTENT_W: number = 595 - 40 * 2;
  static readonly GRAY: number = 0x666666;
  /** 细节照缩略块：每行 5 张 92x69，下方 8pt 编号/来源标注。 */
  static readonly THUMB_W: number = 92;
  static readonly THUMB_H: number = 69;
  static readonly THUMB_STEP_X: number = 96;
  static readonly THUMB_PER_ROW: number = 5;
  static readonly THUMB_BLOCK_H: number = 83;
  /** 红色（pdfService textColor 为 BGR 口径，0x0000FF=红）："有变化"行标记色。 */
  static readonly RED: number = 0x0000FF;
  /** "有变化"结果文案（与调用方 resultText 约定一致，用于红色标记判断）。 */
  static readonly CHANGED_TEXT: string = '有变化';

  /**
   * 组装入口：封面 → 交接数据 → 逐房间 → 问题汇总 → 前后对比结论（有数据时）
   * → 确认信息 → 校验信息。
   * measure 为注入的文本测宽函数（渲染器可传 pdfService measureText）；缺省用近似测宽。
   */
  static compose(input: ReportInput, measure?: MeasureFn): PdfDocModel {
    const m: MeasureFn = measure !== undefined ? measure : ReportComposer.approxMeasure;
    const doc = new PdfDocModel();
    ReportComposer.buildCover(doc, input);
    ReportComposer.buildHandoverPage(doc, input, m);
    ReportComposer.buildRoomPages(doc, input);
    ReportComposer.buildIssuePage(doc, input);
    ReportComposer.buildComparePage(doc, input);
    ReportComposer.buildConfirmPage(doc, input);
    ReportComposer.buildVerifyPage(doc, input, m);
    return doc;
  }

  /** 封面：报告编号/房屋/场景/冻结时间/参与人/完整度快照（副文案：不代表证据效力）；可选完整地址。 */
  private static buildCover(doc: PdfDocModel, input: ReportInput): void {
    const page = ReportComposer.newPage(doc);
    ReportComposer.addLine(page, '租房留证报告', ReportComposer.MARGIN_X, 120, 22, 0, true);
    ReportComposer.addLine(page, `报告编号：${input.reportNo}`, ReportComposer.MARGIN_X, 170, 12, 0, false);
    ReportComposer.addLine(page, `房屋：${input.houseName}`, ReportComposer.MARGIN_X, 196, 12, 0, false);
    ReportComposer.addLine(page, `场景：${input.sceneTitle}`, ReportComposer.MARGIN_X, 218, 12, 0, false);
    ReportComposer.addLine(page, `冻结时间：${input.frozenAtText}`, ReportComposer.MARGIN_X, 240, 12, 0, false);
    ReportComposer.addLine(page, `参与人：${input.participantsText}`, ReportComposer.MARGIN_X, 262, 12, 0, false);
    let y = 284;
    if (input.includeFullAddress && input.fullAddress.length > 0) {
      ReportComposer.addLine(page, `房屋地址：${input.fullAddress}`, ReportComposer.MARGIN_X, y, 12, 0, false);
      y += 22;
    }
    ReportComposer.addLine(page,
      `记录完整度：必须项 ${input.requiredRateText} · 建议项 ${input.suggestedRateText}`,
      ReportComposer.MARGIN_X, y, 12, 0, false);
    y += 18;
    ReportComposer.addLine(page, '记录完整度仅反映登记完成情况，不代表证据效力',
      ReportComposer.MARGIN_X, y, 8, ReportComposer.GRAY, false);
  }

  /** 交接数据页：三表读数 + 钥匙门禁 + 补充说明（长文本断行）。 */
  private static buildHandoverPage(doc: PdfDocModel, input: ReportInput, measure: MeasureFn): void {
    const page = ReportComposer.newPage(doc);
    ReportComposer.addLine(page, '交接数据', ReportComposer.MARGIN_X, ReportComposer.TOP_Y, 14, 0, true);
    let y = ReportComposer.TOP_Y + 28;
    for (const m of input.meters) {
      ReportComposer.addLine(page, `${m.label}：${m.valueText}`, ReportComposer.MARGIN_X, y, 11, 0, false);
      y += ReportComposer.LINE_H;
    }
    ReportComposer.addLine(page, `钥匙门禁：${input.handoverText}`, ReportComposer.MARGIN_X, y, 11, 0, false);
    y += ReportComposer.LINE_H + 10;

    ReportComposer.addLine(page, '补充说明', ReportComposer.MARGIN_X, y, 12, 0, true);
    y += 20;
    const note = input.extraNote.length > 0 ? input.extraNote : '无';
    const lines = TextLineBreaker.breakLines(note, ReportComposer.CONTENT_W, 10, measure);
    const maxLines = 10;
    for (let i = 0; i < lines.length && i < maxLines; i++) {
      let text = lines[i];
      if (i === maxLines - 1 && i < lines.length - 1) {
        text = `${text}…`;
      }
      ReportComposer.addLine(page, text, ReportComposer.MARGIN_X, y, 10, 0, false);
      y += ReportComposer.LINE_H;
    }
  }

  /** 逐房间页：每页可放多房间，块超高自动分页；检查项细节照缩略 + 原图编号随行展示。 */
  private static buildRoomPages(doc: PdfDocModel, input: ReportInput): void {
    let page = ReportComposer.newPage(doc);
    ReportComposer.addLine(page, '检查记录（按房间）', ReportComposer.MARGIN_X, ReportComposer.TOP_Y, 14, 0, true);
    let y = ReportComposer.TOP_Y + 28;

    for (const room of input.rooms) {
      const blockH = ReportComposer.roomBlockHeight(room);
      if (y + blockH > ReportComposer.BOTTOM_Y && y > ReportComposer.TOP_Y + 28) {
        page = ReportComposer.newPage(doc);
        y = ReportComposer.TOP_Y;
      }

      ReportComposer.addLine(page, room.name, ReportComposer.MARGIN_X, y, 12, 0, true);
      y += 20;
      if (room.panoramaRefs.length > 0) {
        const ref = room.panoramaRefs[0];
        const img = new PdfImage();
        img.path = ref.thumbPath;
        img.x = ReportComposer.MARGIN_X;
        img.y = y;
        img.w = 220;
        img.h = 165;
        page.images.push(img);
        y += 165;
        ReportComposer.addLine(page, ReportComposer.panoramaCaption(ref),
          ReportComposer.MARGIN_X, y + 1, 8, ReportComposer.GRAY, false);
        y += 12;
      }
      for (const item of room.items) {
        if (y + ReportComposer.LINE_H > ReportComposer.BOTTOM_Y) {
          page = ReportComposer.newPage(doc);
          y = ReportComposer.TOP_Y;
        }
        const note = item.noteFinal.length > 0
          ? `——${ReportComposer.truncate(item.noteFinal, 46)}` : '';
        ReportComposer.addLine(page,
          `${item.name}：${ReportComposer.statusText(item.status)}${note}`,
          ReportComposer.MARGIN_X, y, 10, 0, false);
        y += ReportComposer.LINE_H;
        const cursor = new LayoutCursor();
        cursor.page = page;
        cursor.y = y;
        ReportComposer.renderPhotoRefs(doc, cursor, item.photoRefs);
        page = cursor.page;
        y = cursor.y;
      }
      const cursor = new LayoutCursor();
      cursor.page = page;
      cursor.y = y;
      ReportComposer.renderPhotoRefs(doc, cursor, room.extraPhotos);
      page = cursor.page;
      y = cursor.y;
      y += 14;
    }
  }

  /** 问题汇总页：空清单仍保留标题 + 提示行；长清单真实续页（每页仅一个标题）。 */
  private static buildIssuePage(doc: PdfDocModel, input: ReportInput): void {
    let page = ReportComposer.newPage(doc);
    ReportComposer.addLine(page, '问题汇总', ReportComposer.MARGIN_X, ReportComposer.TOP_Y, 14, 0, true);
    let y = ReportComposer.TOP_Y + 28;
    if (input.issueList.length === 0) {
      ReportComposer.addLine(page, '本次检查未登记问题项', ReportComposer.MARGIN_X, y, 11,
        ReportComposer.GRAY, false);
      return;
    }
    for (const issue of input.issueList) {
      if (y + ReportComposer.LINE_H > ReportComposer.BOTTOM_Y) {
        page = ReportComposer.newPage(doc);
        ReportComposer.addLine(page, '问题汇总（续）', ReportComposer.MARGIN_X,
          ReportComposer.TOP_Y, 12, 0, true);
        y = ReportComposer.TOP_Y + 24;
      }
      const note = issue.note.length > 0 ? `——${ReportComposer.truncate(issue.note, 40)}` : '';
      const photos = issue.photoNos.length > 0 ? `　照片：${issue.photoNos}` : '';
      ReportComposer.addLine(page, `${issue.room} · ${issue.item}${note}${photos}`,
        ReportComposer.MARGIN_X, y, 10, 0, false);
      y += ReportComposer.LINE_H;
    }
  }

  /**
   * 前后对比结论页（E3，仅退租 PDF）：无对比数据不生成；
   * 措辞红线：仅客观呈现对照结果（"有变化"红色标记），不出现归因/责任文案。
   */
  private static buildComparePage(doc: PdfDocModel, input: ReportInput): void {
    if (input.compareRows.length === 0) {
      return;
    }
    let page = ReportComposer.newPage(doc);
    ReportComposer.addLine(page, '前后对比结论', ReportComposer.MARGIN_X, ReportComposer.TOP_Y, 14, 0, true);
    let y = ReportComposer.TOP_Y + 28;
    ReportComposer.addLine(page, '以下为入住与退租检查的逐项对照记录，仅呈现登记内容，不代表责任归属。',
      ReportComposer.MARGIN_X, y, 9, ReportComposer.GRAY, false);
    y += ReportComposer.LINE_H + 6;
    for (const row of input.compareRows) {
      if (y + ReportComposer.LINE_H > ReportComposer.BOTTOM_Y) {
        page = ReportComposer.newPage(doc);
        ReportComposer.addLine(page, '前后对比结论（续）', ReportComposer.MARGIN_X,
          ReportComposer.TOP_Y, 12, 0, true);
        y = ReportComposer.TOP_Y + 24;
      }
      const changed = row.result === ReportComposer.CHANGED_TEXT;
      ReportComposer.addLine(page, `${row.room} · ${row.item}：${row.result}`,
        ReportComposer.MARGIN_X, y, 10, changed ? ReportComposer.RED : 0, changed);
      y += ReportComposer.LINE_H;
    }
  }

  /** 确认信息页（产品文档 §5.5 第 5 页）：参与人姓名与确认时间（v1 文本确认）。 */
  private static buildConfirmPage(doc: PdfDocModel, input: ReportInput): void {
    const page = ReportComposer.newPage(doc);
    ReportComposer.addLine(page, '确认信息', ReportComposer.MARGIN_X, ReportComposer.TOP_Y, 14, 0, true);
    let y = ReportComposer.TOP_Y + 28;
    ReportComposer.addLine(page, '参与人姓名与确认时间（文本确认，签名画板随 v1.1 提供）',
      ReportComposer.MARGIN_X, y, 9, ReportComposer.GRAY, false);
    y += ReportComposer.LINE_H + 6;
    if (input.participants.length === 0) {
      ReportComposer.addLine(page, '未填写参与人', ReportComposer.MARGIN_X, y, 11,
        ReportComposer.GRAY, false);
      return;
    }
    const timeText = input.confirmedAtText.length > 0 ? input.confirmedAtText : '未记录';
    for (const p of input.participants) {
      ReportComposer.addLine(page, `${p.roleText}：${p.name}　确认时间：${timeText}`,
        ReportComposer.MARGIN_X, y, 11, 0, false);
      y += ReportComposer.LINE_H;
    }
  }

  /**
   * 校验信息页：manifest 摘要（原图编号 + 文件名 + sha256 前 12 位，构成"编号 ↔ 文件名"映射）
   * + 固定免责文案。
   */
  private static buildVerifyPage(doc: PdfDocModel, input: ReportInput, measure: MeasureFn): void {
    let page = ReportComposer.newPage(doc);
    ReportComposer.addLine(page, '文件校验信息', ReportComposer.MARGIN_X, ReportComposer.TOP_Y, 14, 0, true);
    let y = ReportComposer.TOP_Y + 28;
    ReportComposer.addLine(page, '以下校验值对应检查过程中登记的原始文件（SHA-256 前 12 位）：',
      ReportComposer.MARGIN_X, y, 9, ReportComposer.GRAY, false);
    y += ReportComposer.LINE_H;
    if (input.manifestSummary.length === 0) {
      ReportComposer.addLine(page, '未找到校验清单', ReportComposer.MARGIN_X, y, 10,
        ReportComposer.GRAY, false);
      y += ReportComposer.LINE_H;
    }
    for (const row of input.manifestSummary) {
      if (y + 14 > ReportComposer.BOTTOM_Y) {
        page = ReportComposer.newPage(doc);
        y = ReportComposer.TOP_Y;
      }
      const prefix = row.noText.length > 0 ? `${row.noText} · ` : '';
      ReportComposer.addLine(page, `${prefix}${row.fileName}　${row.shaShort}`,
        ReportComposer.MARGIN_X, y, 9, 0, false);
      y += 14;
    }
    y += 8;
    const disclaimerLines = TextLineBreaker.breakLines(ManifestBuilder.DISCLAIMER,
      ReportComposer.CONTENT_W, 9, measure);
    for (const line of disclaimerLines) {
      if (y + 13 > ReportComposer.BOTTOM_Y) {
        page = ReportComposer.newPage(doc);
        y = ReportComposer.TOP_Y;
      }
      ReportComposer.addLine(page, line, ReportComposer.MARGIN_X, y, 9, ReportComposer.GRAY, false);
      y += 13;
    }
  }

  /** 细节照缩略块高度估算（房间块分页判断用）。 */
  private static photoBlockH(count: number): number {
    if (count <= 0) {
      return 0;
    }
    return Math.ceil(count / ReportComposer.THUMB_PER_ROW) * ReportComposer.THUMB_BLOCK_H;
  }

  private static roomBlockHeight(room: ReportRoom): number {
    let h = 20 + 14;
    if (room.panoramaRefs.length > 0) {
      h += 165 + 12;
    }
    for (const item of room.items) {
      h += ReportComposer.LINE_H + ReportComposer.photoBlockH(item.photoRefs.length);
    }
    h += ReportComposer.photoBlockH(room.extraPhotos.length);
    return h;
  }

  /** 渲染一组照片引用：缩略图网格 + 下方"图 N/从相册导入"标注，超高自动续页。 */
  private static renderPhotoRefs(doc: PdfDocModel, cursor: LayoutCursor, refs: ReportPhotoRef[]): void {
    if (refs.length === 0) {
      return;
    }
    const rows = Math.ceil(refs.length / ReportComposer.THUMB_PER_ROW);
    for (let r = 0; r < rows; r++) {
      if (cursor.y + ReportComposer.THUMB_BLOCK_H > ReportComposer.BOTTOM_Y) {
        cursor.page = ReportComposer.newPage(doc);
        cursor.y = ReportComposer.TOP_Y;
      }
      for (let c = 0; c < ReportComposer.THUMB_PER_ROW; c++) {
        const idx = r * ReportComposer.THUMB_PER_ROW + c;
        if (idx >= refs.length) {
          break;
        }
        const ref = refs[idx];
        const img = new PdfImage();
        img.path = ref.thumbPath;
        img.x = ReportComposer.MARGIN_X + c * ReportComposer.THUMB_STEP_X;
        img.y = cursor.y;
        img.w = ReportComposer.THUMB_W;
        img.h = ReportComposer.THUMB_H;
        cursor.page.images.push(img);
        const caption = ReportComposer.photoCaption(ref);
        if (caption.length > 0) {
          ReportComposer.addLine(cursor.page, caption, img.x, cursor.y + ReportComposer.THUMB_H + 1,
            7, ReportComposer.GRAY, false);
        }
      }
      cursor.y += ReportComposer.THUMB_BLOCK_H;
    }
  }

  /** 细节照标注："图 N"，相册导入追加强制标注（产品文档 §3.4）。 */
  private static photoCaption(ref: ReportPhotoRef): string {
    let caption = ref.noText;
    if (ref.imported) {
      caption = caption.length > 0 ? `${caption}·从相册导入` : '从相册导入';
    }
    return caption;
  }

  private static panoramaCaption(ref: ReportPhotoRef): string {
    let caption = `全景 · ${ref.noText}`;
    if (ref.imported) {
      caption = `${caption} · 从相册导入`;
    }
    return caption;
  }

  private static newPage(doc: PdfDocModel): PdfPageModel {
    const page = new PdfPageModel();
    doc.pages.push(page);
    return page;
  }

  private static addLine(page: PdfPageModel, text: string, x: number, y: number,
    fontSize: number, color: number, bold: boolean): void {
    const line = new PdfTextLine();
    line.text = text;
    line.x = x;
    line.y = y;
    line.fontSize = fontSize;
    line.color = color;
    line.bold = bold;
    page.texts.push(line);
  }

  /**
   * 近似测宽（领域层无渲染引擎）：全角字符 ≈ fontSize，半角 ≈ 0.55 倍。
   * 仅用于断行判断，落盘精确宽度由 pdfService 渲染决定；
   * 渲染器可通过 compose(input, measure) 注入真实测宽函数（技术设计文档 §7.4）。
   */
  private static approxMeasure(text: string, fontSize: number): number {
    let w = 0;
    let i = 0;
    while (i < text.length) {
      const code = text.charCodeAt(i);
      // 增补平面字符（代理对）按一个全角宽度计，避免被拆成两个半角而低估宽度
      if (code >= 0xD800 && code <= 0xDBFF && i + 1 < text.length
        && text.charCodeAt(i + 1) >= 0xDC00 && text.charCodeAt(i + 1) <= 0xDFFF) {
        w += fontSize;
        i += 2;
        continue;
      }
      const full = (code >= 0x2E80 && code <= 0x9FFF) || (code >= 0xF900 && code <= 0xFAFF)
        || (code >= 0xFF00 && code <= 0xFFEF);
      w += full ? fontSize : fontSize * 0.55;
      i += 1;
    }
    return w;
  }

  /** 按 Unicode 码点截断（代理对不劈开），超长以省略号收尾。 */
  private static truncate(text: string, maxChars: number): string {
    if (text.length <= maxChars) {
      return text;
    }
    const keep = maxChars - 1;
    let count = 0;
    let end = 0;
    let i = 0;
    while (i < text.length && count < keep) {
      const code = text.charCodeAt(i);
      if (code >= 0xD800 && code <= 0xDBFF && i + 1 < text.length
        && text.charCodeAt(i + 1) >= 0xDC00 && text.charCodeAt(i + 1) <= 0xDFFF) {
        i += 2;
      } else {
        i += 1;
      }
      count++;
      end = i;
    }
    return `${text.substring(0, end)}…`;
  }

  private static statusText(status: string): string {
    if (status === ItemStatus.OK) {
      return '正常';
    }
    if (status === ItemStatus.ISSUE) {
      return '有问题';
    }
    if (status === ItemStatus.NA) {
      return '不适用';
    }
    if (status === ItemStatus.PENDING) {
      return '待检查';
    }
    return status;
  }
}
