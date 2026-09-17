import { describe, it, expect } from '@ohos/hypium';
import { ManifestBuilder, ManifestContent, ManifestError, ManifestFile } from '../main/ets/domain/manifest/ManifestBuilder';

function makeFile(relPath: string, bytes: number, sha256: string): ManifestFile {
  const f = new ManifestFile();
  f.relPath = relPath;
  f.bytes = bytes;
  f.sha256 = sha256;
  return f;
}

export default function manifestBuilderTest(): void {
  describe('ManifestBuilder', () => {
    it('build_has_top_level_fields', 0, () => {
      const json = ManifestBuilder.build('RB-20260915-0001', 7, 0, 1789315200000, []);
      const c = ManifestBuilder.parse(json);
      expect(c.reportNo).assertEqual('RB-20260915-0001');
      expect(c.inspectionId).assertEqual(7);
      expect(c.revisionNo).assertEqual(0);
      expect(c.generatedAt).assertEqual(1789315200000);
      expect(c.algorithm).assertEqual('SHA-256');
      expect(c.files.length).assertEqual(0);
    });

    it('build_contains_fixed_disclaimer', 0, () => {
      const json = ManifestBuilder.build('RB-20260915-0001', 7, 0, 1789315200000, []);
      expect(json.includes('校验值仅用于检测文件在生成后是否发生变化，不代表司法鉴定或官方存证。')).assertTrue();
      const c = ManifestBuilder.parse(json);
      expect(c.disclaimer).assertEqual(ManifestBuilder.DISCLAIMER);
    });

    it('build_serializes_files_array', 0, () => {
      const files: ManifestFile[] = [
        makeFile('photos/101.jpg', 2048111, '3b1f00e9'),
        makeFile('photos/102.jpg', 1534000, 'aa11bb22')
      ];
      const json = ManifestBuilder.build('RB-20260915-0002', 8, 1, 1789315300000, files);
      expect(json.includes('"relPath":"photos/101.jpg"')).assertTrue();
      expect(json.includes('"bytes":2048111')).assertTrue();
      expect(json.includes('"sha256":"3b1f00e9"')).assertTrue();
    });

    it('parse_roundtrip_preserves_values', 0, () => {
      const files: ManifestFile[] = [makeFile('photos/9.jpg', 100, 'deadbeef')];
      const json = ManifestBuilder.build('RB-20260101-0010', 9, 2, 1234567890, files);
      const c = ManifestBuilder.parse(json);
      expect(c.reportNo).assertEqual('RB-20260101-0010');
      expect(c.inspectionId).assertEqual(9);
      expect(c.revisionNo).assertEqual(2);
      expect(c.files.length).assertEqual(1);
      expect(c.files[0].relPath).assertEqual('photos/9.jpg');
      expect(c.files[0].bytes).assertEqual(100);
      expect(c.files[0].sha256).assertEqual('deadbeef');
    });

    it('parse_tolerates_missing_fields', 0, () => {
      const c = ManifestBuilder.parse('{"reportNo":"RB-20260101-0001"}');
      expect(c.reportNo).assertEqual('RB-20260101-0001');
      expect(c.inspectionId).assertEqual(0);
      expect(c.files.length).assertEqual(0);
      expect(c.disclaimer).assertEqual('');
    });

    it('parse_invalid_json_throws', 0, () => {
      let thrown = false;
      try {
        ManifestBuilder.parse('not-a-json');
      } catch (err) {
        thrown = err instanceof ManifestError;
      }
      expect(thrown).assertTrue();
    });

    it('generateReportNo_pads_seq_to_four_digits', 0, () => {
      expect(ManifestBuilder.generateReportNo('20260915', 1)).assertEqual('RB-20260915-0001');
      expect(ManifestBuilder.generateReportNo('20260915', 42)).assertEqual('RB-20260915-0042');
      expect(ManifestBuilder.generateReportNo('20260915', 123)).assertEqual('RB-20260915-0123');
      expect(ManifestBuilder.generateReportNo('20260915', 9999)).assertEqual('RB-20260915-9999');
    });

    it('generateReportNo_accepts_dashed_date', 0, () => {
      expect(ManifestBuilder.generateReportNo('2026-09-15', 7)).assertEqual('RB-20260915-0007');
    });

    it('generateReportNo_seq_over_9999_not_truncated', 0, () => {
      expect(ManifestBuilder.generateReportNo('20260915', 12345)).assertEqual('RB-20260915-12345');
    });

    it('generateReportNo_rejects_non_positive_seq', 0, () => {
      let thrownZero = false;
      try {
        ManifestBuilder.generateReportNo('20260915', 0);
      } catch (err) {
        thrownZero = err instanceof ManifestError;
      }
      expect(thrownZero).assertTrue();
      let thrownNeg = false;
      try {
        ManifestBuilder.generateReportNo('20260915', -3);
      } catch (err) {
        thrownNeg = err instanceof ManifestError;
      }
      expect(thrownNeg).assertTrue();
    });

    it('generateReportNo_rejects_bad_date', 0, () => {
      let thrown = false;
      try {
        ManifestBuilder.generateReportNo('abc', 1);
      } catch (err) {
        thrown = err instanceof ManifestError;
      }
      expect(thrown).assertTrue();
    });

    it('parse_result_is_typed_manifest_content', 0, () => {
      const c: ManifestContent = ManifestBuilder.parse(
        ManifestBuilder.build('RB-20260915-0003', 3, 0, 99, [makeFile('photos/1.jpg', 5, 'ff')]));
      expect(c instanceof ManifestContent).assertTrue();
      expect(c.files[0] instanceof ManifestFile).assertTrue();
    });
  });
}
