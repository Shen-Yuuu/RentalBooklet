import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { formBindingData, formProvider } from '@kit.FormKit';
import { DbManager } from '../../data/db/DbManager';
import { InspectionStatus, ItemStatus } from '../../domain/model/CoreEnums';
import { TemplateEngine, TemplateError } from '../../domain/template/TemplateEngine';

/** 卡片绑定关系（formId ↔ 检查记录 id）。跨进程持久化到 JSON 文件（preferences 不支持多进程）。 */
export class FormBinding {
  formId: string = '';
  inspectionId: number = 0;
}

/** 卡片展示数据：字段名与 InspectionProgressCard 的 LocalStorageProp key 一一对应。 */
export class CardData {
  houseName: string = '租房留证册';
  sceneTitle: string = '';
  progressText: string = '正在读取检查进度…';
  statusText: string = '';
  inspectionId: number = 0;
}

/**
 * 检查进度卡片服务（F1，链路 L12）。
 * 卡片与主应用分属不同进程：绑定关系落 JSON 文件（跨进程读文件总是最新），
 * 数据查询直接走 DbManager（FormAbility 进程内独立打开同一 RDB）。
 * 全部公开方法静默容错——卡片任何失败都不允许阻塞主流程。
 */
export class WidgetService {
  private static bindingsFile(ctx: common.Context): string {
    return `${ctx.filesDir}/widget/form_bindings.json`;
  }

  /** 读取绑定列表；文件缺失/损坏时返回空列表。 */
  static loadBindings(ctx: common.Context): FormBinding[] {
    try {
      const path = WidgetService.bindingsFile(ctx);
      if (!fs.accessSync(path)) {
        return [];
      }
      const text = fs.readTextSync(path);
      const parsed: object = JSON.parse(text);
      if (!Array.isArray(parsed)) {
        return [];
      }
      const arr = parsed as FormBinding[];
      const list: FormBinding[] = [];
      for (const b of arr) {
        if (typeof b.formId === 'string' && b.formId.length > 0 &&
          typeof b.inspectionId === 'number' && b.inspectionId > 0) {
          const nb = new FormBinding();
          nb.formId = b.formId;
          nb.inspectionId = b.inspectionId;
          list.push(nb);
        }
      }
      return list;
    } catch (err) {
      return [];
    }
  }

  private static saveBindings(ctx: common.Context, bindings: FormBinding[]): void {
    let file: fs.File | undefined = undefined;
    try {
      fs.mkdirSync(`${ctx.filesDir}/widget`, true);
      file = fs.openSync(WidgetService.bindingsFile(ctx),
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, JSON.stringify(bindings));
    } catch (err) {
      // 绑定写入失败仅影响卡片刷新，静默
    } finally {
      if (file !== undefined) {
        try {
          fs.closeSync(file);
        } catch (err) {
          // 关闭失败无需处理
        }
      }
    }
  }

  static bindForm(ctx: common.Context, formId: string, inspectionId: number): void {
    const bindings = WidgetService.loadBindings(ctx).filter((b: FormBinding) => b.formId !== formId);
    const nb = new FormBinding();
    nb.formId = formId;
    nb.inspectionId = inspectionId;
    bindings.push(nb);
    WidgetService.saveBindings(ctx, bindings);
  }

  static unbindForm(ctx: common.Context, formId: string): void {
    WidgetService.saveBindings(ctx,
      WidgetService.loadBindings(ctx).filter((b: FormBinding) => b.formId !== formId));
  }

  /**
   * 卡片目标检查（L12 规则）：进行中草稿优先（最近开始），
   * 否则最近冻结记录，无任何记录返回 0（卡片显示空态）。
   */
  static async resolveTargetInspection(ctx: common.Context): Promise<number> {
    try {
      const db = await DbManager.getStore(ctx);
      const draftRs = await db.querySql(
        'SELECT id FROM inspection WHERE status = ? ORDER BY started_at DESC, id DESC LIMIT 1',
        [InspectionStatus.DRAFT]);
      if (draftRs.goToNextRow()) {
        const id = DbManager.rsLong(draftRs, 'id');
        draftRs.close();
        return id;
      }
      draftRs.close();
      const frozenRs = await db.querySql(
        'SELECT id FROM inspection WHERE status = ? ORDER BY frozen_at DESC, id DESC LIMIT 1',
        [InspectionStatus.FROZEN]);
      if (frozenRs.goToNextRow()) {
        const id = DbManager.rsLong(frozenRs, 'id');
        frozenRs.close();
        return id;
      }
      frozenRs.close();
      return 0;
    } catch (err) {
      return 0;
    }
  }

  /** 场景 key → 中文标题（与 InspectionLauncher 文案一致；无内置模板回退为 key）。 */
  private static sceneTitleOf(sceneKey: string): string {
    try {
      return TemplateEngine.getBuiltin(sceneKey).title;
    } catch (err) {
      if (err instanceof TemplateError) {
        return sceneKey;
      }
      return sceneKey;
    }
  }

  /** 组装卡片数据：JOIN house 取简称 + 子查询统计进度。记录不存在时返回提示态。 */
  static async buildCardData(ctx: common.Context, inspectionId: number): Promise<CardData> {
    const card = new CardData();
    if (inspectionId <= 0) {
      card.progressText = '暂无检查记录';
      card.statusText = '点击开始第一次检查';
      return card;
    }
    try {
      const db = await DbManager.getStore(ctx);
      const rs = await db.querySql(
        `SELECT i.scene_key, i.status, h.name AS house_name,
           (SELECT COUNT(*) FROM check_item ci JOIN room r ON ci.room_id = r.id
              WHERE r.inspection_id = i.id) AS total_items,
           (SELECT COUNT(*) FROM check_item ci JOIN room r ON ci.room_id = r.id
              WHERE r.inspection_id = i.id AND ci.status != ?) AS done_items
         FROM inspection i JOIN house h ON i.house_id = h.id WHERE i.id = ?`,
        [ItemStatus.PENDING, inspectionId]);
      try {
        if (rs.goToNextRow()) {
          card.houseName = DbManager.rsString(rs, 'house_name');
          card.sceneTitle = WidgetService.sceneTitleOf(DbManager.rsString(rs, 'scene_key'));
          const total = DbManager.rsLong(rs, 'total_items');
          const done = DbManager.rsLong(rs, 'done_items');
          card.progressText = total > 0 ? `完成 ${done}/${total} 项` : '暂无检查项';
          card.statusText = DbManager.rsString(rs, 'status') === InspectionStatus.FROZEN
            ? '已冻结' : '检查进行中';
          card.inspectionId = inspectionId;
        } else {
          card.progressText = '检查记录不存在';
          card.statusText = '点击进入应用查看';
        }
      } finally {
        rs.close();
      }
    } catch (err) {
      card.progressText = '检查进度读取失败';
    }
    return card;
  }

  /** 单张卡片刷新：构建数据 → formProvider.updateForm。失败静默。 */
  static async updateCard(ctx: common.Context, formId: string, inspectionId: number): Promise<void> {
    try {
      const card = await WidgetService.buildCardData(ctx, inspectionId);
      const data: Record<string, Object> = {
        'houseName': card.houseName,
        'sceneTitle': card.sceneTitle,
        'progressText': card.progressText,
        'statusText': card.statusText,
        'inspectionId': card.inspectionId
      };
      await formProvider.updateForm(formId, formBindingData.createFormBindingData(data));
    } catch (err) {
      // 卡片可能已被删除，静默
    }
  }

  /** 卡片添加：解析目标检查 → 写绑定 → 异步推送真实数据（onAddForm 占位返回后触发）。 */
  static onFormAdded(ctx: common.Context, formId: string): void {
    WidgetService.resolveTargetInspection(ctx).then((inspectionId: number) => {
      WidgetService.bindForm(ctx, formId, inspectionId);
      WidgetService.updateCard(ctx, formId, inspectionId).catch(() => {
      });
    }).catch(() => {
    });
  }

  /** 目标检查是否仍为草稿（重解析判断用；查询失败按非草稿处理）。 */
  private static async isDraft(ctx: common.Context, inspectionId: number): Promise<boolean> {
    try {
      const db = await DbManager.getStore(ctx);
      const rs = await db.querySql('SELECT status FROM inspection WHERE id = ?', [inspectionId]);
      let status: string = '';
      if (rs.goToNextRow()) {
        status = DbManager.rsString(rs, 'status');
      }
      rs.close();
      return status === InspectionStatus.DRAFT;
    } catch (err) {
      return false;
    }
  }

  /**
   * 主应用进度变化后的主动刷新入口：失败静默、永不抛错。
   * 绑定目标重解析（L12"进行中或最近冻结"语义）：绑定目标已冻结且存在更新目标时，
   * 卡片跟随最新目标，避免冻结后新建草稿卡片仍停留在旧记录。
   */
  static refreshProgress(ctx: common.Context, inspectionId: number = 0): void {
    WidgetService.doRefresh(ctx, inspectionId).catch(() => {
    });
  }

  private static async doRefresh(ctx: common.Context, inspectionId: number): Promise<void> {
    const bindings = WidgetService.loadBindings(ctx);
    if (bindings.length === 0) {
      return;
    }
    try {
      const latest = await WidgetService.resolveTargetInspection(ctx);
      if (latest > 0) {
        let rebound = false;
        for (const b of bindings) {
          // 仅当绑定目标已非进行中（冻结）且最新目标不同才跟随，不打扰多草稿并行场景
          if (b.inspectionId !== latest && !(await WidgetService.isDraft(ctx, b.inspectionId))) {
            b.inspectionId = latest;
            rebound = true;
          }
        }
        if (rebound) {
          WidgetService.saveBindings(ctx, bindings);
        }
      }
    } catch (err) {
      // 重解析失败不影响本次刷新
    }
    // 进度变化刷新全部绑定卡片（卡片数量少，全量刷新成本可忽略且无状态漂移）
    for (const b of bindings) {
      await WidgetService.updateCard(ctx, b.formId, b.inspectionId).catch(() => {
      });
    }
  }
}
