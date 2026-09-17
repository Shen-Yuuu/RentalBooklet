import { describe, it, expect } from '@ohos/hypium';
import { LayoutSpec, LayoutError, LayoutUtil } from '../main/ets/common/LayoutUtil';

export default function layoutUtilTest(): void {
  describe('LayoutUtil', () => {
    it('parse_standard_layout', 0, () => {
      const spec = LayoutUtil.parse('2-1-1-1');
      expect(spec.bedrooms).assertEqual(2);
      expect(spec.livingRooms).assertEqual(1);
      expect(spec.bathrooms).assertEqual(1);
      expect(spec.balconies).assertEqual(1);
    });

    it('format_round_trip', 0, () => {
      const spec = new LayoutSpec(3, 2, 2, 1);
      const text = LayoutUtil.format(spec);
      expect(text).assertEqual('3-2-2-1');
      const back = LayoutUtil.parse(text);
      expect(back.bedrooms).assertEqual(3);
      expect(back.balconies).assertEqual(1);
    });

    it('rejects_wrong_field_count', 0, () => {
      let threw = false;
      try {
        LayoutUtil.parse('2-1-1');
      } catch (e) {
        threw = e instanceof LayoutError;
      }
      expect(threw).assertTrue();
    });

    it('rejects_non_numeric', 0, () => {
      let threw = false;
      try {
        LayoutUtil.parse('a-b-c-d');
      } catch (e) {
        threw = e instanceof LayoutError;
      }
      expect(threw).assertTrue();
    });

    it('rejects_negative_and_empty_parts', 0, () => {
      let threwNegative = false;
      try {
        LayoutUtil.parse('2-1-1--1');
      } catch (e) {
        threwNegative = e instanceof LayoutError;
      }
      expect(threwNegative).assertTrue();

      let threwNegativeValue = false;
      try {
        LayoutUtil.parse('-1-1-1-0');
      } catch (e) {
        threwNegativeValue = e instanceof LayoutError;
      }
      expect(threwNegativeValue).assertTrue();
    });

    it('rejects_out_of_range', 0, () => {
      let threw = false;
      try {
        LayoutUtil.parse('99-1-1-0');
      } catch (e) {
        threw = e instanceof LayoutError;
      }
      expect(threw).assertTrue();
    });
  });
}
