/**
 * PDF 文本断行器（技术设计文档 §7.1）。
 * 纯 TS：零 @ohos/@kit import，可被本地单测直接覆盖。
 * 测宽函数由调用方注入（渲染器传 measureText，单测传伪实现），保持领域层零 ArkUI 依赖。
 * pdfService.addTextObject 只可按行添加 → 长文本必须先断行。
 * 英文单词与 URL 不拆断：整体移入下一行；仅当词元自身超宽时才按字符强制拆分。
 */

/** 测宽函数：返回 text 在 fontSize 字号下的渲染宽度（单位与 maxWidthPx 一致）。 */
export type MeasureFn = (text: string, fontSize: number) => number;

export class TextLineBreaker {
  /** 连续的英文字母/数字/URL 字符视为一个词元（含 http(s)://、路径、查询串），不拆断。 */
  private static readonly WORD: RegExp = /[A-Za-z0-9][A-Za-z0-9\-._~:/?#\[\]@!$&'()*+,;=%]*/g;

  /**
   * 断行规则：
   * - 换行符 '\n' 强制断行（连续换行产生空行）；
   * - 英文单词/URL 作为整体词元，超宽时整词移入下一行；
   * - 词元自身宽度超过 maxWidthPx 时按字符强制拆分（避免丢字/死循环）；
   * - 中日韩及标点按字符累积测宽断行；
   * - 恰好等宽（== maxWidthPx）不断行；
   * - 空串返回 ['']。
   * 段内断行不丢字：被断行的各行直接拼接（join('')）可还原该段原文；
   * 仅当无段内断行（每段都 fits maxWidthPx）时，lines.join('\n') 才严格等于原文。
   */
  static breakLines(text: string, maxWidthPx: number, fontSize: number, measure: MeasureFn): string[] {
    if (text.length === 0) {
      return [''];
    }
    const result: string[] = [];
    const paragraphs = text.split('\n');
    for (const para of paragraphs) {
      if (para.length === 0) {
        result.push('');
        continue;
      }
      const tokens = TextLineBreaker.tokenize(para);
      let line = '';
      let lineW = 0;
      for (const token of tokens) {
        const tokenW = measure(token, fontSize);
        if (tokenW > maxWidthPx && token.length > 1) {
          // 超宽词元：当前行先收尾，再按字符拆分该词元
          if (line.length > 0) {
            result.push(line);
            line = '';
            lineW = 0;
          }
          for (const ch of TextLineBreaker.splitCodePoints(token)) {
            const chW = measure(ch, fontSize);
            if (line.length > 0 && lineW + chW > maxWidthPx) {
              result.push(line);
              line = '';
              lineW = 0;
            }
            line += ch;
            lineW += chW;
          }
          continue;
        }
        if (line.length > 0 && lineW + tokenW > maxWidthPx) {
          result.push(line);
          line = '';
          lineW = 0;
        }
        line += token;
        lineW += tokenW;
      }
      result.push(line);
    }
    return result;
  }

  /** 词元化：英文/URL 连续段为一个词元，其余字符逐字成元；所有词元拼接严格还原原文。 */
  private static tokenize(para: string): string[] {
    const tokens: string[] = [];
    TextLineBreaker.WORD.lastIndex = 0;
    let cursor = 0;
    let m = TextLineBreaker.WORD.exec(para);
    while (m !== null) {
      if (m.index > cursor) {
        TextLineBreaker.pushChars(tokens, para.substring(cursor, m.index));
      }
      tokens.push(m[0]);
      cursor = m.index + m[0].length;
      m = TextLineBreaker.WORD.exec(para);
    }
    if (cursor < para.length) {
      TextLineBreaker.pushChars(tokens, para.substring(cursor));
    }
    return tokens;
  }

  private static pushChars(tokens: string[], chunk: string): void {
    for (const ch of TextLineBreaker.splitCodePoints(chunk)) {
      tokens.push(ch);
    }
  }

  /** 按 Unicode 码点切分：代理对（emoji 等增补平面字符）作为一个单元，不产生孤立代理项。 */
  private static splitCodePoints(s: string): string[] {
    const out: string[] = [];
    let i = 0;
    while (i < s.length) {
      const code = s.charCodeAt(i);
      if (code >= 0xD800 && code <= 0xDBFF && i + 1 < s.length) {
        const low = s.charCodeAt(i + 1);
        if (low >= 0xDC00 && low <= 0xDFFF) {
          out.push(s.substring(i, i + 2));
          i += 2;
          continue;
        }
      }
      out.push(s.charAt(i));
      i += 1;
    }
    return out;
  }
}
