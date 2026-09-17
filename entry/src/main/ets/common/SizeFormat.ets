/** 字节数 → 人类可读大小（纯函数，无 @kit 依赖，可安全进入本地单测 bundle）。 */
export class SizeFormat {
  static format(bytes: number): string {
    if (bytes < 1024) {
      return `${bytes} B`;
    }
    const kb = bytes / 1024;
    if (kb < 1024) {
      return `${SizeFormat.trim(kb)} KB`;
    }
    const mb = kb / 1024;
    if (mb < 1024) {
      return `${SizeFormat.trim(mb)} MB`;
    }
    const gb = mb / 1024;
    return `${SizeFormat.trim(gb)} GB`;
  }

  /** ≥100 取整，否则保留一位小数。 */
  private static trim(v: number): string {
    return v >= 100 ? v.toFixed(0) : v.toFixed(1);
  }
}
