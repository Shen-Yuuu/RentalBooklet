import { describe, it, expect } from '@ohos/hypium';
import { MeasureFn, TextLineBreaker } from '../main/ets/domain/report/TextLineBreaker';

/** 伪测宽：每字符宽度 = fontSize（简单可控）。 */
function charMeasure(): MeasureFn {
  return (text: string, fontSize: number): number => text.length * fontSize;
}

/** 中英混排伪测宽：全角字符 = fontSize，半角字符 = 0.5 * fontSize。 */
function cjkMeasure(): MeasureFn {
  return (text: string, fontSize: number): number => {
    let w = 0;
    for (let i = 0; i < text.length; i++) {
      const code = text.charCodeAt(i);
      const full = (code >= 0x2E80 && code <= 0x9FFF) || (code >= 0xFF00 && code <= 0xFFEF);
      w += full ? fontSize : fontSize * 0.5;
    }
    return w;
  };
}

export default function textLineBreakerTest(): void {
  describe('TextLineBreaker', () => {
    it('short_text_returns_single_line', 0, () => {
      const lines = TextLineBreaker.breakLines('abc', 100, 10, charMeasure());
      expect(lines.length).assertEqual(1);
      expect(lines[0]).assertEqual('abc');
    });

    it('wide_text_breaks_by_measure', 0, () => {
      const lines = TextLineBreaker.breakLines('aaaaaaaaaa', 50, 10, charMeasure());
      expect(lines.length).assertEqual(2);
      expect(lines[0]).assertEqual('aaaaa');
      expect(lines[1]).assertEqual('aaaaa');
    });

    it('newline_forces_break', 0, () => {
      const lines = TextLineBreaker.breakLines('ab\ncd', 100, 10, charMeasure());
      expect(lines.length).assertEqual(2);
      expect(lines[0]).assertEqual('ab');
      expect(lines[1]).assertEqual('cd');
    });

    it('empty_string_returns_single_empty_line', 0, () => {
      const lines = TextLineBreaker.breakLines('', 100, 10, charMeasure());
      expect(lines.length).assertEqual(1);
      expect(lines[0]).assertEqual('');
    });

    it('consecutive_newlines_produce_empty_lines', 0, () => {
      const lines = TextLineBreaker.breakLines('a\n\nb', 100, 10, charMeasure());
      expect(lines.length).assertEqual(3);
      expect(lines[1]).assertEqual('');
    });

    it('exact_width_boundary_not_broken', 0, () => {
      // 5 字符 × 10 = 50，恰好等宽：不断行
      const lines = TextLineBreaker.breakLines('aaaaa', 50, 10, charMeasure());
      expect(lines.length).assertEqual(1);
      expect(lines[0]).assertEqual('aaaaa');
    });

    it('long_no_space_string_breaks', 0, () => {
      const lines = TextLineBreaker.breakLines('abcdefghijkl', 40, 10, charMeasure());
      expect(lines.length).assertEqual(3);
      expect(lines[0]).assertEqual('abcd');
      expect(lines[1]).assertEqual('efgh');
      expect(lines[2]).assertEqual('ijkl');
    });

    it('join_restores_original_text', 0, () => {
      // maxWidth 足够宽（无段内断行）时，仅显式 \n 生效：join('\n') 严格还原原文
      const text = '中英文混排测试with newlines\n第二段落也足够长需要断行处理一下\n\n尾段';
      const lines = TextLineBreaker.breakLines(text, 500, 10, cjkMeasure());
      expect(lines.length).assertEqual(4);
      expect(lines.join('\n')).assertEqual(text);
    });

    it('wrapped_lines_lose_no_chars', 0, () => {
      // 段内断行发生时不丢字：各行拼接（无分隔符）还原该段原文，且每行不超宽
      const para = '中英文混排测试with newlines';
      const lines = TextLineBreaker.breakLines(para, 60, 10, cjkMeasure());
      expect(lines.length).assertEqual(3);
      expect(lines.join('')).assertEqual(para);
      for (const line of lines) {
        expect(cjkMeasure()(line, 10) <= 60).assertTrue();
      }
    });

    it('single_char_over_width_still_emitted', 0, () => {
      // 每个字符都超宽：逐字独占一行，不丢字、不死循环
      const huge: MeasureFn = (text: string, fontSize: number): number => 1000 + text.length;
      const lines = TextLineBreaker.breakLines('abc', 10, 10, huge);
      expect(lines.length).assertEqual(3);
      expect(lines.join('')).assertEqual('abc');
    });

    it('cjk_mixed_text_breaks_at_width', 0, () => {
      // '中文'=20，'abcd'=20：20+20 > 30 → 英文词元不拆断，整体移入下一行
      const lines = TextLineBreaker.breakLines('中文abcd', 30, 10, cjkMeasure());
      expect(lines.length).assertEqual(2);
      expect(lines[0]).assertEqual('中文');
      expect(lines[1]).assertEqual('abcd');
      expect(lines.join('')).assertEqual('中文abcd');
    });

    it('english_word_not_split_mid_word', 0, () => {
      // 中(10)英(20)文(30)；word 需 20 → 30+20 > 45 整词换行；word(20)+测(30)+试(40) ≤ 45 同行
      const lines = TextLineBreaker.breakLines('中英文word测试', 45, 10, cjkMeasure());
      expect(lines.length).assertEqual(2);
      expect(lines[0]).assertEqual('中英文');
      expect(lines[1]).assertEqual('word测试');
      expect(lines.join('')).assertEqual('中英文word测试');
    });

    it('url_kept_intact_on_own_line', 0, () => {
      // URL 为整体词元：行内放不下时整条移入下一行，不在中间拆断
      const url = 'https://example.com/a/b?x=1';
      const lines = TextLineBreaker.breakLines(`详见 ${url} 说明`, 280, 10, charMeasure());
      expect(lines.length).assertEqual(3);
      expect(lines[0]).assertEqual('详见 ');
      expect(lines[1]).assertEqual(`${url} `);
      expect(lines[2]).assertEqual('说明');
      expect(lines.join('')).assertEqual(`详见 ${url} 说明`);
    });
  });
}
