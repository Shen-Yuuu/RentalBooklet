import { common } from '@kit.AbilityKit';
import { Routes } from '../../common/Routes';
import { InspectionParam } from '../../common/NavParams';
import { LayoutUtil } from '../../common/LayoutUtil';
import { HouseRepo } from '../../data/repo/HouseRepo';
import { InspectionRepo } from '../../data/repo/InspectionRepo';
import { TemplateEngine, TemplateError } from '../../domain/template/TemplateEngine';
import { SceneKey } from '../../domain/model/CoreEnums';
import { Inspection } from '../../domain/model/Entities';

/** "开始一次检查"的共享流程：查档案 → 实例化模板 → 建会话 → 跳转执行页。 */
export class InspectionLauncher {
  /**
   * baselineInspectionId>0 时写入 inspection.baseline_inspection_id（E1 退租基线）。
   * 基线候选查询与选择 UI 由入口页负责（无候选直接传 0，跳过基线步）。
   */
  static async startForHouse(ctx: common.UIAbilityContext, pathStack: NavPathStack,
    houseId: number, sceneKey: string, removeSceneSelect: boolean,
    baselineInspectionId: number = 0): Promise<void> {
    const house = await new HouseRepo(ctx).getById(houseId);
    if (house === null) {
      throw new Error('房屋档案不存在');
    }
    const tpl = TemplateEngine.getBuiltin(sceneKey);
    const plan = TemplateEngine.instantiate(tpl, LayoutUtil.parse(house.layout), Date.now());
    const insId = await new InspectionRepo(ctx).createWithPlan(houseId, plan, baselineInspectionId);
    AppStorage.setOrCreate('home_dirty', Date.now());
    pathStack.replacePathByName(Routes.INSPECTION, { inspectionId: insId } as InspectionParam);
    if (removeSceneSelect) {
      pathStack.removeByName(Routes.SCENE_SELECT);
    }
  }

  /** E1 基线候选：同房屋已冻结的入住检查（最近在前），退租场景创建时供用户选择。 */
  static async listBaselines(ctx: common.UIAbilityContext, houseId: number): Promise<Inspection[]> {
    return new InspectionRepo(ctx).listFrozenByHouse(houseId, SceneKey.MOVE_IN);
  }

  static sceneTitleOf(sceneKey: string): string {
    try {
      return TemplateEngine.getBuiltin(sceneKey).title;
    } catch (e) {
      if (e instanceof TemplateError) {
        return sceneKey;
      }
      throw new Error(e instanceof Error ? e.message : '查询场景标题失败');
    }
  }
}
