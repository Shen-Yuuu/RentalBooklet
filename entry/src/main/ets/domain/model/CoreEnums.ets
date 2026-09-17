export enum SceneKey {
  MOVE_IN = 'move_in',
  MOVE_OUT = 'move_out',
  REPAIR = 'repair',
  CLEANING = 'cleaning',
  APPLIANCE = 'appliance',
  CUSTOM = 'custom'
}

export enum MeterType {
  WATER = 'WATER',
  ELECTRICITY = 'ELECTRICITY',
  GAS = 'GAS'
}

export enum ItemStatus {
  PENDING = 'PENDING',
  OK = 'OK',
  ISSUE = 'ISSUE',
  NA = 'NA'
}

export enum InspectionStatus {
  DRAFT = 'DRAFT',
  FROZEN = 'FROZEN'
}

export enum PhotoKind {
  PANORAMA = 'PANORAMA',
  DETAIL = 'DETAIL',
  METER = 'METER',
  SIGN = 'SIGN',
  DOC = 'DOC'
}

export enum PhotoSource {
  CAPTURED = 'CAPTURED',
  IMPORTED = 'IMPORTED'
}

/** 前后对比三态确认（产品文档 §5.6）：App 只呈现与记录，不归因。 */
export enum CompareResult {
  UNCHANGED = 'UNCHANGED',
  CHANGED = 'CHANGED',
  PENDING = 'PENDING'
}
