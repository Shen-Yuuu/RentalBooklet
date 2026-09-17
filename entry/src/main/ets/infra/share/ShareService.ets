/**
 * 系统分享封装（技术设计文档 D7，L9 交付链路）。
 * systemShare.SharedData：首记录 PDF 文件，追加摘要 + manifest.json + 原始照片
 * （多文件记录），ShareController.show 拉系统面板（微信/邮件/华为分享），免权限。
 *
 * 实测约束（官方错误码 1003702001）：BATCH 批量模式仅支持 UDMF.File 类记录，
 * 纯文本记录会被面板拒绝 → 摘要文本落为临时 txt 文件以 FILE 记录分享。
 * 照片超过上限（30 张）时只分享 PDF+摘要+清单，由调用方 Toast 说明。
 */

import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';

/** 分享结果：photoShared < photoTotal 表示照片超上限被裁剪（调用方提示）。 */
export class ShareOutcome {
  photoTotal: number = 0;
  photoShared: number = 0;
}

export class ShareService {
  /** 单次分享照片上限：超出仅分享 PDF + 摘要 + 校验清单。 */
  static readonly MAX_PHOTOS: number = 30;

  /**
   * 分享报告包：PDF（首记录）+ 摘要 txt + manifest.json（存在时）+ 原图（≤30 张）。
   * 分享面板拉起失败抛 Error；照片裁剪通过 ShareOutcome 告知，不算失败。
   */
  static async shareReport(ctx: common.UIAbilityContext, pdfPath: string,
    summaryText: string, photoPaths: string[], manifestPath: string): Promise<ShareOutcome> {
    const outcome = new ShareOutcome();
    outcome.photoTotal = photoPaths.length;

    const data: systemShare.SharedData = new systemShare.SharedData({
      utd: utd.UniformDataType.PDF,
      uri: fileUri.getUriFromPath(pdfPath),
      title: ShareService.baseNameOf(pdfPath),
      description: '租房留证 PDF 检查报告'
    });

    // 摘要：批量模式仅支持文件类记录，落为临时 txt（写失败则跳过该记录，不阻塞主分享）
    const summaryPath = ShareService.writeSummaryFile(ctx, summaryText);
    if (summaryPath.length > 0) {
      data.addRecord({
        utd: utd.UniformDataType.FILE,
        uri: fileUri.getUriFromPath(summaryPath),
        title: '报告摘要.txt'
      });
    }

    // 校验清单：交付包承诺"编号 ↔ 文件名 ↔ sha256"随包分发（产品文档 §5.4）
    if (manifestPath.length > 0 && ShareService.fileExists(manifestPath)) {
      data.addRecord({
        utd: utd.UniformDataType.FILE,
        uri: fileUri.getUriFromPath(manifestPath),
        title: 'manifest.json'
      });
    }

    const limit = Math.min(photoPaths.length, ShareService.MAX_PHOTOS);
    for (let i = 0; i < limit; i++) {
      data.addRecord({
        utd: utd.UniformDataType.JPEG,
        uri: fileUri.getUriFromPath(photoPaths[i]),
        title: ShareService.baseNameOf(photoPaths[i])
      });
    }
    outcome.photoShared = limit;

    const controller = new systemShare.ShareController(data);
    try {
      await controller.show(ctx, {
        selectionMode: systemShare.SelectionMode.BATCH,
        previewMode: systemShare.SharePreviewMode.DETAIL
      });
    } catch (err) {
      const e = err as BusinessError;
      throw new Error(`分享面板拉起失败 code=${e.code} message=${e.message}`);
    }
    return outcome;
  }

  /** 摘要写临时文件：先清理历史会话遗留（上次分享早已结束，可安全删除），成功返回路径。 */
  private static writeSummaryFile(ctx: common.UIAbilityContext, summaryText: string): string {
    ShareService.purgeStaleSummaries(ctx);
    if (summaryText.length === 0) {
      return '';
    }
    const path = `${ctx.tempDir}/report-summary-${Date.now()}.txt`;
    try {
      const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, summaryText);
      } finally {
        fs.closeSync(file);
      }
      return path;
    } catch (err) {
      return '';
    }
  }

  /** 清理分享摘要临时文件（report-summary-*.txt），单个失败忽略。 */
  private static purgeStaleSummaries(ctx: common.UIAbilityContext): void {
    try {
      const names = fs.listFileSync(ctx.tempDir);
      for (const name of names) {
        if (name.startsWith('report-summary-') && name.endsWith('.txt')) {
          try {
            fs.unlinkSync(`${ctx.tempDir}/${name}`);
          } catch (err) {
            // 单文件清理失败不阻塞分享
          }
        }
      }
    } catch (err) {
      // tempDir 不可读时忽略
    }
  }

  private static fileExists(path: string): boolean {
    try {
      return fs.accessSync(path);
    } catch (err) {
      return false;
    }
  }

  private static baseNameOf(path: string): string {
    const idx = path.lastIndexOf('/');
    return idx >= 0 ? path.substring(idx + 1) : path;
  }
}
