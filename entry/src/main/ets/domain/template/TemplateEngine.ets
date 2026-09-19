import { MeterType } from '../model/CoreEnums';
import { GuideType, InspectPlan, ItemTpl, PlannedItem, PlannedRoom, RoomTpl, SceneTemplate } from '../model/TemplateModels';
import { LayoutSpec } from '../../common/LayoutUtil';
import { BUILTIN_TEMPLATES } from './BuiltinTemplates';

export class TemplateError extends Error {
  constructor(message: string) {
    super(message);
  }
}

/**
 * 模板引擎：解析模板、按户型裁剪房间、实例化为检查计划。
 * 纯逻辑，不依赖任何 @ohos/@kit，可被本地单测直接覆盖。
 */
export class TemplateEngine {
  static getBuiltin(sceneKey: string): SceneTemplate {
    for (const t of BUILTIN_TEMPLATES) {
      if (t.sceneKey === sceneKey) {
        return t;
      }
    }
    throw new TemplateError(`未知的内置场景模板: ${sceneKey}`);
  }

  /** 解析模板 JSON（用于未来用户自定义模板导入）：非法 JSON 统一抛 TemplateError。 */
  static parseSceneTemplate(json: string): SceneTemplate {
    let parsed: object | null = null;
    try {
      parsed = JSON.parse(json);
    } catch (err) {
      throw new TemplateError('模板 JSON 格式非法');
    }
    if (parsed === null) {
      throw new TemplateError('模板 JSON 为空');
    }
    const raw = parsed as SceneTemplate;
    if (typeof raw.sceneKey !== 'string' || raw.sceneKey.length === 0) {
      throw new TemplateError('缺少 sceneKey');
    }
    if (typeof raw.title !== 'string' || raw.title.length === 0) {
      throw new TemplateError('缺少 title');
    }
    if (!Array.isArray(raw.rooms) || raw.rooms.length === 0) {
      throw new TemplateError('rooms 不能为空');
    }
    const rooms: RoomTpl[] = [];
    const seenRooms = new Set<string>();
    for (const r of raw.rooms) {
      if (typeof r.key !== 'string' || r.key.length === 0) {
        throw new TemplateError('房间缺少 key');
      }
      if (typeof r.name !== 'string' || r.name.length === 0) {
        throw new TemplateError(`房间 ${r.key} 缺少 name`);
      }
      if (!Array.isArray(r.items) || r.items.length === 0) {
        throw new TemplateError(`房间 ${r.key} 缺少检查项`);
      }
      if (seenRooms.has(r.key)) {
        throw new TemplateError(`房间 key 重复: ${r.key}`);
      }
      seenRooms.add(r.key);
      const items: ItemTpl[] = [];
      const seenItems = new Set<string>();
      for (const it of r.items) {
        if (typeof it.key !== 'string' || it.key.length === 0) {
          throw new TemplateError(`房间 ${r.key} 的检查项缺少 key`);
        }
        if (typeof it.name !== 'string' || it.name.length === 0) {
          throw new TemplateError(`检查项 ${it.key} 缺少 name`);
        }
        if (seenItems.has(it.key)) {
          throw new TemplateError(`检查项 key 重复: ${it.key}`);
        }
        seenItems.add(it.key);
        const guide: GuideType = it.guide === GuideType.DIAL ? GuideType.DIAL : GuideType.NONE;
        items.push({ key: it.key, name: it.name, required: it.required !== false, guide: guide });
      }
      rooms.push({ key: r.key, name: r.name, items: items });
    }
    const validMeters: string[] = [MeterType.WATER, MeterType.ELECTRICITY, MeterType.GAS];
    const meters: MeterType[] = [];
    const seenMeters = new Set<string>();
    if (Array.isArray(raw.meters)) {
      for (const m of raw.meters) {
        if (typeof m !== 'string' || !validMeters.includes(m)) {
          throw new TemplateError(`非法的表具类型: ${String(m)}`);
        }
        // 去重：重复登记同一表型会让完整度 R2 分母重复计数
        if (!seenMeters.has(m)) {
          seenMeters.add(m);
          meters.push(m);
        }
      }
    }
    const tpl: SceneTemplate = {
      sceneKey: raw.sceneKey,
      title: raw.title,
      description: typeof raw.description === 'string' ? raw.description : '',
      rooms: rooms,
      meters: meters,
      handover: raw.handover === true
    };
    return tpl;
  }

  /** 户型裁剪：仅对通用房屋结构键生效，场景专属房间一律保留。 */
  static cropRooms(tpl: SceneTemplate, layout: LayoutSpec): RoomTpl[] {
    const kept: RoomTpl[] = [];
    for (const room of tpl.rooms) {
      if (TemplateEngine.roomExists(room.key, layout)) {
        kept.push(room);
      }
    }
    return kept;
  }

  private static roomExists(key: string, layout: LayoutSpec): boolean {
    switch (key) {
      case 'balcony':
        return layout.balconies > 0;
      case 'living':
        return layout.livingRooms > 0;
      case 'master_bedroom':
        return layout.bedrooms >= 1;
      case 'second_bedroom':
        return layout.bedrooms >= 2;
      case 'bathroom':
        return layout.bathrooms >= 1;
      default:
        return true;
    }
  }

  /** 实例化：归一化 required/guide 默认值，sort 按路线顺序连续编号。 */
  static instantiate(tpl: SceneTemplate, layout: LayoutSpec, startedAt: number): InspectPlan {
    const cropped = TemplateEngine.cropRooms(tpl, layout);
    if (cropped.length === 0) {
      throw new TemplateError('模板房间在当前户型下为空');
    }
    const rooms: PlannedRoom[] = [];
    let roomSort = 0;
    for (const room of cropped) {
      const items: PlannedItem[] = [];
      let itemSort = 0;
      for (const item of room.items) {
        const required: boolean = item.required !== false;
        const guide: GuideType = item.guide === undefined ? GuideType.NONE : item.guide;
        items.push({ key: item.key, name: item.name, required: required, guide: guide, sort: itemSort });
        itemSort++;
      }
      rooms.push({ key: room.key, name: room.name, sort: roomSort, items: items });
      roomSort++;
    }
    const plan: InspectPlan = {
      sceneKey: tpl.sceneKey,
      title: tpl.title,
      startedAt: startedAt,
      rooms: rooms
    };
    return plan;
  }
}
