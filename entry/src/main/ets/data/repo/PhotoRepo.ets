import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { DbManager } from '../db/DbManager';
import { PhotoEntity } from '../../domain/model/Entities';
import { PhotoKind, PhotoSource } from '../../domain/model/CoreEnums';

const TABLE: string = 'photo';

export class PhotoRepo {
  private ctx: common.UIAbilityContext;

  constructor(ctx: common.UIAbilityContext) {
    this.ctx = ctx;
  }

  private static rowToPhoto(rs: relationalStore.ResultSet): PhotoEntity {
    const p = new PhotoEntity();
    p.id = DbManager.rsLong(rs, 'id');
    p.inspectionId = DbManager.rsLong(rs, 'inspection_id');
    p.roomId = DbManager.rsLong(rs, 'room_id');
    p.itemId = DbManager.rsLong(rs, 'item_id');
    p.kind = DbManager.rsString(rs, 'kind') as PhotoKind;
    p.source = DbManager.rsString(rs, 'source') as PhotoSource;
    p.path = DbManager.rsString(rs, 'path');
    p.thumbPath = DbManager.rsString(rs, 'thumb_path');
    p.width = DbManager.rsLong(rs, 'width');
    p.height = DbManager.rsLong(rs, 'height');
    p.shotAt = DbManager.rsLong(rs, 'shot_at');
    p.location = DbManager.rsString(rs, 'location');
    p.qualityFlags = DbManager.rsString(rs, 'quality_flags');
    p.note = DbManager.rsString(rs, 'note');
    p.sha256 = DbManager.rsString(rs, 'sha256');
    return p;
  }

  async addPhoto(p: PhotoEntity): Promise<number> {
    const db = await DbManager.getStore(this.ctx);
    await DbManager.assertInspectionDraft(db, p.inspectionId);
    const bucket: relationalStore.ValuesBucket = {
      'inspection_id': p.inspectionId,
      'room_id': p.roomId > 0 ? p.roomId : null,
      'item_id': p.itemId > 0 ? p.itemId : null,
      'kind': p.kind,
      'source': p.source,
      'path': p.path,
      'thumb_path': p.thumbPath,
      'width': p.width,
      'height': p.height,
      'shot_at': p.shotAt,
      'location': p.location.length > 0 ? p.location : null,
      'quality_flags': p.qualityFlags.length > 0 ? p.qualityFlags : null,
      'note': p.note.length > 0 ? p.note : null
    };
    try {
      return await db.insert(TABLE, bucket);
    } catch (err) {
      const e = err as BusinessError;
      throw new Error(`照片索引写入失败 code=${e.code}`);
    }
  }

  async listByItem(itemId: number): Promise<PhotoEntity[]> {
    const db = await DbManager.getStore(this.ctx);
    try {
      const rs = await db.querySql('SELECT * FROM photo WHERE item_id = ? ORDER BY shot_at, id', [itemId]);
      const list: PhotoEntity[] = [];
      while (rs.goToNextRow()) {
        list.push(PhotoRepo.rowToPhoto(rs));
      }
      rs.close();
      return list;
    } catch (err) {
      const e = err as BusinessError;
      throw new Error(`照片列表失败 code=${e.code}`);
    }
  }

  /** 按 id 取单张照片（表读数页回显关联表盘照等场景）。 */
  async getById(photoId: number): Promise<PhotoEntity | null> {
    const db = await DbManager.getStore(this.ctx);
    try {
      const rs = await db.querySql('SELECT * FROM photo WHERE id = ?', [photoId]);
      let result: PhotoEntity | null = null;
      if (rs.goToNextRow()) {
        result = PhotoRepo.rowToPhoto(rs);
      }
      rs.close();
      return result;
    } catch (err) {
      const e = err as BusinessError;
      throw new Error(`照片查询失败 code=${e.code}`);
    }
  }

  /** 完整度检查用：某次检查的全部照片（含全景/细节归属关系）。 */
  async listByInspection(inspectionId: number): Promise<PhotoEntity[]> {
    const db = await DbManager.getStore(this.ctx);
    try {
      const rs = await db.querySql('SELECT * FROM photo WHERE inspection_id = ? ORDER BY shot_at, id', [inspectionId]);
      const list: PhotoEntity[] = [];
      while (rs.goToNextRow()) {
        list.push(PhotoRepo.rowToPhoto(rs));
      }
      rs.close();
      return list;
    } catch (err) {
      const e = err as BusinessError;
      throw new Error(`照片列表失败 code=${e.code}`);
    }
  }

  /** item_id → 照片数，供检查页角标使用。 */
  async countsByInspection(inspectionId: number): Promise<Map<number, number>> {
    const db = await DbManager.getStore(this.ctx);
    try {
      const rs = await db.querySql(
        'SELECT item_id, COUNT(*) AS cnt FROM photo WHERE inspection_id = ? AND item_id IS NOT NULL GROUP BY item_id',
        [inspectionId]);
      const map = new Map<number, number>();
      while (rs.goToNextRow()) {
        map.set(DbManager.rsLong(rs, 'item_id'), DbManager.rsLong(rs, 'cnt'));
      }
      rs.close();
      return map;
    } catch (err) {
      const e = err as BusinessError;
      throw new Error(`照片计数失败 code=${e.code}`);
    }
  }

  async deletePhoto(photoId: number): Promise<void> {
    const db = await DbManager.getStore(this.ctx);
    // FROZEN 只读红线：通过照片行反查所属检查，非 DRAFT 一律拒绝删除
    const insRs = await db.querySql('SELECT inspection_id FROM photo WHERE id = ?', [photoId]);
    let inspectionId: number = 0;
    if (insRs.goToNextRow()) {
      inspectionId = DbManager.rsLong(insRs, 'inspection_id');
    }
    insRs.close();
    if (inspectionId > 0) {
      await DbManager.assertInspectionDraft(db, inspectionId);
    }
    try {
      const rs = await db.querySql('SELECT path, thumb_path FROM photo WHERE id = ?', [photoId]);
      if (rs.goToNextRow()) {
        const path = DbManager.rsString(rs, 'path');
        const thumb = DbManager.rsString(rs, 'thumb_path');
        rs.close();
        try {
          fs.unlinkSync(path);
        } catch (err) {
          // 文件可能已不存在
        }
        try {
          fs.unlinkSync(thumb);
        } catch (err) {
          // 同上
        }
        const pre = new relationalStore.RdbPredicates(TABLE);
        pre.equalTo('id', photoId);
        await db.delete(pre);
        return;
      }
      rs.close();
    } catch (err) {
      const e = err as BusinessError;
      throw new Error(`照片删除失败 code=${e.code}`);
    }
  }
}
