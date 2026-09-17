import { textRecognition } from '@kit.CoreVisionKit';
import { image } from '@kit.ImageKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { OcrCandidate, OcrCandidateFilter } from '../../domain/vision/OcrCandidateFilter';

/**
 * 表盘 OCR（技术设计文档 D3）：Core Vision Kit textRecognition 端侧离线识别。
 * 实测 API 要点（以官方文档为准）：
 * - import { textRecognition } from '@kit.CoreVisionKit'，仅 Stage 模型；
 * - init(): Promise<boolean>（API 12+），返回 false 即服务不可用（模拟器上可能 undefined）；
 * - recognizeText(VisionInfo{pixelMap}): Promise<TextRecognitionResult>，
 *   结构 result.blocks[] → block.lines[] → line.value（无置信度字段）；
 * - PixelMap 要求 RGBA_8888，image.createImageSource(fd).createPixelMap() 默认即满足。
 * 失败/不可用一律抛带文案 Error（'OCR 当前不可用，请手动输入读数'），绝不静默返回空。
 */
export class OcrService {
  static readonly UNAVAILABLE_MESSAGE: string = 'OCR 当前不可用，请手动输入读数';

  /**
   * 识别图片中的候选读数：文件路径 → ImageSource → PixelMap → recognizeText →
   * 提取全部文本行 → OcrCandidateFilter 过滤出含数字候选。
   * 识别成功但无含数字行时返回空数组（调用方据此展示手动输入引导）。
   */
  static async recognize(imagePath: string): Promise<OcrCandidate[]> {
    let inited = false;
    try {
      inited = await textRecognition.init();
    } catch (err) {
      // 模拟器等环境下 textRecognition 命名空间可能为 undefined
      throw new Error(OcrService.UNAVAILABLE_MESSAGE);
    }
    if (!inited) {
      throw new Error(OcrService.UNAVAILABLE_MESSAGE);
    }

    const srcFile = fs.openSync(imagePath, fs.OpenMode.READ_ONLY);
    let source: image.ImageSource | null = null;
    let pixel: image.PixelMap | null = null;
    try {
      source = image.createImageSource(srcFile.fd);
      pixel = await source.createPixelMap();
      const visionInfo: textRecognition.VisionInfo = { pixelMap: pixel };
      const result = await textRecognition.recognizeText(visionInfo);
      const lines: string[] = [];
      for (const block of result.blocks) {
        for (const line of block.lines) {
          lines.push(line.value);
        }
      }
      return OcrCandidateFilter.extractCandidates(lines);
    } catch (err) {
      const e = err as BusinessError;
      // 200 超时 / 401 参数 / 1001400001~2 服务异常：统一降级为手动输入引导
      throw new Error(OcrService.UNAVAILABLE_MESSAGE);
    } finally {
      if (pixel !== null) {
        pixel.release();
      }
      if (source !== null) {
        await source.release();
      }
      fs.closeSync(srcFile.fd);
      try {
        await textRecognition.release();
      } catch (err) {
        // 释放失败不影响结果返回
      }
    }
  }
}
