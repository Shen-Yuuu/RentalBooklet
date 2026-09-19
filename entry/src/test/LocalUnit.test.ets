import { describe, it, expect } from '@ohos/hypium';
import { ManifestBuilder } from '../main/ets/domain/manifest/ManifestBuilder';

/**
 * 基础冒烟断言（替代脚手架遗留的恒真断言）：
 * 锁定报告号格式与免责文案措辞红线——两者是冻结与交付链路的契约常量。
 */
export default function localUnitTest() {
  describe('localUnitTest', () => {
    it('report_no_format', 0, () => {
      expect(ManifestBuilder.generateReportNo('20260919', 1)).assertEqual('RB-20260919-0001');
      expect(ManifestBuilder.generateReportNo('20260919', 1234)).assertEqual('RB-20260919-1234');
    });

    it('manifest_disclaimer_wording', 0, () => {
      // 措辞红线：校验值只用于检测文件变化，不得表述为司法鉴定/存证
      expect(ManifestBuilder.DISCLAIMER.includes('仅用于检测文件在生成后是否发生变化')).assertTrue();
      expect(ManifestBuilder.DISCLAIMER.includes('不代表司法鉴定或官方存证')).assertTrue();
    });
  });
}
