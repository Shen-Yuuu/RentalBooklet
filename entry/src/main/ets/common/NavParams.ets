/** Navigation 路由参数。约束：与页面 onReady 中的解析保持一致。 */
export interface SceneSelectParam {
  houseId?: number;
}

export interface InspectionParam {
  inspectionId: number;
  /** 可选：完整度页跳转回执行页时定位的房间 id。 */
  focusRoomId?: number;
}

export interface HouseDetailParam {
  houseId: number;
}

/** 场景选择后进入的检查准备参数：sceneKey 必填；houseId>0 时为档案编辑模式（仅保存档案，不发起检查）。 */
export interface HousePrepareParam {
  sceneKey: string;
  houseId?: number;
}

/** 记录完整度页参数。 */
export interface ReviewParam {
  inspectionId: number;
}

/** 表读数确认页参数：meterType 取 MeterType 枚举值（WATER/ELECTRICITY/GAS 字符串）。 */
export interface MeterOcrParam {
  inspectionId: number;
  meterType: string;
}

/** 确认冻结页参数。 */
export interface ConfirmSignParam {
  inspectionId: number;
}

/** 报告预览页参数。 */
export interface ReportPreviewParam {
  inspectionId: number;
}

/** 前后对比页参数：inspectionId 为退租检查 id（E2）。 */
export interface CompareParam {
  inspectionId: number;
}
