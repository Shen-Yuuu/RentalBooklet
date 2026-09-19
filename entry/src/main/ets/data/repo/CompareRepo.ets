import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { DbManager } from '../db/DbManager';
import { CompareSummary } from '../../domain/model/Entities';
import { CompareResult } from '../../domain/model/CoreEnums';

const TABLE: string = 'compare_result';

/**
 * 前后对比结果仓库（compare_result 表，产品文档 §5.6 / 链路 L11）。
 * 措辞红线：仅记录用户三态确认（无变化/有变化/待确认），不产生任何归因文案。
 * UNIQUE(item_id)：同一检查项仅一条结果，重复点击覆盖旧值。
 */
export class CompareRepo {
  private ctx: common.UIAbilityContext;

  constructor(ctx: common.UIAbilityContext) {
    this.ctx = ctx;
  }

  /** 某次检查的确认现状：itemId → 三态结果（未标记的项不在 Map 中）。 */
  async listResults(inspectionId: number): Promise<Map<number, string>> {
    const db = await DbManager.getStore(this.ctx);
    try {
      const rs = await db.querySql('SELECT item_id, result FROM compare_result WHERE inspection_id = ?',
        [inspectionId]);
      const map = new Map<number, string>();
      while (rs.goToNextRow()) {
        map.set(DbManager.rsLong(rs, 'item_id'), DbManager.rsString(rs, 'result'));
      }
      rs.close();
      return map;
    } catch (err) {
      const e = err as BusinessError;
      throw new Error(`对比结果查询失败 code=${e.code}`);
    }
  }

  /**
   * 同 item_id 已有结果则 UPDATE，否则 INSERT（UNIQUE(item_id) 冲突走更新，
   * 与 MeterRepo.upsert 同模式：先查存在行，再决定 insert/update）。
   */
  async upsert(inspectionId: number, itemId: number, result: string, note: string): Promise<void> {
    const db = await DbManager.getStore(this.ctx);
    await DbManager.assertInspectionDraft(db, inspectionId);
    const bucket: relationalStore.ValuesBucket = {
      'inspection_id': inspectionId,
      'item_id': itemId,
      'result': result,
      'note': note.length > 0 ? note : null,
      'updated_at': Date.now()
    };
    // 事务包裹"先查后写"：并发重入不会撞 UNIQUE(item_id) 约束
    db.beginTransaction();
    try {
      const rs = await db.querySql('SELECT id FROM compare_result WHERE item_id = ?', [itemId]);
      const has = rs.goToNextRow();
      const existId = has ? DbManager.rsLong(rs, 'id') : 0;
      rs.close();
      if (!has) {
        await db.insert(TABLE, bucket);
      } else {
        const pre = new relationalStore.RdbPredicates(TABLE);
        pre.equalTo('id', existId);
        await db.update(bucket, pre);
      }
      db.commit();
    } catch (err) {
      db.rollBack();
      const e = err as BusinessError;
      throw new Error(`对比结果写入失败 code=${e.code}`);
    }
  }

  /** 已确认汇总：total=已标记项数，changed=其中"有变化"项数（由 listResults 计算，不做 SQL 聚合）。 */
  async summary(inspectionId: number): Promise<CompareSummary> {
    const results = await this.listResults(inspectionId);
    const s = new CompareSummary();
    s.total = results.size;
    for (const value of results.values()) {
      if (value === CompareResult.CHANGED) {
        s.changed++;
      }
    }
    return s;
  }
}
