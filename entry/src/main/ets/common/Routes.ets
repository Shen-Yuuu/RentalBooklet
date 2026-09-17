/**
 * Navigation 路由名常量。
 * 约束：必须与 resources/base/profile/route_map.json 中的 name 保持一致。
 */
export class Routes {
  static readonly SCENE_SELECT: string = 'sceneSelect';
  static readonly HOUSE_EDIT: string = 'houseEdit';
  static readonly HOUSE_DETAIL: string = 'houseDetail';
  static readonly INSPECTION: string = 'inspection';
  static readonly METER_OCR: string = 'meterOcr';
  static readonly REVIEW: string = 'review';
  static readonly CONFIRM_SIGN: string = 'confirmSign';
  static readonly REPORT_PREVIEW: string = 'reportPreview';
  static readonly ARCHIVE_DETAIL: string = 'archiveDetail';
  static readonly COMPARE: string = 'compare';
}
