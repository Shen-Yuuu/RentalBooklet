import { describe, it, expect } from '@ohos/hypium';
import {
  BaselineOnlyItem, CompareAligner, CompareAlignment, ComparePair
} from '../main/ets/domain/compare/CompareAligner';
import { ItemEntity, RoomEntity } from '../main/ets/domain/model/Entities';
import { ItemStatus } from '../main/ets/domain/model/CoreEnums';

function mkRoom(id: number, key: string, name: string, sort: number): RoomEntity {
  const r = new RoomEntity();
  r.id = id;
  r.templateKey = key;
  r.name = name;
  r.sort = sort;
  return r;
}

function mkItem(id: number, roomId: number, key: string, name: string, sort: number,
  status: ItemStatus = ItemStatus.OK, noteFinal: string = '', noteRaw: string = ''): ItemEntity {
  const it = new ItemEntity();
  it.id = id;
  it.roomId = roomId;
  it.templateKey = key;
  it.name = name;
  it.sort = sort;
  it.status = status;
  it.noteFinal = noteFinal;
  it.noteRaw = noteRaw;
  return it;
}

function itemMap(items: ItemEntity[]): Map<number, ItemEntity[]> {
  const m = new Map<number, ItemEntity[]>();
  for (const it of items) {
    const list = m.get(it.roomId);
    if (list === undefined) {
      m.set(it.roomId, [it]);
    } else {
      list.push(it);
    }
  }
  return m;
}

/** 配对序列签名（乱序稳定性断言用）。 */
function pairSignatures(a: CompareAlignment): string[] {
  const keys: string[] = [];
  for (const p of a.pairs) {
    keys.push(`${p.roomName}/${p.itemName}/${p.newItem ? 'new' : `${p.baselineItemId}`}/${p.baselineStatus}/${p.baselineNote}`);
  }
  return keys;
}

function onlySignatures(a: CompareAlignment): string[] {
  const keys: string[] = [];
  for (const o of a.baselineOnly) {
    keys.push(`${o.roomName}/${o.itemName}`);
  }
  return keys;
}

export default function compareAlignerTest(): void {
  describe('CompareAligner', () => {
    // 基线：客厅（墙面/沙发）+ 主卧（窗户）
    it('all_aligned_pairs_match_and_copy_baseline_info', 0, () => {
      const bRooms = [mkRoom(1, 'living', '客厅', 0), mkRoom(2, 'master', '主卧', 1)];
      const bItems = [
        mkItem(11, 1, 'wall', '墙面', 0, ItemStatus.OK, '入住时墙面完好'),
        mkItem(12, 1, 'sofa', '沙发', 1, ItemStatus.ISSUE, '扶手有旧划痕'),
        mkItem(13, 2, 'window', '窗户', 0, ItemStatus.OK)
      ];
      const cRooms = [mkRoom(101, 'living', '客厅', 0), mkRoom(102, 'master', '主卧', 1)];
      const cItems = [
        mkItem(111, 101, 'wall', '墙面', 0),
        mkItem(112, 101, 'sofa', '沙发', 1),
        mkItem(113, 102, 'window', '窗户', 0)
      ];
      const a = CompareAligner.align(bRooms, itemMap(bItems), cRooms, itemMap(cItems));
      expect(a.pairs.length).assertEqual(3);
      expect(a.baselineOnly.length).assertEqual(0);
      for (const p of a.pairs) {
        expect(p.newItem).assertFalse();
      }
      const wall: ComparePair = a.pairs[0];
      expect(wall.roomName).assertEqual('客厅');
      expect(wall.itemName).assertEqual('墙面');
      expect(wall.itemId).assertEqual(111);
      expect(wall.baselineItemId).assertEqual(11);
      expect(wall.baselineStatus === ItemStatus.OK).assertTrue();
      expect(wall.baselineNote).assertEqual('入住时墙面完好');
      const sofa: ComparePair = a.pairs[1];
      expect(sofa.baselineItemId).assertEqual(12);
      expect(sofa.baselineStatus === ItemStatus.ISSUE).assertTrue();
    });

    it('current_extra_item_marked_new', 0, () => {
      const bRooms = [mkRoom(1, 'living', '客厅', 0)];
      const bItems = [mkItem(11, 1, 'wall', '墙面', 0)];
      const cRooms = [mkRoom(101, 'living', '客厅', 0)];
      const cItems = [mkItem(111, 101, 'wall', '墙面', 0), mkItem(112, 101, 'tv', '电视', 1)];
      const a = CompareAligner.align(bRooms, itemMap(bItems), cRooms, itemMap(cItems));
      expect(a.pairs.length).assertEqual(2);
      expect(a.pairs[1].newItem).assertTrue();
      expect(a.pairs[1].baselineItemId).assertEqual(0);
      expect(a.pairs[0].newItem).assertFalse();
      expect(a.baselineOnly.length).assertEqual(0);
    });

    it('baseline_only_items_listed_separately', 0, () => {
      const bRooms = [mkRoom(1, 'living', '客厅', 0)];
      const bItems = [mkItem(11, 1, 'wall', '墙面', 0), mkItem(12, 1, 'floor', '地板', 1)];
      const cRooms = [mkRoom(101, 'living', '客厅', 0)];
      const cItems = [mkItem(111, 101, 'wall', '墙面', 0)];
      const a = CompareAligner.align(bRooms, itemMap(bItems), cRooms, itemMap(cItems));
      expect(a.pairs.length).assertEqual(1);
      expect(a.baselineOnly.length).assertEqual(1);
      const only: BaselineOnlyItem = a.baselineOnly[0];
      expect(only.roomName).assertEqual('客厅');
      expect(only.itemName).assertEqual('地板');
    });

    it('same_item_key_in_different_rooms_not_mismatched', 0, () => {
      // 客厅与主卧都有 wall：必须各自配对，不串房间
      const bRooms = [mkRoom(1, 'living', '客厅', 0), mkRoom(2, 'master', '主卧', 1)];
      const bItems = [mkItem(11, 1, 'wall', '墙面', 0), mkItem(12, 2, 'wall', '墙面', 0)];
      const cRooms = [mkRoom(101, 'living', '客厅', 0), mkRoom(102, 'master', '主卧', 1)];
      const cItems = [mkItem(111, 101, 'wall', '墙面', 0), mkItem(112, 102, 'wall', '墙面', 0)];
      const a = CompareAligner.align(bRooms, itemMap(bItems), cRooms, itemMap(cItems));
      expect(a.pairs.length).assertEqual(2);
      expect(a.pairs[0].baselineItemId).assertEqual(11);
      expect(a.pairs[1].baselineItemId).assertEqual(12);
      expect(a.baselineOnly.length).assertEqual(0);

      // 反例：基线 wall 只在主卧、当前 wall 只在客厅 → 不得跨房配对，应为新增项 + 基线独有
      const b2Rooms = [mkRoom(2, 'master', '主卧', 0)];
      const b2Items = [mkItem(12, 2, 'wall', '墙面', 0)];
      const c2Rooms = [mkRoom(101, 'living', '客厅', 0)];
      const c2Items = [mkItem(111, 101, 'wall', '墙面', 0)];
      const a2 = CompareAligner.align(b2Rooms, itemMap(b2Items), c2Rooms, itemMap(c2Items));
      expect(a2.pairs.length).assertEqual(1);
      expect(a2.pairs[0].newItem).assertTrue();
      expect(a2.baselineOnly.length).assertEqual(1);
      expect(onlySignatures(a2)[0]).assertEqual('主卧/墙面');
    });

    it('shuffled_input_produces_stable_output', 0, () => {
      const bRooms = [mkRoom(1, 'living', '客厅', 0), mkRoom(2, 'master', '主卧', 1), mkRoom(3, 'kitchen', '厨房', 2)];
      const bItems = [
        mkItem(11, 1, 'wall', '墙面', 0, ItemStatus.OK, '备注A'),
        mkItem(12, 1, 'sofa', '沙发', 1),
        mkItem(13, 2, 'window', '窗户', 0),
        mkItem(14, 2, 'bed', '床', 1),
        mkItem(15, 3, 'stove', '灶台', 0)
      ];
      const cRooms = [mkRoom(101, 'living', '客厅', 0), mkRoom(102, 'master', '主卧', 1), mkRoom(103, 'kitchen', '厨房', 2)];
      const cItems = [
        mkItem(111, 101, 'wall', '墙面', 0),
        mkItem(112, 101, 'sofa', '沙发', 1),
        mkItem(113, 102, 'window', '窗户', 0),
        mkItem(114, 102, 'bed', '床', 1),
        mkItem(115, 103, 'stove', '灶台', 0)
      ];
      const normal = CompareAligner.align(bRooms, itemMap(bItems), cRooms, itemMap(cItems));

      // 乱序副本：房间/项目数组反转（sort 值不变）
      const shuffledBRooms = [bRooms[2], bRooms[0], bRooms[1]];
      const shuffledBItems = [bItems[4], bItems[1], bItems[3], bItems[0], bItems[2]];
      const shuffledCRooms = [cRooms[1], cRooms[2], cRooms[0]];
      const shuffledCItems = [cItems[3], cItems[4], cItems[1], cItems[0], cItems[2]];
      const shuffled = CompareAligner.align(shuffledBRooms, itemMap(shuffledBItems),
        shuffledCRooms, itemMap(shuffledCItems));

      const normalKeys = pairSignatures(normal);
      const shuffledKeys = pairSignatures(shuffled);
      expect(normalKeys.length).assertEqual(5);
      expect(shuffledKeys.length).assertEqual(5);
      for (let i = 0; i < normalKeys.length; i++) {
        expect(shuffledKeys[i]).assertEqual(normalKeys[i]);
      }
    });

    it('empty_inputs_produce_empty_alignment', 0, () => {
      const a = CompareAligner.align([], new Map<number, ItemEntity[]>(), [], new Map<number, ItemEntity[]>());
      expect(a.pairs.length).assertEqual(0);
      expect(a.baselineOnly.length).assertEqual(0);
    });

    it('empty_baseline_marks_all_current_items_new', 0, () => {
      const cRooms = [mkRoom(101, 'living', '客厅', 0)];
      const cItems = [mkItem(111, 101, 'wall', '墙面', 0)];
      const a = CompareAligner.align([], new Map<number, ItemEntity[]>(), cRooms, itemMap(cItems));
      expect(a.pairs.length).assertEqual(1);
      expect(a.pairs[0].newItem).assertTrue();
      expect(a.baselineOnly.length).assertEqual(0);
    });

    it('baseline_note_falls_back_to_raw_when_final_empty', 0, () => {
      const bRooms = [mkRoom(1, 'living', '客厅', 0)];
      const bItems = [mkItem(11, 1, 'wall', '墙面', 0, ItemStatus.OK, '', '原始备注')];
      const cRooms = [mkRoom(101, 'living', '客厅', 0)];
      const cItems = [mkItem(111, 101, 'wall', '墙面', 0)];
      const a = CompareAligner.align(bRooms, itemMap(bItems), cRooms, itemMap(cItems));
      expect(a.pairs[0].baselineNote).assertEqual('原始备注');
    });
  });
}
