import { ItemStatus, MeterType, PhotoKind } from '../model/CoreEnums';

/**
 * 完整性引擎输入/输出模型（产品文档 §5.2 规则 R1~R7）。
 * 纯 TS：文件顶部零 @ohos/@kit import，可被本地单测直接覆盖。
 */

/** 房间最小快照：完整度只关心 id/模板键/名称。 */
export class CompRoom {
  id: number = 0;
  templateKey: string = '';
  name: string = '';
}

/** 检查项最小快照。 */
export class CompItem {
  id: number = 0;
  roomId: number = 0;
  required: boolean = true;
  status: ItemStatus = ItemStatus.PENDING;
  noteRaw: string = '';
  noteFinal: string = '';
  noteSuggestion: string = '';
  waiver: boolean = false;
}

/** 表读数最小快照：confirmed=已确认读数；naFlag=无表具/无法读取。 */
export class CompMeter {
  meterType: string = '';
  confirmed: boolean = false;
  naFlag: boolean = false;
}

/** 照片最小快照：仅保留规则所需的归属关系与类型。 */
export class CompPhoto {
  itemId: number = 0;
  roomId: number = 0;
  kind: PhotoKind = PhotoKind.DETAIL;
}

/** 完整性检查输入：由页面层从各仓库聚合后拼装。 */
export class CompletenessInput {
  rooms: CompRoom[] = [];
  items: CompItem[] = [];
  meterTypes: string[] = [];
  meters: CompMeter[] = [];
  hasHandover: boolean = false;
  handoverConfirmed: boolean = false;
  photos: CompPhoto[] = [];
}

/** 单条遗漏：ruleId 定位规则与级别，roomId/itemId 供页面跳转与豁免。 */
export class CompletenessIssue {
  ruleId: string = '';
  roomId: number = 0;
  itemId: number = 0;
  message: string = '';
  /** R2 专属：缺登记的表类型（MeterType 枚举值），供完整度页直达表读数确认页。 */
  meterType: string = '';
}

/** 完整性检查结果：完成率为 0~1 的小数，无计数单位时为 1。 */
export class CompletenessResult {
  requiredRate: number = 1;
  suggestedRate: number = 1;
  issues: CompletenessIssue[] = [];
}

/**
 * 完整性规则引擎（R1~R7，产品文档 §5.2）。
 * 措辞约束：message 仅描述"缺什么"，不判断责任、不提证据效力。
 * 原子单位：requiredRate = R1逐房间 + R2逐表 + R3(有交接时1个) + R4逐ISSUE项；
 *          suggestedRate = R5逐房间 + R6(存在入户门时1个) + R7逐ISSUE项。
 * 分母为 0 时该 rate = 1。
 */
export class CompletenessEngine {
  static isRequiredRule(ruleId: string): boolean {
    return ruleId === 'R1' || ruleId === 'R2' || ruleId === 'R3' || ruleId === 'R4';
  }

  static check(input: CompletenessInput): CompletenessResult {
    const issues: CompletenessIssue[] = [];
    let requiredTotal: number = 0;
    let requiredPassed: number = 0;
    let suggestedTotal: number = 0;
    let suggestedPassed: number = 0;

    const itemsByRoom = new Map<number, CompItem[]>();
    for (const item of input.items) {
      const list = itemsByRoom.get(item.roomId);
      if (list === undefined) {
        itemsByRoom.set(item.roomId, [item]);
      } else {
        list.push(item);
      }
    }
    const photoItemIds = new Set<number>();
    const panoramaRoomIds = new Set<number>();
    const closeupRoomIds = new Set<number>();
    for (const p of input.photos) {
      if (p.itemId > 0) {
        photoItemIds.add(p.itemId);
      }
      if (p.roomId > 0) {
        if (p.kind === PhotoKind.PANORAMA) {
          panoramaRoomIds.add(p.roomId);
        } else {
          // 近照（非全景）：R6 判定口径，全景照不算近照
          closeupRoomIds.add(p.roomId);
        }
      }
    }

    // R1（必须）：每个含必查项的房间，至少 1 个检查项被处理（非 PENDING）。
    for (const room of input.rooms) {
      const list = itemsByRoom.get(room.id);
      let hasRequired = false;
      let anyProcessed = false;
      if (list !== undefined) {
        for (const item of list) {
          if (item.required) {
            hasRequired = true;
          }
          if (item.status !== ItemStatus.PENDING) {
            anyProcessed = true;
          }
        }
      }
      if (!hasRequired) {
        continue;
      }
      requiredTotal++;
      if (anyProcessed) {
        requiredPassed++;
      } else {
        const issue = new CompletenessIssue();
        issue.ruleId = 'R1';
        issue.roomId = room.id;
        issue.message = `「${room.name}」还没有检查项被处理`;
        issues.push(issue);
      }
    }

    // R2（必须）：每类表读数已确认，或标记无表具/无法读取。
    for (const mt of input.meterTypes) {
      requiredTotal++;
      let ok = false;
      for (const m of input.meters) {
        if (m.meterType === mt && (m.confirmed || m.naFlag)) {
          ok = true;
          break;
        }
      }
      if (ok) {
        requiredPassed++;
      } else {
        const issue = new CompletenessIssue();
        issue.ruleId = 'R2';
        issue.roomId = CompletenessEngine.roomIdOfKey(input.rooms, 'meters');
        issue.meterType = mt;
        issue.message = `「${CompletenessEngine.meterDisplayName(mt)}」读数尚未确认，可确认读数或标记无表具`;
        issues.push(issue);
      }
    }

    // R3（必须）：模板含交接时，钥匙与门禁需已确认。
    if (input.hasHandover) {
      requiredTotal++;
      if (input.handoverConfirmed) {
        requiredPassed++;
      } else {
        const issue = new CompletenessIssue();
        issue.ruleId = 'R3';
        issue.roomId = CompletenessEngine.roomIdOfKey(input.rooms, 'handover');
        issue.message = '钥匙与门禁交接尚未确认';
        issues.push(issue);
      }
    }

    // R4（必须）：每个存在问题项需有照片、备注，或勾选"说明原因通过"。
    for (const item of input.items) {
      if (item.status !== ItemStatus.ISSUE) {
        continue;
      }
      requiredTotal++;
      if (photoItemIds.has(item.id) || item.noteFinal.length > 0 || item.waiver) {
        requiredPassed++;
      } else {
        const issue = new CompletenessIssue();
        issue.ruleId = 'R4';
        issue.roomId = item.roomId;
        issue.itemId = item.id;
        issue.message = '该项标记为存在问题，还缺少照片或备注（可说明原因通过）';
        issues.push(issue);
      }
    }

    // R5（建议）：每个房间至少 1 张全景照。
    for (const room of input.rooms) {
      suggestedTotal++;
      if (panoramaRoomIds.has(room.id)) {
        suggestedPassed++;
      } else {
        const issue = new CompletenessIssue();
        issue.ruleId = 'R5';
        issue.roomId = room.id;
        issue.message = `「${room.name}」还没有全景照`;
        issues.push(issue);
      }
    }

    // R6（建议）：入户门房间至少 1 张近照（非全景）。
    const entranceRoomId = CompletenessEngine.roomIdOfKey(input.rooms, 'entrance');
    if (entranceRoomId > 0) {
      suggestedTotal++;
      if (closeupRoomIds.has(entranceRoomId)) {
        suggestedPassed++;
      } else {
        const issue = new CompletenessIssue();
        issue.ruleId = 'R6';
        issue.roomId = entranceRoomId;
        issue.message = '入户门还没有近照（细节照）';
        issues.push(issue);
      }
    }

    // R7（建议）：存在问题项的备注建议被采纳（建议为空视为通过）。
    for (const item of input.items) {
      if (item.status !== ItemStatus.ISSUE) {
        continue;
      }
      suggestedTotal++;
      if (item.noteSuggestion.length === 0 || item.noteFinal !== item.noteRaw) {
        suggestedPassed++;
      } else {
        const issue = new CompletenessIssue();
        issue.ruleId = 'R7';
        issue.roomId = item.roomId;
        issue.itemId = item.id;
        issue.message = '存在问题项的备注未采纳中性化建议（可选）';
        issues.push(issue);
      }
    }

    const result = new CompletenessResult();
    result.requiredRate = requiredTotal === 0 ? 1 : requiredPassed / requiredTotal;
    result.suggestedRate = suggestedTotal === 0 ? 1 : suggestedPassed / suggestedTotal;
    result.issues = issues;
    return result;
  }

  private static roomIdOfKey(rooms: CompRoom[], key: string): number {
    for (const room of rooms) {
      if (room.templateKey === key) {
        return room.id;
      }
    }
    return 0;
  }

  private static meterDisplayName(meterType: string): string {
    switch (meterType) {
      case MeterType.WATER:
        return '水表';
      case MeterType.ELECTRICITY:
        return '电表';
      case MeterType.GAS:
        return '燃气表';
      default:
        return meterType;
    }
  }
}
