/**
 * 照片轻量质量启发式：只在 UI 提示，不拦截、不判定证据效力。
 * 输入来自 RGBA_8888 缓冲的抽样亮度。
 */
export class QualityHeuristics {
  static readonly DARK_THRESHOLD: number = 60;

  /** 从 RGBA_8888 缓冲抽样计算平均亮度（0~255）。step=1 表示逐像素，>1 为跨步抽样。 */
  static averageLuma(rgba: Uint8Array, step: number): number {
    const stride = Math.max(1, step) * 4;
    let total = 0;
    let count = 0;
    for (let off = 0; off + 3 < rgba.length; off += stride) {
      total += 0.299 * rgba[off] + 0.587 * rgba[off + 1] + 0.114 * rgba[off + 2];
      count++;
    }
    return count === 0 ? 0 : total / count;
  }

  static isTooDark(avgLuma: number): boolean {
    return avgLuma < QualityHeuristics.DARK_THRESHOLD;
  }

  static qualityFlagFor(avgLuma: number): string {
    return QualityHeuristics.isTooDark(avgLuma) ? 'TOO_DARK' : '';
  }
}
