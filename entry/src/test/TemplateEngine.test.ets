import { describe, it, expect } from '@ohos/hypium';
import { TemplateEngine, TemplateError } from '../main/ets/domain/template/TemplateEngine';
import {
  APPLIANCE_TEMPLATE,
  BUILTIN_TEMPLATES,
  CLEANING_TEMPLATE,
  CUSTOM_TEMPLATE,
  MOVE_IN_TEMPLATE,
  MOVE_OUT_TEMPLATE,
  REPAIR_TEMPLATE
} from '../main/ets/domain/template/BuiltinTemplates';
import { LayoutSpec, LayoutUtil } from '../main/ets/common/LayoutUtil';
import { GuideType } from '../main/ets/domain/model/TemplateModels';

const MOVE_IN_ROOMS: number = 9;
const MOVE_IN_ITEMS: number = 55;

export default function templateEngineTest(): void {
  describe('TemplateEngine', () => {
    it('builtin_move_in_full_layout_9_rooms_55_items', 0, () => {
      const plan = TemplateEngine.instantiate(MOVE_IN_TEMPLATE, new LayoutSpec(2, 1, 1, 1), 0);
      expect(plan.rooms.length).assertEqual(MOVE_IN_ROOMS);
      let total = 0;
      for (const r of plan.rooms) {
        total += r.items.length;
      }
      expect(total).assertEqual(MOVE_IN_ITEMS);
      expect(plan.rooms[0].key).assertEqual('entrance');
      expect(plan.rooms[8].key).assertEqual('handover');
      expect(plan.sceneKey).assertEqual('move_in');
    });

    it('sorts_are_sequential', 0, () => {
      const plan = TemplateEngine.instantiate(MOVE_IN_TEMPLATE, new LayoutSpec(2, 1, 1, 1), 0);
      for (let i = 0; i < plan.rooms.length; i++) {
        expect(plan.rooms[i].sort).assertEqual(i);
        for (let j = 0; j < plan.rooms[i].items.length; j++) {
          expect(plan.rooms[i].items[j].sort).assertEqual(j);
        }
      }
    });

    it('meter_items_have_dial_guide', 0, () => {
      const plan = TemplateEngine.instantiate(MOVE_IN_TEMPLATE, new LayoutSpec(2, 1, 1, 1), 0);
      const metersRoom = plan.rooms[7];
      expect(metersRoom.key).assertEqual('meters');
      expect(metersRoom.items[0].guide).assertEqual(GuideType.DIAL);
      expect(metersRoom.items[1].guide).assertEqual(GuideType.DIAL);
      expect(metersRoom.items[2].guide).assertEqual(GuideType.DIAL);
      expect(metersRoom.items[3].guide).assertEqual(GuideType.NONE);
    });

    it('move_out_keys_match_move_in', 0, () => {
      expect(MOVE_OUT_TEMPLATE.rooms.length).assertEqual(MOVE_IN_TEMPLATE.rooms.length);
      for (let i = 0; i < MOVE_IN_TEMPLATE.rooms.length; i++) {
        expect(MOVE_OUT_TEMPLATE.rooms[i].key).assertEqual(MOVE_IN_TEMPLATE.rooms[i].key);
        expect(MOVE_OUT_TEMPLATE.rooms[i].items.length).assertEqual(MOVE_IN_TEMPLATE.rooms[i].items.length);
        for (let j = 0; j < MOVE_IN_TEMPLATE.rooms[i].items.length; j++) {
          expect(MOVE_OUT_TEMPLATE.rooms[i].items[j].key).assertEqual(MOVE_IN_TEMPLATE.rooms[i].items[j].key);
        }
      }
    });

    // 防回归：前后对比按 (room_key, item_key) 对齐，两模板的键集合必须完全相等
    it('move_in_move_out_room_item_key_sets_identical', 0, () => {
      const moveInKeys = new Set<string>();
      const moveOutKeys = new Set<string>();
      for (const r of MOVE_IN_TEMPLATE.rooms) {
        for (const item of r.items) {
          moveInKeys.add(`${r.key}/${item.key}`);
        }
      }
      for (const r of MOVE_OUT_TEMPLATE.rooms) {
        for (const item of r.items) {
          moveOutKeys.add(`${r.key}/${item.key}`);
        }
      }
      expect(moveInKeys.size > 0).assertTrue();
      expect(moveOutKeys.size > 0).assertTrue();
      expect(moveInKeys.size).assertEqual(moveOutKeys.size);
      for (const k of moveInKeys) {
        expect(moveOutKeys.has(k)).assertTrue();
      }
      for (const k of moveOutKeys) {
        expect(moveInKeys.has(k)).assertTrue();
      }
    });

    // 防回归：required 标记与产品文档 §3.2 ★ 必查项基线一致
    // （断言实例化后的 plan：模板字面量省略 required 时为 undefined，instantiate 归一化为 true）
    it('required_flags_match_doc_baseline', 0, () => {
      const plan = TemplateEngine.instantiate(MOVE_IN_TEMPLATE, new LayoutSpec(2, 1, 1, 1), 0);
      let balcony: number = -1;
      let kitchen: number = -1;
      let bathroom: number = -1;
      let master: number = -1;
      let second: number = -1;
      for (let i = 0; i < plan.rooms.length; i++) {
        const key = plan.rooms[i].key;
        if (key === 'balcony') {
          balcony = i;
        } else if (key === 'kitchen') {
          kitchen = i;
        } else if (key === 'bathroom') {
          bathroom = i;
        } else if (key === 'master_bedroom') {
          master = i;
        } else if (key === 'second_bedroom') {
          second = i;
        }
      }
      expect(balcony >= 0 && kitchen >= 0 && bathroom >= 0 && master >= 0 && second >= 0).assertTrue();
      // 阳台全建议项
      for (const item of plan.rooms[balcony].items) {
        expect(item.required).assertEqual(false);
      }
      // 厨房：燃气阀门非必查
      for (const item of plan.rooms[kitchen].items) {
        if (item.key === 'gas_valve') {
          expect(item.required).assertEqual(false);
        }
      }
      // 卫生间：淋浴区/渗漏痕迹非必查，地漏排水必查
      for (const item of plan.rooms[bathroom].items) {
        if (item.key === 'shower' || item.key === 'leak_traces') {
          expect(item.required).assertEqual(false);
        }
        if (item.key === 'floor_drain') {
          expect(item.required).assertEqual(true);
        }
      }
      // 主卧/次卧：地板非必查、窗户与锁扣必查、插座存在且非必查（次卧同主卧）
      for (const roomIdx of [master, second]) {
        let hasSocket = false;
        for (const item of plan.rooms[roomIdx].items) {
          if (item.key === 'floor') {
            expect(item.required).assertEqual(false);
          }
          if (item.key === 'window_lock') {
            expect(item.required).assertEqual(true);
          }
          if (item.key === 'socket') {
            hasSocket = true;
            expect(item.required).assertEqual(false);
          }
        }
        expect(hasSocket).assertTrue();
      }
    });

    it('crop_removes_balcony_and_second_bedroom', 0, () => {
      const plan = TemplateEngine.instantiate(MOVE_IN_TEMPLATE, LayoutUtil.parse('1-1-1-0'), 0);
      expect(plan.rooms.length).assertEqual(7);
      let total = 0;
      for (const r of plan.rooms) {
        total += r.items.length;
      }
      expect(total).assertEqual(44);
      for (const r of plan.rooms) {
        expect(r.key !== 'balcony' && r.key !== 'second_bedroom').assertTrue();
      }
    });

    it('crop_zero_bedrooms', 0, () => {
      const plan = TemplateEngine.instantiate(MOVE_IN_TEMPLATE, LayoutUtil.parse('0-1-1-0'), 0);
      expect(plan.rooms.length).assertEqual(6);
    });

    it('repair_template_is_linear_6_steps', 0, () => {
      expect(REPAIR_TEMPLATE.rooms.length).assertEqual(6);
      expect(REPAIR_TEMPLATE.meters.length).assertEqual(0);
      expect(REPAIR_TEMPLATE.handover).assertEqual(false);
    });

    it('cleaning_appliance_custom_shapes', 0, () => {
      expect(CLEANING_TEMPLATE.rooms.length).assertEqual(5);
      expect(APPLIANCE_TEMPLATE.rooms.length).assertEqual(5);
      expect(APPLIANCE_TEMPLATE.rooms[0].items.length).assertEqual(4);
      expect(CUSTOM_TEMPLATE.rooms.length).assertEqual(1);
      expect(CUSTOM_TEMPLATE.rooms[0].items[0].required).assertEqual(false);
    });

    it('builtin_registry_has_six_scenes', 0, () => {
      expect(BUILTIN_TEMPLATES.length).assertEqual(6);
      for (const t of BUILTIN_TEMPLATES) {
        expect(t.rooms.length > 0).assertTrue();
        expect(t.title.length > 0).assertTrue();
      }
    });

    it('parse_normalizes_defaults', 0, () => {
      const json = '{"sceneKey":"custom","title":"自定义","rooms":[{"key":"r1","name":"房间","items":[{"key":"i1","name":"项"},{"key":"i2","name":"表项","required":false,"guide":"dial"}]}]}';
      const tpl = TemplateEngine.parseSceneTemplate(json);
      expect(tpl.rooms[0].items[0].required).assertEqual(true);
      expect(tpl.rooms[0].items[0].guide).assertEqual(GuideType.NONE);
      expect(tpl.rooms[0].items[1].required).assertEqual(false);
      expect(tpl.rooms[0].items[1].guide).assertEqual(GuideType.DIAL);
      expect(tpl.handover).assertEqual(false);
      expect(tpl.meters.length).assertEqual(0);
    });

    it('parse_rejects_missing_scene_key', 0, () => {
      let threw = false;
      try {
        TemplateEngine.parseSceneTemplate('{"sceneKey":"","title":"t","rooms":[{"key":"r","name":"n","items":[{"key":"i","name":"x"}]}]}');
      } catch (e) {
        threw = e instanceof TemplateError;
      }
      expect(threw).assertTrue();
    });

    it('parse_rejects_duplicate_room_key', 0, () => {
      const dup = '{"sceneKey":"c","title":"t","rooms":[{"key":"r","name":"a","items":[{"key":"i","name":"x"}]},{"key":"r","name":"b","items":[{"key":"j","name":"y"}]}]}';
      let threw = false;
      try {
        TemplateEngine.parseSceneTemplate(dup);
      } catch (e) {
        threw = e instanceof TemplateError;
      }
      expect(threw).assertTrue();
    });

    it('parse_rejects_empty_rooms', 0, () => {
      let threw = false;
      try {
        TemplateEngine.parseSceneTemplate('{"sceneKey":"c","title":"t","rooms":[]}');
      } catch (e) {
        threw = e instanceof TemplateError;
      }
      expect(threw).assertTrue();
    });

    it('getBuiltin_throws_for_unknown_scene', 0, () => {
      let threw = false;
      try {
        TemplateEngine.getBuiltin('no_such_scene');
      } catch (e) {
        threw = e instanceof TemplateError;
      }
      expect(threw).assertTrue();
    });
  });
}
