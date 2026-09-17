import { describe, it, expect } from '@ohos/hypium';
import { OcrCandidate, OcrCandidateFilter } from '../main/ets/domain/vision/OcrCandidateFilter';

export default function ocrCandidateFilterTest(): void {
  describe('OcrCandidateFilter', () => {
    it('contains_digit_basic', 0, () => {
      expect(OcrCandidateFilter.containsDigit('01234.5')).assertTrue();
      expect(OcrCandidateFilter.containsDigit('水表 00123 m3')).assertTrue();
      expect(OcrCandidateFilter.containsDigit('')).assertFalse();
      expect(OcrCandidateFilter.containsDigit('水表读数')).assertFalse();
      expect(OcrCandidateFilter.containsDigit('m³')).assertFalse();
    });

    it('extract_filters_non_digit_lines', 0, () => {
      const out = OcrCandidateFilter.extractCandidates(['水表', '01234.56', '', 'm³', '  8801  ']);
      expect(out.length).assertEqual(2);
      expect(out[0].value).assertEqual('01234.56');
      expect(out[1].value).assertEqual('8801');
    });

    it('extract_dedupes_same_value', 0, () => {
      const out = OcrCandidateFilter.extractCandidates(['0123', ' 0123 ', '456']);
      expect(out.length).assertEqual(2);
      expect(out[0].value).assertEqual('0123');
      expect(out[1].value).assertEqual('456');
    });

    it('extract_caps_at_max_candidates', 0, () => {
      const lines: string[] = [];
      for (let i = 0; i < 20; i++) {
        lines.push(`${i * 111}`);
      }
      const out = OcrCandidateFilter.extractCandidates(lines);
      expect(out.length).assertEqual(OcrCandidateFilter.MAX_CANDIDATES);
    });

    it('extract_empty_input_returns_empty', 0, () => {
      const out: OcrCandidate[] = OcrCandidateFilter.extractCandidates([]);
      expect(out.length).assertEqual(0);
      const none = OcrCandidateFilter.extractCandidates(['无数字行', '   ']);
      expect(none.length).assertEqual(0);
    });
  });
}
