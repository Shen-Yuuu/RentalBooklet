import { describe, it, expect } from '@ohos/hypium';
import { QualityHeuristics } from '../main/ets/domain/media/QualityHeuristics';

function solidBuffer(r: number, g: number, b: number, pixels: number): Uint8Array {
  const buf = new Uint8Array(pixels * 4);
  for (let i = 0; i < pixels; i++) {
    buf[i * 4] = r;
    buf[i * 4 + 1] = g;
    buf[i * 4 + 2] = b;
    buf[i * 4 + 3] = 255;
  }
  return buf;
}

export default function qualityHeuristicsTest(): void {
  describe('QualityHeuristics', () => {
    it('white_buffer_full_luma', 0, () => {
      const luma = QualityHeuristics.averageLuma(solidBuffer(255, 255, 255, 64), 1);
      expect(luma > 254).assertTrue();
      expect(QualityHeuristics.isTooDark(luma)).assertFalse();
    });

    it('black_buffer_zero_luma_too_dark', 0, () => {
      const luma = QualityHeuristics.averageLuma(solidBuffer(0, 0, 0, 64), 1);
      expect(luma).assertEqual(0);
      expect(QualityHeuristics.isTooDark(luma)).assertTrue();
      expect(QualityHeuristics.qualityFlagFor(luma)).assertEqual('TOO_DARK');
    });

    it('step_sampling_consistent', 0, () => {
      const buf = solidBuffer(100, 150, 200, 256);
      const full = QualityHeuristics.averageLuma(buf, 1);
      const stepped = QualityHeuristics.averageLuma(buf, 8);
      expect(Math.abs(full - stepped) < 0.001).assertTrue();
    });

    it('empty_buffer_safe', 0, () => {
      expect(QualityHeuristics.averageLuma(new Uint8Array(0), 4)).assertEqual(0);
    });
  });
}
