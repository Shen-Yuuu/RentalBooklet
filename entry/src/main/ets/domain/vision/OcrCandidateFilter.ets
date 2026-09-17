/**
 * OCR 候选过滤（产品文档 §5.8）：纯 TS，零 Kit import。
 * 规则：仅保留"包含数字"的文本行作为候选读数；原文供用户核对，不加工不改写。
 * textRecognition API 不返回置信度，因此候选不含置信度字段（真实结构，不虚构）。
 */

/** 单个候选读数：value 为 OCR 原文行（含数字），用户点选后填入输入框核对。 */
export class OcrCandidate {
  value: string = '';
}

export class OcrCandidateFilter {
  /** 候选数上限：表盘场景有效行极少，超限说明识别噪声过多，截断保护 UI。 */
  static readonly MAX_CANDIDATES: number = 8;

  /** 是否包含数字字符（0-9）。不用正则：ArkTS 禁止正则字面量，字符码遍历更快。 */
  static containsDigit(text: string): boolean {
    for (let i = 0; i < text.length; i++) {
      const c = text.charCodeAt(i);
      if (c >= 0x30 && c <= 0x39) {
        return true;
      }
    }
    return false;
  }

  /**
   * 从 OCR 全部文本行提取候选读数：
   * 过滤空行与不含数字的行 → 去除首尾空白 → 按原文去重 → 截断至 MAX_CANDIDATES。
   */
  static extractCandidates(lines: string[]): OcrCandidate[] {
    const seen = new Set<string>();
    const out: OcrCandidate[] = [];
    for (const raw of lines) {
      const v = raw.trim();
      if (v.length === 0 || seen.has(v) || !OcrCandidateFilter.containsDigit(v)) {
        continue;
      }
      seen.add(v);
      const c = new OcrCandidate();
      c.value = v;
      out.push(c);
      if (out.length >= OcrCandidateFilter.MAX_CANDIDATES) {
        break;
      }
    }
    return out;
  }
}
