export interface RefineChange {
  ruleName: string;
  before: string;
  after: string;
}

export interface RefineResult {
  refined: string;
  changes: RefineChange[];
}

/**
 * 备注中性化改写：只整理语言，不判断成因与责任（产品文档 §5.7）。
 * 规则管道：主观/情绪词替换 → 对话归因标记 → 责任归因去名 → 句式建议（位置+对象+现象+尺寸）
 * → 中文数量词规范化 → "左右"改"约" → 补充说明转括注。
 * 替换一律按匹配位置切片进行（不用 String.replace(m[0])，避免相同子串在更早位置被误替换），
 * 每次替换逐条记录到 changes。
 */
export class TextRefiner {
  /** 主观词替换表（保守清单，宁可漏改不可改错事实）。 */
  private static readonly SUBJECTIVE: string[][] = [
    ['非常脏|特别脏|超级脏|很脏', '存在明显污渍'],
    ['有点脏|比较脏', '存在污渍'],
    ['破了个洞|有个洞|破了个口', '存在破损'],
    ['裂了个缝|有裂缝|裂了|开裂', '可见裂纹'],
    ['坏掉了|坏了|用不了|不能用了|失灵', '无法正常使用'],
    ['很旧|太旧|特别旧', '陈旧'],
    ['有划痕|划了一道|有道划痕|划花了', '存在划痕'],
    ['生锈了|锈了|有锈', '存在锈迹'],
    ['发霉了|长霉|有霉斑', '存在霉斑'],
    ['积水了|淹水', '存在积水']
  ];

  private static readonly ATTRIBUTION: RegExp = /(房东|中介|物业)(说|讲|要求|让|认为|觉得)/g;
  private static readonly SELF_BLAME: RegExp =
    /(被我弄坏[了的]?|是我弄坏[了的]?|我弄坏[了的]?|被我搞坏[了的]?|我搞坏[了的]?|被我碰坏[了的]?|是我碰坏[了的]?|我碰坏[了的]?)/g;
  /** 句式建议（§5.7）：口语裂缝描述 → "位置+对象+现象+尺寸"句式。 */
  private static readonly CRACK: RegExp =
    /(有|长了?|出现)(一[条道处])?(约)?([0-9一二两三四五六七八九十]+)?(厘米|公分|毫米|米)?(左右|上下)?的?(裂缝|裂纹|裂痕)/g;
  /** 句式建议（§5.7）："，入住时已经存在" → "（入住时已存在）"括注。 */
  private static readonly EXISTED: RegExp = /(，)?(入住时|收房时|交房时|退租时)已[经]?(存在|有了?)/g;
  private static readonly CN_QTY: RegExp =
    /([一两二三四五六七八九]十[一两二三四五六七八九]?|[一两二三四五六七八九十])(厘米|公分|毫米|米)(左右|上下)?/g;
  private static readonly APPROX: RegExp = /(\d+)\s*(厘米|公分|毫米|米)\s*(左右|上下)/g;

  private static cnDigit(ch: string): number {
    if (ch === '两') {
      return 2;
    }
    if (ch === '十') {
      return 10;
    }
    const digits: string = '零一二三四五六七八九';
    const idx = digits.indexOf(ch);
    return idx < 0 ? -1 : idx;
  }

  /** 中文数量词转阿拉伯数字；无法解析的（如"两三米"）原样返回。 */
  private static parseCnNumber(text: string): string {
    if (text === '十') {
      return '10';
    }
    if (text.endsWith('十')) {
      const head = TextRefiner.cnDigit(text.charAt(0));
      return head > 0 ? `${head * 10}` : text;
    }
    const mid = text.indexOf('十');
    if (mid > 0) {
      const head = TextRefiner.cnDigit(text.charAt(0));
      const tail = TextRefiner.cnDigit(text.charAt(text.length - 1));
      if (head > 0 && tail >= 0) {
        return `${head * 10 + tail}`;
      }
    }
    if (text.length === 1) {
      const v = TextRefiner.cnDigit(text);
      return v >= 0 ? `${v}` : text;
    }
    return text;
  }

  /** 裂缝句式改写：有数量 → "可见线状裂纹，长度约 N 厘米"（§5.7 示例口径）；无数量 → "可见线状裂纹"。 */
  private static buildCrack(m: RegExpExecArray): string {
    const qtyRaw = m[4] === undefined ? '' : m[4];
    const unitRaw = m[5] === undefined ? '' : m[5];
    const unit = unitRaw === '公分' ? '厘米' : unitRaw;
    if (qtyRaw.length === 0 || unit.length === 0) {
      return '可见线状裂纹';
    }
    if (/^[0-9]+$/.test(qtyRaw)) {
      return `可见线状裂纹，长度约 ${qtyRaw} ${unit}`;
    }
    const converted = TextRefiner.parseCnNumber(qtyRaw);
    if (converted !== qtyRaw) {
      return `可见线状裂纹，长度约 ${converted} ${unit}`;
    }
    // 歧义数量（如"两三"）原样保留，不强行数字化
    return `可见线状裂纹，长度约${qtyRaw}${unit}`;
  }

  /**
   * 按匹配位置切片替换并逐条记录 changes；build 返回 null 表示保留原文（歧义保护跳过）。
   * 所有规则共用，保证多次出现全部改写、且替换发生在匹配位置而非同串首次出现位置。
   */
  private static applyRule(out: string, reg: RegExp, ruleName: string,
    build: (m: RegExpExecArray) => string | null, changes: RefineChange[]): string {
    reg.lastIndex = 0;
    let result = '';
    let cursor = 0;
    let m = reg.exec(out);
    while (m !== null) {
      const after = build(m);
      result += out.substring(cursor, m.index);
      if (after !== null) {
        result += after;
        changes.push({ ruleName: ruleName, before: m[0], after: after });
      } else {
        result += m[0];
      }
      cursor = m.index + m[0].length;
      m = reg.exec(out);
    }
    result += out.substring(cursor);
    return result;
  }

  static refine(text: string): RefineResult {
    let out = text;
    const changes: RefineChange[] = [];

    for (const rule of TextRefiner.SUBJECTIVE) {
      const reg = new RegExp(rule[0], 'g');
      out = TextRefiner.applyRule(out, reg, '主观词改客观描述', () => rule[1], changes);
    }

    out = TextRefiner.applyRule(out, TextRefiner.ATTRIBUTION, '对话归因标记为转述', (m) => {
      // 说/讲/认为/觉得 → 转述引导语；要求/让 → 保留祈使语义但去除具体归因对象
      // （"房东要求维修"→"对方要求维修"，避免转述强度失真）
      const verb = m[2];
      if (verb === '要求' || verb === '让') {
        return '对方要求';
      }
      return '据对方表述，';
    }, changes);

    out = TextRefiner.applyRule(out, TextRefiner.SELF_BLAME, '去除责任归因',
      () => '成因未确认', changes);

    out = TextRefiner.applyRule(out, TextRefiner.CRACK, '句式建议（现象+尺寸）',
      (m) => TextRefiner.buildCrack(m), changes);

    out = TextRefiner.applyRule(out, TextRefiner.CN_QTY, '口语数量规范化', (m) => {
      // 歧义保护：前一字符也是中文数字（如"两三米"）时不转换
      const prevChar = m.index > 0 ? m.input.charAt(m.index - 1) : '';
      const prevIsDigit = prevChar.length > 0 && TextRefiner.cnDigit(prevChar) >= 0;
      if (prevIsDigit) {
        return null;
      }
      const converted = TextRefiner.parseCnNumber(m[1]);
      if (converted === m[1]) {
        return null;
      }
      // 口语回忆值统一按近似值处理（§5.7 规范表达"约 10 厘米"）；"左右"后缀一并消费避免二次量化
      return `约${converted}${m[2]}`;
    }, changes);

    out = TextRefiner.applyRule(out, TextRefiner.APPROX, '模糊量化改精确表述',
      (m) => `约${m[1]}${m[2]}`, changes);

    out = TextRefiner.applyRule(out, TextRefiner.EXISTED, '补充说明转括注',
      (m) => `（${m[2]}已存在）`, changes);

    const result: RefineResult = { refined: out, changes: changes };
    return result;
  }
}
