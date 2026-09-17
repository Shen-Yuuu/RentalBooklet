import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { DbManager } from '../db/DbManager';
import { HandoverEntity } from '../../domain/model/Entities';

const TABLE: string = 'handover';

/**
 * 钥匙门禁交接仓库（handover 表，完整性 R3）。
 * 确认门闩红线：confirmed=0 的交接记录绝不进入报告/摘要。
 */
export class HandoverRepo {
  private ctx: common.UIAbilityContext;

  constructor(ctx: common.UIAbilityContext) {
    this.ctx = ctx;
  }

  private static rowToHandover(rs: relationalStore.ResultSet): HandoverEntity {
    const h = new HandoverEntity();
    h.inspectionId = DbManager.rsLong(rs, 'inspection_id');
    h.keyCount = DbManager.rsLong(rs, 'key_count');
    h.accessCardCount = DbManager.rsLong(rs, 'access_card_count');
    h.confirmed = DbManager.rsBool(rs, 'confirmed');
    h.parkingOrStorage = DbManager.rsString(rs, 'parking_or_storage');
    h.note = DbManager.rsString(rs, 'note');
    return h;
  }

  /** 某次检查的交接记录（无则 null）。 */
  async get(inspectionId: number): Promise<HandoverEntity | null> {
    const db = await DbManager.getStore(this.ctx);
    try {
      const rs = await db.querySql('SELECT * FROM handover WHERE inspection_id = ?', [inspectionId]);
      let result: HandoverEntity | null = null;
      if (rs.goToNextRow()) {
        result = HandoverRepo.rowToHandover(rs);
      }
      rs.close();
      return result;
    } catch (err) {
      const e = err as BusinessError;
      throw new Error(`交接记录查询失败 code=${e.code}`);
    }
  }

  /** 已有记录则 UPDATE，否则 INSERT（handover 以 inspection_id 为主键）。 */
  async upsert(inspectionId: number, keyCount: number, accessCardCount: number,
    parkingOrStorage: string, note: string, confirmed: boolean): Promise<void> {
    const db = await DbManager.getStore(this.ctx);
    await DbManager.assertInspectionDraft(db, inspectionId);
    const bucket: relationalStore.ValuesBucket = {
      'inspection_id': inspectionId,
      'key_count': keyCount,
      'access_card_count': accessCardCount,
      'parking_or_storage': parkingOrStorage.length > 0 ? parkingOrStorage : null,
      'note': note.length > 0 ? note : null,
      'confirmed': confirmed ? 1 : 0
    };
    try {
      const existing = await this.get(inspectionId);
      if (existing === null) {
        await db.insert(TABLE, bucket);
      } else {
        const pre = new relationalStore.RdbPredicates(TABLE);
        pre.equalTo('inspection_id', inspectionId);
        await db.update(bucket, pre);
      }
    } catch (err) {
      const e = err as BusinessError;
      throw new Error(`交接记录写入失败 code=${e.code}`);
    }
  }

  /**
   * "无需记录"：confirmed=1 + note='无需记录'（不引入魔法计数值）。
   * R3 通过条件是 confirmed==true，该语义即"交接已处理，无需登记数量"。
   */
  async markNoNeed(inspectionId: number): Promise<void> {
    await this.upsert(inspectionId, 0, 0, '', HandoverEntity.NO_NEED_NOTE, true);
  }
}
