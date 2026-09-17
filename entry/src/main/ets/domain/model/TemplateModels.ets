import { MeterType } from './CoreEnums';

/** 拍摄取景引导类型：DIAL=表盘读数引导框。 */
export enum GuideType {
  NONE = 'none',
  DIAL = 'dial'
}

/** 模板检查项（JSON/内置常量形态，required/guide 可省略，由引擎归一化）。 */
export interface ItemTpl {
  key: string;
  name: string;
  required?: boolean;
  guide?: GuideType;
}

export interface RoomTpl {
  key: string;
  name: string;
  items: ItemTpl[];
}

/** 场景模板：rooms 顺序即检查路线；meters/handover 决定交接数据页内容。 */
export interface SceneTemplate {
  sceneKey: string;
  title: string;
  description: string;
  rooms: RoomTpl[];
  meters: MeterType[];
  handover: boolean;
}

/** 引擎归一化后的实例化产物（写入 room/check_item 表前的内存形态）。 */
export interface PlannedItem {
  key: string;
  name: string;
  required: boolean;
  guide: GuideType;
  sort: number;
}

export interface PlannedRoom {
  key: string;
  name: string;
  sort: number;
  items: PlannedItem[];
}

export interface InspectPlan {
  sceneKey: string;
  title: string;
  startedAt: number;
  rooms: PlannedRoom[];
}
