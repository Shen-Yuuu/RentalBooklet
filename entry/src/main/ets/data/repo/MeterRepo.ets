import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { DbManager } from '../db/DbManager';
import { MeterReadingEntity } from '../../domain/model/Entities';

const TABLE: string = 'meter_reading';

/**
 * 表读数仓库（meter_reading 表，产品文档 §5.8 / 链路 L5）。
 * 确认门闩红线：confirmed=0 的记录绝不进入报告/摘要——本仓库仅由表读数确认页调用，
 * upsert 落库的记录一律由调用方在用户点击「确认保存」时写入（保存即确认）。
 */
export class MeterRepo {
  private ctx: common.UIAbilityContext;

  constructor(ctx: common.UIAbilityContext) {
    this.ctx = ctx;
  }

  private static rowToMeter(rs: relationalStore.ResultSet): MeterReadingEntity {
    const m = new MeterReadingEntity();
    m.id = DbManager.rsLong(rs, 'id');
    m.inspectionId = DbManager.rsLong(rs, 'inspection_id');
    m.meterType = DbManager.rsString(rs, 'meter_type');
    m.valueText = DbManager.rsString(rs, 'value_text');
    m.confirmed = DbManager.rsBool(rs, 'confirmed');
    m.naFlag = DbManager.rsBool(rs, 'na_flag');
    m.unit = DbManager.rsString(rs, 'unit');
    m.ocrRawText = DbManager.rsString(rs, 'ocr_raw_text');
    m.ocrConf = DbManager.rsDouble(rs, 'ocr_conf');
    m.photoId = DbManager.rsLong(rs, 'photo_id');
    m.note = DbManager.rsString(rs, 'note');
    return m;
  }

  /** 某次检查某类表的最新一条读数记录（无则 null）。 */
  async getByType(inspectionId: number, meterType: string): Promise<MeterReadingEntity | null> {
    const db = await DbManager.getStore(this.ctx);
    try {
      const rs = await db.querySql(
        'SELECT * FROM meter_reading WHERE inspection_id = ? AND meter_type = ? ORDER BY id DESC LIMIT 1',
        [inspectionId, meterType]);
      let result: MeterReadingEntity | null = null;
      if (rs.goToNextRow()) {
        result = MeterRepo.rowToMeter(rs);
      }
      rs.close();
      return result;
    } catch (err) {
      const e = err as BusinessError;
      throw new Error(`表读数查询失败 code=${e.code}`);
    }
  }

  /**
   * 同 inspection+type 已有记录则 UPDATE，否则 INSERT（链路 L5：重复拍覆盖旧值）。
   * ocrConf 传 null 表示无置信度数据（当前 textRecognition API 不返回置信度，列为 NULL）。
   */
  async upsert(inspectionId: number, meterType: string, valueText: string, ocrRawText: string,
    ocrConf: number | null, photoId: number, confirmed: boolean, naFlag: boolean,
    note: string): Promise<void> {
    const db = await DbManager.getStore(this.ctx);
    await DbManager.assertInspectionDraft(db, inspectionId);
    const bucket: relationalStore.ValuesBucket = {
      'inspection_id': inspectionId,
      'meter_type': meterType,
      'value_text': valueText.length > 0 ? valueText : null,
      'unit': '',
      'ocr_raw_text': ocrRawText.length > 0 ? ocrRawText : null,
      'ocr_conf': ocrConf,
      'photo_id': photoId > 0 ? photoId : null,
      'confirmed': confirmed ? 1 : 0,
      'na_flag': naFlag ? 1 : 0,
      'note': note.length > 0 ? note : null
    };
    // 事务包裹"先查后写"：并发重入不会对同一 inspection+type 插入两行
    db.beginTransaction();
    try {
      const existing = await this.getByType(inspectionId, meterType);
      if (existing === null) {
        await db.insert(TABLE, bucket);
      } else {
        const pre = new relationalStore.RdbPredicates(TABLE);
        pre.equalTo('id', existing.id);
        await db.update(bucket, pre);
      }
      db.commit();
    } catch (err) {
      db.rollBack();
      const e = err as BusinessError;
      throw new Error(`表读数写入失败 code=${e.code}`);
    }
  }

  /** 删除某次检查某类表的读数记录（"保留历史可删"：删除即整行 DELETE）。 */
  async deleteByType(inspectionId: number, meterType: string): Promise<void> {
    const db = await DbManager.getStore(this.ctx);
    await DbManager.assertInspectionDraft(db, inspectionId);
    try {
      const pre = new relationalStore.RdbPredicates(TABLE);
      pre.equalTo('inspection_id', inspectionId).equalTo('meter_type', meterType);
      await db.delete(pre);
    } catch (err) {
      const e = err as BusinessError;
      throw new Error(`表读数删除失败 code=${e.code}`);
    }
  }
}
