import { ItemEntity, RoomEntity } from '../model/Entities';

/**
 * 前后对比对齐器（产品文档 §5.6 / 链路 L11，纯函数，零 Kit 依赖）。
 * 按 (room.templateKey, item.templateKey) 复合键配对基线（入住）与当前（退租）检查项：
 * - 当前项找不到基线项 → newItem=true（"新增项"）；
 * - 基线项未被任何当前项匹配 → baselineOnly（"基线独有（本次未包含）"）；
 * - 输入乱序时先按 sort 归一化，输出顺序稳定（房间 sort → 项目 sort）。
 * 措辞红线：本模块只做结构对齐，不产生任何成因/责任判断。
 */

/** 一对配对结果：当前项为主，baselineItemId=0 表示基线无此项（新增项）。 */
export class ComparePair {
  roomId: number = 0;
  roomName: string = '';
  itemId: number = 0;
  itemName: string = '';
  baselineItemId: number = 0;
  baselineNote: string = '';
  baselineStatus: string = '';
  newItem: boolean = false;
}

/** 基线独有项（本次检查未包含）。 */
export class BaselineOnlyItem {
  roomName: string = '';
  itemName: string = '';
}

/** 对齐产物：配对列表 + 基线独有列表。 */
export class CompareAlignment {
  pairs: ComparePair[] = [];
  baselineOnly: BaselineOnlyItem[] = [];
}

export class CompareAligner {
  /**
   * 对齐两组聚合的房间/检查项。
   * @param baselineRooms 基线（入住）房间列表（顺序不限）
   * @param baselineItemsByRoom 基线 roomId → 检查项列表
   * @param currentRooms 当前（退租）房间列表（顺序不限）
   * @param currentItemsByRoom 当前 roomId → 检查项列表
   */
  static align(baselineRooms: RoomEntity[], baselineItemsByRoom: Map<number, ItemEntity[]>,
    currentRooms: RoomEntity[], currentItemsByRoom: Map<number, ItemEntity[]>): CompareAlignment {
    const out = new CompareAlignment();
    const bRooms = CompareAligner.sortedRooms(baselineRooms);
    const cRooms = CompareAligner.sortedRooms(currentRooms);

    // 基线索引：'roomKey/itemKey' → 基线检查项（同名项在不同房间不会误配）
    const index = new Map<string, ItemEntity>();
    for (const room of bRooms) {
      const items = CompareAligner.sortedItems(baselineItemsByRoom.get(room.id));
      for (const item of items) {
        index.set(`${room.templateKey}/${item.templateKey}`, item);
      }
    }

    const matchedBaselineIds = new Set<number>();
    for (const room of cRooms) {
      const items = CompareAligner.sortedItems(currentItemsByRoom.get(room.id));
      for (const item of items) {
        const pair = new ComparePair();
        pair.roomId = room.id;
        pair.roomName = room.name;
        pair.itemId = item.id;
        pair.itemName = item.name;
        const base = index.get(`${room.templateKey}/${item.templateKey}`);
        if (base !== undefined) {
          pair.baselineItemId = base.id;
          pair.baselineNote = base.noteFinal.length > 0 ? base.noteFinal : base.noteRaw;
          pair.baselineStatus = base.status;
          matchedBaselineIds.add(base.id);
        } else {
          pair.newItem = true;
        }
        out.pairs.push(pair);
      }
    }

    for (const room of bRooms) {
      const items = CompareAligner.sortedItems(baselineItemsByRoom.get(room.id));
      for (const item of items) {
        if (!matchedBaselineIds.has(item.id)) {
          const only = new BaselineOnlyItem();
          only.roomName = room.name;
          only.itemName = item.name;
          out.baselineOnly.push(only);
        }
      }
    }
    return out;
  }

  private static sortedRooms(rooms: RoomEntity[]): RoomEntity[] {
    const copy: RoomEntity[] = [...rooms];
    copy.sort((a: RoomEntity, b: RoomEntity) => (a.sort - b.sort) || (a.id - b.id));
    return copy;
  }

  private static sortedItems(items: ItemEntity[] | undefined): ItemEntity[] {
    if (items === undefined) {
      return [];
    }
    const copy: ItemEntity[] = [...items];
    copy.sort((a: ItemEntity, b: ItemEntity) => (a.sort - b.sort) || (a.id - b.id));
    return copy;
  }
}
