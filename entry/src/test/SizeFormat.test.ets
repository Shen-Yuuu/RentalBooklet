import { describe, it, expect } from '@ohos/hypium';
import { SizeFormat } from '../main/ets/common/SizeFormat';

export default function sizeFormatTest(): void {
  describe('SizeFormat', () => {
    it('bytes_below_1kb', 0, () => {
      expect(SizeFormat.format(0)).assertEqual('0 B');
      expect(SizeFormat.format(512)).assertEqual('512 B');
      expect(SizeFormat.format(1023)).assertEqual('1023 B');
    });

    it('kb_range', 0, () => {
      expect(SizeFormat.format(1024)).assertEqual('1.0 KB');
      expect(SizeFormat.format(2048)).assertEqual('2.0 KB');
      expect(SizeFormat.format(1536)).assertEqual('1.5 KB');
    });

    it('mb_range', 0, () => {
      expect(SizeFormat.format(1024 * 1024)).assertEqual('1.0 MB');
      expect(SizeFormat.format(5 * 1024 * 1024)).assertEqual('5.0 MB');
      expect(SizeFormat.format(1536 * 1024)).assertEqual('1.5 MB');
    });

    it('gb_range', 0, () => {
      expect(SizeFormat.format(1024 * 1024 * 1024)).assertEqual('1.0 GB');
      expect(SizeFormat.format(2.5 * 1024 * 1024 * 1024)).assertEqual('2.5 GB');
    });

    it('large_values_trim_to_integer', 0, () => {
      // ≥100 单位后取整
      expect(SizeFormat.format(100 * 1024)).assertEqual('100 KB');
      expect(SizeFormat.format(999 * 1024)).assertEqual('999 KB');
      expect(SizeFormat.format(123.7 * 1024 * 1024)).assertEqual('124 MB');
    });
  });
}
