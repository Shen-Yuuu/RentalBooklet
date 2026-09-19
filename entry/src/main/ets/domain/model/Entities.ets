import { InspectionStatus, ItemStatus, PhotoKind, PhotoSource } from './CoreEnums';
import { GuideType } from './TemplateModels';

export class House {
  id: number = 0;
  name: string = '';
  fullAddress: string = '';
  layout: string = '';
  landlordName: string = '';
  landlordPhone: string = '';
  tenantName: string = '';
  tenantPhone: string = '';
  leaseEndDate: number = 0;
  recordLocation: boolean = false;
  createdAt: number = 0;
  updatedAt: number = 0;
}

export class Inspection {
  id: number = 0;
  houseId: number = 0;
  sceneKey: string = '';
  status: InspectionStatus = InspectionStatus.DRAFT;
  baselineInspectionId: number = 0;
  parentRevisionId: number = 0;
  revisionNo: number = 0;
  reportNo: string = '';
  startedAt: number = 0;
  frozenAt: number = 0;
  participants: string = '';
  extraNote: string = '';
  completeRequired: number = 0;
  completeSuggested: number = 0;
  pdfSha256: string = '';
}

export class RoomEntity {
  id: number = 0;
  inspectionId: number = 0;
  templateKey: string = '';
  name: string = '';
  sort: number = 0;
}

export class ItemEntity {
  id: number = 0;
  roomId: number = 0;
  templateKey: string = '';
  name: string = '';
  sort: number = 0;
  required: boolean = true;
  guide: GuideType = GuideType.NONE;
  status: ItemStatus = ItemStatus.PENDING;
  noteRaw: string = '';
  noteSuggestion: string = '';
  noteFinal: string = '';
  waiver: boolean = false;
  waiverReason: string = '';
  updatedAt: number = 0;
}

export class PhotoEntity {
  id: number = 0;
  inspectionId: number = 0;
  roomId: number = 0;
  itemId: number = 0;
  kind: PhotoKind = PhotoKind.DETAIL;
  source: PhotoSource = PhotoSource.CAPTURED;
  path: string = '';
  thumbPath: string = '';
  width: number = 0;
  height: number = 0;
  shotAt: number = 0;
  location: string = '';
  qualityFlags: string = '';
  note: string = '';
  sha256: string = '';
}

/** 检查聚合：执行页一次加载的完整数据。 */
export class InspectionAggregate {
  inspection: Inspection = new Inspection();
  house: House = new House();
  rooms: RoomEntity[] = [];
  itemsByRoom: Map<number, ItemEntity[]> = new Map();
}

/** 列表行：检查记录 + 进度快照。 */
export class InspectionSummary {
  inspection: Inspection = new Inspection();
  totalItems: number = 0;
  doneItems: number = 0;
}

/** 记录 Tab 列表行：跨房屋的检查记录摘要（JOIN house）。 */
export class RecordSummary {
  inspectionId: number = 0;
  houseName: string = '';
  sceneKey: string = '';
  status: InspectionStatus = InspectionStatus.DRAFT;
  reportNo: string = '';
  revisionNo: number = 0;
  /** 前后对比基线（入住检查 id），0 = 未设置。 */
  baselineInspectionId: number = 0;
  startedAt: number = 0;
  frozenAt: number = 0;
  totalItems: number = 0;
  doneItems: number = 0;
  /** 全文检索文本：该记录全部检查项名称与备注拼接（产品文档 §5.4 可搜索承诺）。 */
  itemText: string = '';
}

/** 前后对比已确认汇总（compare_result 计算，E2 汇总条/E3 挂接用）。 */
export class CompareSummary {
  /** 已标记三态结果的检查项数。 */
  total: number = 0;
  /** 其中标记"有变化"的项数。 */
  changed: number = 0;
}

/** 表读数记录（meter_reading 表视图，表读数确认页与完整性 R2 使用）。 */
export class MeterReadingEntity {
  id: number = 0;
  inspectionId: number = 0;
  meterType: string = '';
  valueText: string = '';
  confirmed: boolean = false;
  naFlag: boolean = false;
  unit: string = '';
  /** OCR 原文（候选行拼接），未识别时为空串。 */
  ocrRawText: string = '';
  /** OCR 置信度：当前 textRecognition API 不返回置信度，恒为 0（库中为 NULL）。 */
  ocrConf: number = 0;
  /** 关联的表盘照片（photo 表 id），0 表示未关联。 */
  photoId: number = 0;
  note: string = '';
}

/**
 * 钥匙门禁交接记录（handover 表视图，交接登记与完整性 R3 使用）。
 * "无需记录"语义：confirmed=1 且 note=NO_NEED_NOTE（不引入魔法计数值）。
 */
export class HandoverEntity {
  /** "无需记录"的备注约定值：R3 通过条件是 confirmed==true，无需记录即确认 + 该备注。 */
  static readonly NO_NEED_NOTE: string = '无需记录';

  inspectionId: number = 0;
  keyCount: number = 0;
  accessCardCount: number = 0;
  confirmed: boolean = false;
  parkingOrStorage: string = '';
  note: string = '';

  isNoNeed(): boolean {
    return this.note === HandoverEntity.NO_NEED_NOTE;
  }
}
