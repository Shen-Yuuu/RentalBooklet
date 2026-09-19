import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { InspectionStatus } from '../../domain/model/CoreEnums';

export const DB_NAME: string = 'rental.db';
export const DB_VERSION: number = 3;

export class DbError extends Error {
  constructor(message: string) {
    super(message);
  }
}

/** 数据库单例：打开加密 RDB + 版本迁移。表结构见技术设计文档 §4.1。 */
export class DbManager {
  /** 缓存打开中的 Promise：并发调用共享同一次打开，避免重复建库；失败置空允许重试。 */
  private static storePromise: Promise<relationalStore.RdbStore> | null = null;

  static readonly DDL: string[] = [
    `CREATE TABLE IF NOT EXISTS house (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      full_address TEXT,
      layout TEXT NOT NULL,
      landlord_name TEXT,
      landlord_phone TEXT,
      tenant_name TEXT,
      tenant_phone TEXT,
      lease_end_date INTEGER,
      record_location INTEGER DEFAULT 0,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )`,
    `CREATE TABLE IF NOT EXISTS inspection (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      house_id INTEGER NOT NULL REFERENCES house(id),
      scene_key TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'DRAFT',
      baseline_inspection_id INTEGER,
      parent_revision_id INTEGER,
      revision_no INTEGER DEFAULT 0,
      report_no TEXT,
      started_at INTEGER NOT NULL,
      frozen_at INTEGER,
      participants TEXT,
      extra_note TEXT,
      complete_required REAL,
      complete_suggested REAL
    )`,
    `CREATE TABLE IF NOT EXISTS room (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      inspection_id INTEGER NOT NULL REFERENCES inspection(id),
      template_key TEXT NOT NULL,
      name TEXT NOT NULL,
      sort INTEGER NOT NULL
    )`,
    `CREATE TABLE IF NOT EXISTS check_item (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      room_id INTEGER NOT NULL REFERENCES room(id),
      template_key TEXT NOT NULL,
      name TEXT NOT NULL,
      sort INTEGER NOT NULL,
      required INTEGER DEFAULT 1,
      guide TEXT DEFAULT 'none',
      status TEXT DEFAULT 'PENDING',
      note_raw TEXT,
      note_suggestion TEXT,
      note_final TEXT,
      waiver INTEGER DEFAULT 0,
      updated_at INTEGER
    )`,
    `CREATE TABLE IF NOT EXISTS photo (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      inspection_id INTEGER NOT NULL REFERENCES inspection(id),
      room_id INTEGER,
      item_id INTEGER REFERENCES check_item(id),
      kind TEXT NOT NULL,
      source TEXT NOT NULL,
      path TEXT NOT NULL,
      thumb_path TEXT,
      width INTEGER,
      height INTEGER,
      shot_at INTEGER NOT NULL,
      location TEXT,
      quality_flags TEXT,
      note TEXT,
      sha256 TEXT
    )`,
    `CREATE TABLE IF NOT EXISTS meter_reading (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      inspection_id INTEGER NOT NULL REFERENCES inspection(id),
      meter_type TEXT NOT NULL,
      value_text TEXT,
      unit TEXT DEFAULT '',
      ocr_raw_text TEXT,
      ocr_conf REAL,
      photo_id INTEGER REFERENCES photo(id),
      confirmed INTEGER DEFAULT 0,
      na_flag INTEGER DEFAULT 0,
      note TEXT
    )`,
    `CREATE TABLE IF NOT EXISTS handover (
      inspection_id INTEGER PRIMARY KEY REFERENCES inspection(id),
      key_count INTEGER,
      access_card_count INTEGER,
      parking_or_storage TEXT,
      note TEXT,
      confirmed INTEGER DEFAULT 0
    )`,
    `CREATE TABLE IF NOT EXISTS signature (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      inspection_id INTEGER NOT NULL REFERENCES inspection(id),
      role TEXT NOT NULL,
      path TEXT NOT NULL,
      sha256 TEXT,
      signed_at INTEGER NOT NULL
    )`,
    `CREATE TABLE IF NOT EXISTS manifest (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      inspection_id INTEGER NOT NULL REFERENCES inspection(id),
      revision_no INTEGER NOT NULL,
      algorithm TEXT NOT NULL DEFAULT 'SHA-256',
      generated_at INTEGER NOT NULL,
      content TEXT NOT NULL,
      UNIQUE(inspection_id, revision_no)
    )`,
    `CREATE INDEX IF NOT EXISTS idx_inspection_house ON inspection(house_id)`,
    `CREATE INDEX IF NOT EXISTS idx_room_inspection ON room(inspection_id)`,
    `CREATE INDEX IF NOT EXISTS idx_item_room ON check_item(room_id)`,
    `CREATE INDEX IF NOT EXISTS idx_photo_inspection ON photo(inspection_id)`,
    `CREATE INDEX IF NOT EXISTS idx_photo_item ON photo(item_id)`,
    `CREATE INDEX IF NOT EXISTS idx_meter_inspection ON meter_reading(inspection_id)`
  ];

  /** v2 迁移语句（技术设计文档 §4.1 v2 迁移）：前后对比表 + R4 弃权原因 + PDF 哈希回填列。 */
  static readonly DDL_V2: string[] = [
    `CREATE TABLE IF NOT EXISTS compare_result (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      inspection_id INTEGER NOT NULL REFERENCES inspection(id),
      item_id INTEGER NOT NULL REFERENCES check_item(id),
      result TEXT NOT NULL DEFAULT 'PENDING',
      note TEXT,
      updated_at INTEGER,
      UNIQUE(item_id)
    )`,
    `CREATE INDEX IF NOT EXISTS idx_compare_inspection ON compare_result(inspection_id)`,
    // SQLite 的 ALTER TABLE 不支持 IF NOT EXISTS；迁移仅在 version<2 时执行一次，天然幂等
    `ALTER TABLE check_item ADD COLUMN waiver_reason TEXT`,
    `ALTER TABLE inspection ADD COLUMN pdf_sha256 TEXT`
  ];

  /** v3 迁移：报告号唯一索引（冻结事务内已有占用复查，此处为库级硬约束兜底；NULL 报告号不受约束）。 */
  static readonly DDL_V3: string[] = [
    `CREATE UNIQUE INDEX IF NOT EXISTS idx_inspection_report_no ON inspection(report_no)`
  ];

  /** 接受基类 Context：FormExtensionAbility（卡片进程）同样需要打开 RDB。 */
  static async getStore(context: common.Context): Promise<relationalStore.RdbStore> {
    if (DbManager.storePromise !== null) {
      return DbManager.storePromise;
    }
    const opening = DbManager.openStore(context);
    DbManager.storePromise = opening;
    try {
      return await opening;
    } catch (err) {
      // 打开/迁移失败：清空缓存，下次调用重新打开（允许重试）
      if (DbManager.storePromise === opening) {
        DbManager.storePromise = null;
      }
      if (err instanceof DbError) {
        throw err;
      }
      const e = err as BusinessError;
      throw new DbError(`数据库打开失败 code=${e.code} message=${e.message}`);
    }
  }

  private static async openStore(context: common.Context): Promise<relationalStore.RdbStore> {
    const config: relationalStore.StoreConfig = {
      name: DB_NAME,
      securityLevel: relationalStore.SecurityLevel.S2,
      encrypt: true
    };
    let db: relationalStore.RdbStore;
    try {
      db = await relationalStore.getRdbStore(context, config);
    } catch (err) {
      const e = err as BusinessError;
      throw new DbError(`数据库打开失败 code=${e.code} message=${e.message}`);
    }
    try {
      await db.executeSql('PRAGMA foreign_keys = ON');
    } catch (err) {
      const e = err as BusinessError;
      throw new DbError(`外键开关设置失败 code=${e.code}`);
    }
    await DbManager.migrate(db);
    return db;
  }

  /** 迁移单语句执行：跨进程（UI 与卡片进程）首启并发迁移时 ALTER 可能报 duplicate column，视为已成功。 */
  private static async execMigrationSql(db: relationalStore.RdbStore, sql: string): Promise<void> {
    try {
      await db.executeSql(sql);
    } catch (err) {
      const e = err as BusinessError;
      if (e.message !== undefined && e.message.includes('duplicate column name')) {
        return;
      }
      throw new Error(`迁移语句执行失败 code=${e.code} message=${e.message}`);
    }
  }

  static async migrate(db: relationalStore.RdbStore): Promise<void> {
    const current: number = db.version;
    if (current >= DB_VERSION) {
      return;
    }
    if (current < 1) {
      db.beginTransaction();
      try {
        for (const sql of DbManager.DDL) {
          await db.executeSql(sql);
        }
        db.commit();
      } catch (err) {
        db.rollBack();
        const e = err as BusinessError;
        throw new DbError(`建表失败 code=${e.code} message=${e.message}`);
      }
    }
    if (current < 2) {
      // 全新安装（version=0）先跑 v1 DDL 再跑 v2 ALTER，路径成立
      db.beginTransaction();
      try {
        for (const sql of DbManager.DDL_V2) {
          await DbManager.execMigrationSql(db, sql);
        }
        db.commit();
      } catch (err) {
        db.rollBack();
        const e = err as BusinessError;
        throw new DbError(`v2 迁移失败 code=${e.code} message=${e.message}`);
      }
    }
    if (current < 3) {
      db.beginTransaction();
      try {
        for (const sql of DbManager.DDL_V3) {
          await DbManager.execMigrationSql(db, sql);
        }
        db.commit();
      } catch (err) {
        db.rollBack();
        const e = err as BusinessError;
        throw new DbError(`v3 迁移失败 code=${e.code} message=${e.message}`);
      }
    }
    // 后续版本迁移在此追加：if (current < 4) { ... }
    db.version = DB_VERSION;
  }

  /** ResultSet 读取辅助：NULL 安全。 */
  static rsString(rs: relationalStore.ResultSet, column: string): string {
    const i = rs.getColumnIndex(column);
    return rs.isColumnNull(i) ? '' : rs.getString(i);
  }

  static rsLong(rs: relationalStore.ResultSet, column: string): number {
    const i = rs.getColumnIndex(column);
    return rs.isColumnNull(i) ? 0 : rs.getLong(i);
  }

  /** REAL 列（完整度快照等 0~1 小数）读取辅助：NULL 安全。 */
  static rsDouble(rs: relationalStore.ResultSet, column: string): number {
    const i = rs.getColumnIndex(column);
    return rs.isColumnNull(i) ? 0 : rs.getDouble(i);
  }

  static rsBool(rs: relationalStore.ResultSet, column: string): boolean {
    return DbManager.rsLong(rs, column) === 1;
  }

  /**
   * FROZEN 只读红线（技术设计文档 D7-3）：所有写路径前置校验——
   * 目标检查必须仍为 DRAFT，否则抛 DbError（冻结后修改一律走修订版本）。
   */
  static async assertInspectionDraft(db: relationalStore.RdbStore, inspectionId: number): Promise<void> {
    const rs = await db.querySql('SELECT status FROM inspection WHERE id = ?', [inspectionId]);
    let status: string = '';
    if (rs.goToNextRow()) {
      status = DbManager.rsString(rs, 'status');
    }
    rs.close();
    if (status !== InspectionStatus.DRAFT) {
      throw new DbError(`记录不可写（status=${status}）：冻结后不可修改，请创建修订版本`);
    }
  }

  /** 仅供测试注入/重置。 */
  static resetForTest(): void {
    DbManager.storePromise = null;
  }
}
