/**
 * 校验清单（manifest）构建与解析（技术设计文档 §4.4）。
 * 纯 TS：文件顶部零 @ohos/@kit import，可被本地单测直接覆盖。
 * 措辞红线：disclaimer 固定文案，不得改动（法务评审后进包）。
 */

export class ManifestError extends Error {
  constructor(message: string) {
    super(message);
  }
}

/** 清单内单个文件条目：relPath 相对检查目录（如 photos/xxx.jpg）。 */
export class ManifestFile {
  relPath: string = '';
  bytes: number = 0;
  sha256: string = '';
}

/** manifest 反序列化结果（复查用）。 */
export class ManifestContent {
  reportNo: string = '';
  inspectionId: number = 0;
  revisionNo: number = 0;
  generatedAt: number = 0;
  algorithm: string = '';
  files: ManifestFile[] = [];
  disclaimer: string = '';
}

export class ManifestBuilder {
  static readonly ALGORITHM: string = 'SHA-256';
  static readonly DISCLAIMER: string =
    '校验值仅用于检测文件在生成后是否发生变化，不代表司法鉴定或官方存证。';

  /**
   * 构建清单 JSON 字符串。
   * 结构：{reportNo, inspectionId, revisionNo, generatedAt, algorithm:'SHA-256',
   *        files:[{relPath,bytes,sha256}], disclaimer}
   */
  static build(reportNo: string, inspectionId: number, revisionNo: number,
    generatedAt: number, files: ManifestFile[]): string {
    const content = new ManifestContent();
    content.reportNo = reportNo;
    content.inspectionId = inspectionId;
    content.revisionNo = revisionNo;
    content.generatedAt = generatedAt;
    content.algorithm = ManifestBuilder.ALGORITHM;
    content.files = files;
    content.disclaimer = ManifestBuilder.DISCLAIMER;
    return JSON.stringify(content);
  }

  /** 解析清单（复查用）：字段缺失时容错回退为默认值，非法 JSON 抛 ManifestError。 */
  static parse(content: string): ManifestContent {
    let parsed: object | null = null;
    try {
      parsed = JSON.parse(content);
    } catch (err) {
      throw new ManifestError('校验清单不是合法的 JSON');
    }
    if (parsed === null) {
      throw new ManifestError('校验清单内容为空');
    }
    const raw = parsed as ManifestContent;
    const result = new ManifestContent();
    result.reportNo = typeof raw.reportNo === 'string' ? raw.reportNo : '';
    result.inspectionId = typeof raw.inspectionId === 'number' ? raw.inspectionId : 0;
    result.revisionNo = typeof raw.revisionNo === 'number' ? raw.revisionNo : 0;
    result.generatedAt = typeof raw.generatedAt === 'number' ? raw.generatedAt : 0;
    result.algorithm = typeof raw.algorithm === 'string' ? raw.algorithm : '';
    result.disclaimer = typeof raw.disclaimer === 'string' ? raw.disclaimer : '';
    if (Array.isArray(raw.files)) {
      for (const f of raw.files) {
        const mf = f as ManifestFile;
        const file = new ManifestFile();
        file.relPath = typeof mf.relPath === 'string' ? mf.relPath : '';
        file.bytes = typeof mf.bytes === 'number' ? mf.bytes : 0;
        file.sha256 = typeof mf.sha256 === 'string' ? mf.sha256 : '';
        result.files.push(file);
      }
    }
    return result;
  }

  /**
   * 报告号：RB-YYYYMMDD-xxxx，seq 补零至 4 位；超过 9999 不截断。
   * dateStr 容忍 'YYYY-MM-DD' / 'YYYYMMDD' 等写法（取前 8 位数字）。
   */
  static generateReportNo(dateStr: string, seq: number): string {
    if (seq < 1) {
      throw new ManifestError(`非法报告序号: ${seq}`);
    }
    const digits = dateStr.replace(new RegExp('[^0-9]', 'g'), '');
    if (digits.length < 8) {
      throw new ManifestError(`非法日期串: ${dateStr}`);
    }
    return `RB-${digits.substring(0, 8)}-${ManifestBuilder.pad4(seq)}`;
  }

  private static pad4(seq: number): string {
    if (seq < 10) {
      return `000${seq}`;
    }
    if (seq < 100) {
      return `00${seq}`;
    }
    if (seq < 1000) {
      return `0${seq}`;
    }
    return `${seq}`;
  }
}
