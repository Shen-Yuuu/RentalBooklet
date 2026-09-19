import { describe, it, expect } from '@ohos/hypium';
import { TextRefiner } from '../main/ets/domain/refine/TextRefiner';

export default function textRefinerTest(): void {
  describe('TextRefiner', () => {
    it('subjective_word_replaced', 0, () => {
      const r = TextRefiner.refine('客厅很脏');
      expect(r.refined).assertEqual('客厅存在明显污渍');
      expect(r.changes.length).assertEqual(1);
    });

    it('crack_word_normalized', 0, () => {
      const r = TextRefiner.refine('窗户裂了');
      expect(r.refined).assertEqual('窗户可见裂纹');
    });

    it('cn_quantity_converted', 0, () => {
      const r = TextRefiner.refine('裂缝十厘米左右');
      expect(r.refined).assertEqual('裂缝约10厘米');
    });

    it('approx_word_normalized', 0, () => {
      const r = TextRefiner.refine('裂缝10厘米 上下');
      expect(r.refined).assertEqual('裂缝约10厘米');
    });

    it('attribution_marked_as_hearsay', 0, () => {
      const r = TextRefiner.refine('房东说墙是新刷的');
      expect(r.refined).assertEqual('据对方表述，墙是新刷的');
    });

    it('attribution_request_keeps_imperative', 0, () => {
      // 归因剥离不得吞掉祈使语义：要求/让 → "对方要求"
      const r = TextRefiner.refine('房东要求维修空调');
      expect(r.refined).assertEqual('对方要求维修空调');
      const r2 = TextRefiner.refine('物业让换锁');
      expect(r2.refined).assertEqual('对方要求换锁');
    });

    it('self_blame_removed', 0, () => {
      const r = TextRefiner.refine('冰箱门凹陷，是我弄坏的');
      expect(r.refined).assertEqual('冰箱门凹陷，成因未确认');
    });

    it('mixed_sentence_full_pipeline', 0, () => {
      // §5.7 示例前半句：句式建议改写为"位置+对象+现象+尺寸"
      const r = TextRefiner.refine('主卧窗户左下角有一条十厘米左右的裂缝');
      expect(r.refined).assertEqual('主卧窗户左下角可见线状裂纹，长度约 10 厘米');
      expect(r.changes.length >= 1).assertTrue();
    });

    it('doc_example_sentence_with_existed_note', 0, () => {
      // §5.7 完整示例："…有一条十厘米左右的裂缝，入住时已经存在" → "…可见线状裂纹，长度约 10 厘米（入住时已存在）"
      const r = TextRefiner.refine('主卧窗户左下角有一条十厘米左右的裂缝，入住时已经存在');
      expect(r.refined).assertEqual('主卧窗户左下角可见线状裂纹，长度约 10 厘米（入住时已存在）');
    });

    it('ambiguous_quantity_does_not_block_later_conversion', 0, () => {
      // 位置切片替换回归：跳过的歧义量词（两三米）不得被后续同串替换误伤
      const r = TextRefiner.refine('墙裙两三米，踢脚线三米');
      expect(r.refined).assertEqual('墙裙两三米，踢脚线约3米');
      expect(r.changes.length).assertEqual(1);
      expect(r.changes[0].before).assertEqual('三米');
      expect(r.changes[0].after).assertEqual('约3米');
    });

    it('bare_cn_quantity_gets_approx_marker', 0, () => {
      // 裸口语数量（无"左右"）同为回忆近似值，统一加"约"（§5.7 口径）
      const r = TextRefiner.refine('窗缝十厘米');
      expect(r.refined).assertEqual('窗缝约10厘米');
    });

    it('multiple_matches_all_recorded', 0, () => {
      const r = TextRefiner.refine('客厅很脏，家具特别旧');
      expect(r.refined).assertEqual('客厅存在明显污渍，家具陈旧');
      expect(r.changes.length).assertEqual(2);
    });

    it('clean_text_unchanged', 0, () => {
      const r = TextRefiner.refine('主卧窗户左下角可见线状裂纹，长度约10厘米');
      expect(r.refined).assertEqual('主卧窗户左下角可见线状裂纹，长度约10厘米');
      expect(r.changes.length).assertEqual(0);
    });

    it('ambiguous_cn_quantity_left_alone', 0, () => {
      const r = TextRefiner.refine('两三米的地板');
      expect(r.refined).assertEqual('两三米的地板');
    });
  });
}
