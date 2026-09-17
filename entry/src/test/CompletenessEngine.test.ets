import { describe, it, expect } from '@ohos/hypium';
import {
  CompItem,
  CompMeter,
  CompPhoto,
  CompRoom,
  CompletenessEngine,
  CompletenessInput,
  CompletenessIssue
} from '../main/ets/domain/completeness/CompletenessEngine';
import { ItemStatus, MeterType, PhotoKind } from '../main/ets/domain/model/CoreEnums';

function makeRoom(id: number, key: string, name: string): CompRoom {
  const r = new CompRoom();
  r.id = id;
  r.templateKey = key;
  r.name = name;
  return r;
}

function makeItem(id: number, roomId: number, required: boolean, status: ItemStatus): CompItem {
  const it = new CompItem();
  it.id = id;
  it.roomId = roomId;
  it.required = required;
  it.status = status;
  return it;
}

function makePhoto(roomId: number, itemId: number, kind: PhotoKind): CompPhoto {
  const p = new CompPhoto();
  p.roomId = roomId;
  p.itemId = itemId;
  p.kind = kind;
  return p;
}

function makeMeter(meterType: string, confirmed: boolean, naFlag: boolean): CompMeter {
  const m = new CompMeter();
  m.meterType = meterType;
  m.confirmed = confirmed;
  m.naFlag = naFlag;
  return m;
}

function countRule(issues: CompletenessIssue[], ruleId: string): number {
  let n = 0;
  for (const issue of issues) {
    if (issue.ruleId === ruleId) {
      n++;
    }
  }
  return n;
}

export default function completenessEngineTest(): void {
  describe('CompletenessEngine', () => {
    it('empty_input_rates_one_no_issues', 0, () => {
      const r = CompletenessEngine.check(new CompletenessInput());
      expect(r.requiredRate).assertEqual(1);
      expect(r.suggestedRate).assertEqual(1);
      expect(r.issues.length).assertEqual(0);
    });

    it('all_pass_both_rates_one', 0, () => {
      const input = new CompletenessInput();
      input.rooms = [makeRoom(1, 'entrance', '入户门'), makeRoom(2, 'living', '客厅')];
      const i1 = makeItem(11, 1, true, ItemStatus.OK);
      const i2 = makeItem(12, 2, true, ItemStatus.ISSUE);
      i2.noteFinal = '墙面可见污渍';
      input.items = [i1, i2];
      input.meterTypes = [MeterType.WATER, MeterType.ELECTRICITY, MeterType.GAS];
      input.meters = [
        makeMeter(MeterType.WATER, true, false),
        makeMeter(MeterType.ELECTRICITY, true, false),
        makeMeter(MeterType.GAS, true, false)
      ];
      input.hasHandover = true;
      input.handoverConfirmed = true;
      input.photos = [
        makePhoto(1, 0, PhotoKind.PANORAMA),
        makePhoto(1, 11, PhotoKind.DETAIL),
        makePhoto(2, 0, PhotoKind.PANORAMA),
        makePhoto(2, 12, PhotoKind.DETAIL)
      ];
      const r = CompletenessEngine.check(input);
      expect(r.requiredRate).assertEqual(1);
      expect(r.suggestedRate).assertEqual(1);
      expect(r.issues.length).assertEqual(0);
    });

    it('r1_required_room_all_pending_fails', 0, () => {
      const input = new CompletenessInput();
      input.rooms = [makeRoom(1, 'living', '客厅')];
      input.items = [makeItem(11, 1, true, ItemStatus.PENDING), makeItem(12, 1, true, ItemStatus.PENDING)];
      const r = CompletenessEngine.check(input);
      expect(r.requiredRate).assertEqual(0);
      expect(countRule(r.issues, 'R1')).assertEqual(1);
      expect(r.issues[0].roomId).assertEqual(1);
      expect(r.issues[0].message.includes('客厅')).assertTrue();
    });

    it('r1_room_without_required_not_counted', 0, () => {
      const input = new CompletenessInput();
      input.rooms = [makeRoom(1, 'balcony', '阳台')];
      input.items = [makeItem(11, 1, false, ItemStatus.PENDING)];
      const r = CompletenessEngine.check(input);
      expect(r.requiredRate).assertEqual(1);
      expect(countRule(r.issues, 'R1')).assertEqual(0);
    });

    it('r2_meter_type_missing_fails_with_name', 0, () => {
      const input = new CompletenessInput();
      input.meterTypes = [MeterType.WATER, MeterType.GAS];
      input.meters = [makeMeter(MeterType.WATER, true, false)];
      const r = CompletenessEngine.check(input);
      expect(r.requiredRate).assertEqual(0.5);
      expect(countRule(r.issues, 'R2')).assertEqual(1);
      expect(r.issues[0].message.includes('燃气表')).assertTrue();
    });

    it('r2_na_flag_passes', 0, () => {
      const input = new CompletenessInput();
      input.meterTypes = [MeterType.GAS];
      input.meters = [makeMeter(MeterType.GAS, false, true)];
      const r = CompletenessEngine.check(input);
      expect(r.requiredRate).assertEqual(1);
      expect(countRule(r.issues, 'R2')).assertEqual(0);
    });

    it('r3_handover_unconfirmed_fails', 0, () => {
      const input = new CompletenessInput();
      input.hasHandover = true;
      input.handoverConfirmed = false;
      const r = CompletenessEngine.check(input);
      expect(r.requiredRate).assertEqual(0);
      expect(countRule(r.issues, 'R3')).assertEqual(1);
    });

    it('r3_not_counted_when_no_handover', 0, () => {
      const input = new CompletenessInput();
      input.hasHandover = false;
      input.handoverConfirmed = false;
      const r = CompletenessEngine.check(input);
      expect(r.requiredRate).assertEqual(1);
      expect(countRule(r.issues, 'R3')).assertEqual(0);
    });

    it('r4_issue_without_evidence_fails', 0, () => {
      const input = new CompletenessInput();
      input.items = [makeItem(11, 1, true, ItemStatus.ISSUE)];
      const r = CompletenessEngine.check(input);
      expect(r.requiredRate).assertEqual(0);
      expect(countRule(r.issues, 'R4')).assertEqual(1);
      expect(r.issues[0].itemId).assertEqual(11);
    });

    it('r4_waiver_passes', 0, () => {
      const input = new CompletenessInput();
      const item = makeItem(11, 1, true, ItemStatus.ISSUE);
      item.waiver = true;
      input.items = [item];
      const r = CompletenessEngine.check(input);
      expect(r.requiredRate).assertEqual(1);
      expect(countRule(r.issues, 'R4')).assertEqual(0);
    });

    it('r4_note_final_passes', 0, () => {
      const input = new CompletenessInput();
      const item = makeItem(11, 1, true, ItemStatus.ISSUE);
      item.noteFinal = '门锁松动';
      input.items = [item];
      const r = CompletenessEngine.check(input);
      expect(countRule(r.issues, 'R4')).assertEqual(0);
    });

    it('r5_room_without_panorama_fails', 0, () => {
      const input = new CompletenessInput();
      input.rooms = [makeRoom(1, 'living', '客厅')];
      input.photos = [makePhoto(1, 0, PhotoKind.DETAIL)];
      const r = CompletenessEngine.check(input);
      expect(r.suggestedRate).assertEqual(0);
      expect(countRule(r.issues, 'R5')).assertEqual(1);
    });

    it('r6_entrance_without_photo_fails', 0, () => {
      const input = new CompletenessInput();
      input.rooms = [makeRoom(1, 'entrance', '入户门'), makeRoom(2, 'living', '客厅')];
      input.photos = [makePhoto(2, 0, PhotoKind.PANORAMA)];
      const r = CompletenessEngine.check(input);
      expect(countRule(r.issues, 'R6')).assertEqual(1);
      expect(r.issues[0].roomId).assertEqual(1);
    });

    it('r6_panorama_only_does_not_count_as_closeup', 0, () => {
      // 近照判定：入户门仅有全景照不满足 R6
      const input = new CompletenessInput();
      input.rooms = [makeRoom(1, 'entrance', '入户门')];
      input.photos = [makePhoto(1, 0, PhotoKind.PANORAMA)];
      const r = CompletenessEngine.check(input);
      expect(countRule(r.issues, 'R6')).assertEqual(1);
      expect(r.issues[0].message.includes('近照')).assertTrue();
    });

    it('r6_detail_photo_satisfies_closeup', 0, () => {
      const input = new CompletenessInput();
      input.rooms = [makeRoom(1, 'entrance', '入户门')];
      input.photos = [makePhoto(1, 0, PhotoKind.DETAIL)];
      const r = CompletenessEngine.check(input);
      expect(countRule(r.issues, 'R6')).assertEqual(0);
    });

    it('r7_suggestion_not_adopted_fails', 0, () => {
      const input = new CompletenessInput();
      const item = makeItem(11, 1, true, ItemStatus.ISSUE);
      item.noteRaw = '墙很脏';
      item.noteSuggestion = '墙面存在明显污渍';
      item.noteFinal = '墙很脏';
      input.items = [item];
      const r = CompletenessEngine.check(input);
      expect(r.suggestedRate).assertEqual(0);
      expect(countRule(r.issues, 'R7')).assertEqual(1);
    });

    it('r7_adopted_suggestion_passes', 0, () => {
      const input = new CompletenessInput();
      const item = makeItem(11, 1, true, ItemStatus.ISSUE);
      item.noteRaw = '墙很脏';
      item.noteSuggestion = '墙面存在明显污渍';
      item.noteFinal = '墙面存在明显污渍';
      input.items = [item];
      const r = CompletenessEngine.check(input);
      expect(countRule(r.issues, 'R7')).assertEqual(0);
    });

    it('zero_required_denominator_rate_one', 0, () => {
      const input = new CompletenessInput();
      input.rooms = [makeRoom(1, 'custom_room', '自定义房间')];
      input.items = [makeItem(11, 1, false, ItemStatus.PENDING)];
      const r = CompletenessEngine.check(input);
      expect(r.requiredRate).assertEqual(1);
      expect(r.suggestedRate).assertEqual(0);
      expect(countRule(r.issues, 'R5')).assertEqual(1);
    });

    it('mixed_scenario_fractional_rates', 0, () => {
      const input = new CompletenessInput();
      input.rooms = [makeRoom(1, 'entrance', '入户门'), makeRoom(2, 'living', '客厅')];
      const i1 = makeItem(11, 1, true, ItemStatus.PENDING);
      const i2 = makeItem(12, 2, true, ItemStatus.ISSUE);
      const i3 = makeItem(13, 2, true, ItemStatus.OK);
      input.items = [i1, i2, i3];
      input.meterTypes = [MeterType.WATER, MeterType.ELECTRICITY, MeterType.GAS];
      input.meters = [makeMeter(MeterType.WATER, true, false), makeMeter(MeterType.ELECTRICITY, false, true)];
      input.hasHandover = true;
      input.handoverConfirmed = false;
      input.photos = [];
      const r = CompletenessEngine.check(input);
      // required 原子：R1×2（入户门失败/客厅通过）+ R2×3（燃气失败）+ R3（失败）+ R4×1（i2 失败）= 7，通过 3
      expect(r.requiredRate).assertEqual(3 / 7);
      // suggested 原子：R5×2（均失败）+ R6（失败）+ R7×1（建议为空通过）= 4，通过 1
      expect(r.suggestedRate).assertEqual(0.25);
      // 必须级遗漏 4（R1×1+R2×1+R3×1+R4×1）+ 建议级遗漏 3（R5×2+R6×1）= 7
      expect(r.issues.length).assertEqual(7);
      expect(CompletenessEngine.isRequiredRule('R4')).assertTrue();
      expect(CompletenessEngine.isRequiredRule('R5')).assertFalse();
    });
  });
}
