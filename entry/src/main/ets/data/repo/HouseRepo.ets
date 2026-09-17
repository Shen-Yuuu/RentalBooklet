import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { DbManager } from '../db/DbManager';
import { House } from '../../domain/model/Entities';
import { BusinessError } from '@kit.BasicServicesKit';

const TABLE: string = 'house';

export class HouseRepo {
  private ctx: common.UIAbilityContext;

  constructor(ctx: common.UIAbilityContext) {
    this.ctx = ctx;
  }

  private static rowToHouse(rs: relationalStore.ResultSet): House {
    const h = new House();
    h.id = DbManager.rsLong(rs, 'id');
    h.name = DbManager.rsString(rs, 'name');
    h.fullAddress = DbManager.rsString(rs, 'full_address');
    h.layout = DbManager.rsString(rs, 'layout');
    h.landlordName = DbManager.rsString(rs, 'landlord_name');
    h.landlordPhone = DbManager.rsString(rs, 'landlord_phone');
    h.tenantName = DbManager.rsString(rs, 'tenant_name');
    h.tenantPhone = DbManager.rsString(rs, 'tenant_phone');
    h.leaseEndDate = DbManager.rsLong(rs, 'lease_end_date');
    h.recordLocation = DbManager.rsBool(rs, 'record_location');
    h.createdAt = DbManager.rsLong(rs, 'created_at');
    h.updatedAt = DbManager.rsLong(rs, 'updated_at');
    return h;
  }

  private static toBucket(h: House, now: number): relationalStore.ValuesBucket {
    const bucket: relationalStore.ValuesBucket = {
      'name': h.name,
      'full_address': h.fullAddress,
      'layout': h.layout,
      'landlord_name': h.landlordName,
      'landlord_phone': h.landlordPhone,
      'tenant_name': h.tenantName,
      'tenant_phone': h.tenantPhone,
      'lease_end_date': h.leaseEndDate,
      'record_location': h.recordLocation ? 1 : 0,
      'updated_at': now
    };
    return bucket;
  }

  async create(h: House): Promise<number> {
    const db = await DbManager.getStore(this.ctx);
    const bucket = HouseRepo.toBucket(h, Date.now());
    try {
      return await db.insert(TABLE, bucket);
    } catch (err) {
      const e = err as BusinessError;
      throw new Error(`房屋档案创建失败 code=${e.code} message=${e.message}`);
    }
  }

  async update(h: House): Promise<void> {
    const db = await DbManager.getStore(this.ctx);
    const bucket = HouseRepo.toBucket(h, Date.now());
    const pre = new relationalStore.RdbPredicates(TABLE);
    pre.equalTo('id', h.id);
    try {
      await db.update(bucket, pre);
    } catch (err) {
      const e = err as BusinessError;
      throw new Error(`房屋档案更新失败 code=${e.code}`);
    }
  }

  async getById(id: number): Promise<House | null> {
    const db = await DbManager.getStore(this.ctx);
    try {
      const rs = await db.querySql('SELECT * FROM house WHERE id = ?', [id]);
      const house: House | null = rs.goToNextRow() ? HouseRepo.rowToHouse(rs) : null;
      rs.close();
      return house;
    } catch (err) {
      const e = err as BusinessError;
      throw new Error(`房屋档案查询失败 code=${e.code}`);
    }
  }

  async listAll(): Promise<House[]> {
    const db = await DbManager.getStore(this.ctx);
    try {
      const rs = await db.querySql('SELECT * FROM house ORDER BY updated_at DESC');
      const list: House[] = [];
      while (rs.goToNextRow()) {
        list.push(HouseRepo.rowToHouse(rs));
      }
      rs.close();
      return list;
    } catch (err) {
      const e = err as BusinessError;
      throw new Error(`房屋档案列表失败 code=${e.code}`);
    }
  }
}
