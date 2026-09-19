/**
 * PDF Kit 渲染器（技术设计文档 §7.4 / D1 实测签名）。
 * PdfDocModel → pdfService 调用序列：createDocument → insertBlankPage →
 * addImageObject/addTextObject → saveDocument → releaseDocument。
 * 降级策略（v1.1）：saveDocument 失败/异常统一上抛"当前设备不支持生成 PDF"，
 * 不做截图降级渲染器；UI 层保留摘要文本兜底展示。
 */

import { pdfService } from '@kit.PDFKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { PdfDocModel } from '../../domain/report/ReportComposer';

export class PdfKitRenderer {
  static readonly PAGE_W: number = 595;
  static readonly PAGE_H: number = 842;
  /** 措辞红线：设备不支持时的固定提示（L9 异常分支）。 */
  static readonly NOT_SUPPORTED_MSG: string = '当前设备不支持生成 PDF';

  /**
   * 渲染文档模型到 outPath（沙箱绝对路径）。
   * fontPath 由调用方经 UIContext.getFont().getFontByName() 解析后传入
   * （Font 不可直接构造，需 UIContext 获取）；解析失败传空串走默认字体。
   * 失败上抛带原因的 Error，不静默；成功后调用方负责计算 pdf sha256。
   */
  static async render(model: PdfDocModel, outPath: string, fontPath: string = ''): Promise<void> {
    if (model.pages.length === 0) {
      throw new Error('PDF 文档模型为空，无法生成');
    }
    const dir = outPath.substring(0, outPath.lastIndexOf('/'));
    try {
      fs.mkdirSync(dir, true);
    } catch (err) {
      // 目录已存在时忽略，其他 IO 错误由后续写入暴露
    }

    let doc: pdfService.PdfDocument | undefined = undefined;
    try {
      doc = new pdfService.PdfDocument();
      if (!doc.createDocument(PdfKitRenderer.PAGE_W, PdfKitRenderer.PAGE_H)) {
        throw new Error(PdfKitRenderer.NOT_SUPPORTED_MSG);
      }
      for (let i = 0; i < model.pages.length; i++) {
        const pm = model.pages[i];
        const page = doc.insertBlankPage(i, PdfKitRenderer.PAGE_W, PdfKitRenderer.PAGE_H);
        // 先图后文：图片垫底，文本覆盖在上
        for (const img of pm.images) {
          if (img.path.length > 0) {
            page.addImageObject(img.path, img.x, img.y, img.w, img.h);
          }
        }
        for (const t of pm.texts) {
          const style = new pdfService.TextStyle();
          style.textSize = t.fontSize;
          style.textColor = t.color;
          style.isBold = t.bold;
          if (fontPath.length > 0) {
            const fontInfo = new pdfService.FontInfo();
            fontInfo.fontPath = fontPath;
            style.fontInfo = fontInfo;
          }
          page.addTextObject(t.text, t.x, t.y, style);
        }
      }
      if (!doc.saveDocument(outPath)) {
        throw new Error(PdfKitRenderer.NOT_SUPPORTED_MSG);
      }
    } catch (err) {
      if (err instanceof Error && err.message === PdfKitRenderer.NOT_SUPPORTED_MSG) {
        throw err;
      }
      const e = err as BusinessError;
      throw new Error(`${PdfKitRenderer.NOT_SUPPORTED_MSG}（code=${e.code} ${e.message}）`);
    } finally {
      if (doc !== undefined) {
        try {
          doc.releaseDocument();
        } catch (err) {
          // 释放失败不掩盖主错误
        }
      }
    }
  }
}
