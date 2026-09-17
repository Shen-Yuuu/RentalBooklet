import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { fileIo as fs, hash } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { DbManager, DbError } from '../db/DbManager';
import { HandoverEntity, House, Inspection, InspectionAggregate, InspectionSummary, ItemEntity, MeterReadingEntity, RecordSummary, RoomEntity } from '../../domain/model/Entities';
import { GuideType, InspectPlan } from '../../domain/model/TemplateModels';
import { InspectionStatus, ItemStatus, PhotoKind } from '../../domain/model/CoreEnums';
import { CompletenessInput, CompItem, CompMeter, CompPhoto, CompRoom } from '../../domain/completeness/CompletenessEngine';
import { InspectionStateMachine } from '../../domain/statemachine/InspectionStateMachine';
import { ManifestBuilder, ManifestFile } from '../../domain/manifest/ManifestBuilder';
import { TemplateEngine } from '../../domain/template/TemplateEngine';
import { ManifestRepo } from './ManifestRepo';
import { PhotoRepo } from './PhotoRepo';

const T_INSPECTION: string = 'inspection';
const T_ROOM: string = 'room';
const T_ITEM: string = 'check_item';

/** 全量进度子查询：total/done 两列挂在 inspection 行上。 */
const SUMMARY_SQL: string = `SELECT i.*,
  (SELECT COUNT(*) FROM check_item ci JOIN room r ON ci.room_id = r.id WHERE r.inspection_id = i.id) AS total_items,
  (SELECT COUNT(*) FROM check_item ci JOIN room r ON ci.room_id = r.id
     WHERE r.inspection_id = i.id AND ci.status != '${ItemStatus.PENDING}') AS done_items
  FROM inspection i`;

export class InspectionRepo {
  private ctx: common.UIAbilityContext;

  constructor(ctx: common.UIAbilityContext) {
    this.ctx = ctx;
  }

  private static rowToInspection(rs: relationalStore.ResultSet): Inspection {
    const ins = new Inspection();
    ins.id = DbManager.rsLong(rs, 'id');
    ins.houseId = DbManager.rsLong(rs, 'house_id');
    ins.sceneKey = DbManager.rsString(rs, 'scene_key');
    ins.status = DbManager.rsString(rs, 'status') as InspectionStatus;
    ins.baselineInspectionId = DbManager.rsLong(rs, 'baseline_inspection_id');
    ins.parentRevisionId = DbManager.rsLong(rs, 'parent_revision_id');
    ins.revisionNo = DbManager.rsLong(rs, 'revision_no');
    ins.reportNo = DbManager.rsString(rs, 'report_no');
    ins.startedAt = DbManager.rsLong(rs, 'started_at');
    ins.frozenAt = DbManager.rsLong(rs, 'frozen_at');
    ins.participants = DbManager.rsString(rs, 'participants');
    ins.extraNote = DbManager.rsString(rs, 'extra_note');
    ins.completeRequired = DbManager.rsDouble(rs, 'complete_required');
    ins.completeSuggested = DbManager.rsDouble(rs, 'complete_suggested');
    ins.pdfSha256 = DbManager.rsString(rs, 'pdf_sha256');
    return ins;
  }

  private static rowToRoom(rs: relationalStore.ResultSet): RoomEntity {
    const room = new RoomEntity();
    room.id = DbManager.rsLong(rs, 'id');
    room.inspectionId = DbManager.rsLong(rs, 'inspection_id');
    room.templateKey = DbManager.rsString(rs, 'template_key');
    room.name = DbManager.rsString(rs, 'name');
    room.sort = DbManager.rsLong(rs, 'sort');
    return room;
  }

  private static rowToItem(rs: relationalStore.ResultSet): ItemEntity {
    const item = new ItemEntity();
    item.id = DbManager.rsLong(rs, 'id');
    item.roomId = DbManager.rsLong(rs, 'room_id');
    item.templateKey = DbManager.rsString(rs, 'template_key');
    item.name = DbManager.rsString(rs, 'name');
    item.sort = DbManager.rsLong(rs, 'sort');
    item.required = DbManager.rsBool(rs, 'required');
    item.guide = DbManager.rsString(rs, 'guide') as GuideType;
    item.status = DbManager.rsString(rs, 'status') as ItemStatus;
    item.noteRaw = DbManager.rsString(rs, 'note_raw');
    item.noteSuggestion = DbManager.rsString(rs, 'note_suggestion');
    item.noteFinal = DbManager.rsString(rs, 'note_final');
    item.waiver = DbManager.rsBool(rs, 'waiver');
    item.waiverReason = DbManager.rsString(rs, 'waiver_reason');
    item.updatedAt = DbManager.rsLong(rs, 'updated_at');
    return item;
  }

  /** 模板实例化结果一次性写入 inspection/room/check_item，事务保证完整。baselineInspectionId>0 时写入对比基线（E1）。 */
  async createWithPlan(houseId: number, plan: InspectPlan, baselineInspectionId: number = 0): Promise<number> {
    const db = await DbManager.getStore(this.ctx);
    db.beginTransaction();
    try {
      const insBucket: relationalStore.ValuesBucket = {
        'house_id': houseId,
        'scene_key': plan.sceneKey,
        'status': InspectionStatus.DRAFT,
        'baseline_inspection_id': baselineInspectionId > 0 ? baselineInspectionId : null,
        'started_at': plan.startedAt
      };
      const insId = await db.insert(T_INSPECTION, insBucket);
      for (const room of plan.rooms) {
        const roomBucket: relationalStore.ValuesBucket = {
          'inspection_id': insId,
          'template_key': room.key,
          'name': room.name,
          'sort': room.sort
        };
        const roomId = await db.insert(T_ROOM, roomBucket);
        for (const item of room.items) {
          const itemBucket: relationalStore.ValuesBucket = {
            'room_id': roomId,
            'template_key': item.key,
            'name': item.name,
            'sort': item.sort,
            'required': item.required ? 1 : 0,
            'guide': item.guide,
            'status': ItemStatus.PENDING
          };
          await db.insert(T_ITEM, itemBucket);
        }
      }
      db.commit();
      return insId;
    } catch (err) {
      db.rollBack();
      const e = err as BusinessError;
      throw new Error(`检查会话创建失败 code=${e.code} message=${e.message}`);
    }
  }

  async getById(id: number): Promise<Inspection | null> {
    const db = await DbManager.getStore(this.ctx);
    try {
      const rs = await db.querySql('SELECT * FROM inspection WHERE id = ?', [id]);
      const ins: Inspection | null = rs.goToNextRow() ? InspectionRepo.rowToInspection(rs) : null;
      rs.close();
      return ins;
    } catch (err) {
      const e = err as BusinessError;
      throw new Error(`检查记录查询失败 code=${e.code}`);
    }
  }

  /** 基线候选（E1）：同房屋同场景的已冻结检查（退租创建时选入住基线），最近在前。 */
  async listFrozenByHouse(houseId: number, sceneKey: string): Promise<Inspection[]> {
    const db = await DbManager.getStore(this.ctx);
    try {
      const rs = await db.querySql(
        'SELECT * FROM inspection WHERE house_id = ? AND scene_key = ? AND status = ? ORDER BY started_at DESC, id DESC',
        [houseId, sceneKey, InspectionStatus.FROZEN]);
      const list: Inspection[] = [];
      while (rs.goToNextRow()) {
        list.push(InspectionRepo.rowToInspection(rs));
      }
      rs.close();
      return list;
    } catch (err) {
      const e = err as BusinessError;
      throw new Error(`基线候选查询失败 code=${e.code}`);
    }
  }

  async listByHouse(houseId: number): Promise<InspectionSummary[]> {
    const db = await DbManager.getStore(this.ctx);
    try {
      const rs = await db.querySql(`${SUMMARY_SQL} WHERE i.house_id = ? ORDER BY i.started_at DESC`, [houseId]);
      const list: InspectionSummary[] = [];
      while (rs.goToNextRow()) {
        const s = new InspectionSummary();
        s.inspection = InspectionRepo.rowToInspection(rs);
        s.totalItems = DbManager.rsLong(rs, 'total_items');
        s.doneItems = DbManager.rsLong(rs, 'done_items');
        list.push(s);
      }
      rs.close();
      return list;
    } catch (err) {
      const e = err as BusinessError;
      throw new Error(`检查记录列表失败 code=${e.code}`);
    }
  }

  /** 记录 Tab 跨房屋列表：JOIN house 取房屋简称，按开始时间倒序。 */
  async listSummaries(): Promise<RecordSummary[]> {
    const db = await DbManager.getStore(this.ctx);
    try {
      const rs = await db.querySql(
        `SELECT i.id, i.scene_key, i.status, i.report_no, i.revision_no, i.baseline_inspection_id, i.started_at, i.frozen_at,
           h.name AS house_name,
           (SELECT COUNT(*) FROM check_item ci JOIN room r ON ci.room_id = r.id WHERE r.inspection_id = i.id) AS total_items,
           (SELECT COUNT(*) FROM check_item ci JOIN room r ON ci.room_id = r.id
              WHERE r.inspection_id = i.id AND ci.status != '${ItemStatus.PENDING}') AS done_items
         FROM inspection i JOIN house h ON i.house_id = h.id
         ORDER BY i.started_at DESC`);
      const list: RecordSummary[] = [];
      while (rs.goToNextRow()) {
        const s = new RecordSummary();
        s.inspectionId = DbManager.rsLong(rs, 'id');
        s.houseName = DbManager.rsString(rs, 'house_name');
        s.sceneKey = DbManager.rsString(rs, 'scene_key');
        s.status = DbManager.rsString(rs, 'status') as InspectionStatus;
        s.reportNo = DbManager.rsString(rs, 'report_no');
        s.revisionNo = DbManager.rsLong(rs, 'revision_no');
        s.baselineInspectionId = DbManager.rsLong(rs, 'baseline_inspection_id');
        s.startedAt = DbManager.rsLong(rs, 'started_at');
        s.frozenAt = DbManager.rsLong(rs, 'frozen_at');
        s.totalItems = DbManager.rsLong(rs, 'total_items');
        s.doneItems = DbManager.rsLong(rs, 'done_items');
        list.push(s);
      }
      rs.close();
      return list;
    } catch (err) {
      const e = err as BusinessError;
      throw new Error(`检查记录列表失败 code=${e.code}`);
    }
  }

  async countsByHouse(): Promise<Map<number, number>> {
    const db = await DbManager.getStore(this.ctx);
    try {
      const rs = await db.querySql('SELECT house_id, COUNT(*) AS cnt FROM inspection GROUP BY house_id');
      const map = new Map<number, number>();
      while (rs.goToNextRow()) {
        map.set(DbManager.rsLong(rs, 'house_id'), DbManager.rsLong(rs, 'cnt'));
      }
      rs.close();
      return map;
    } catch (err) {
      const e = err as BusinessError;
      throw new Error(`检查计数失败 code=${e.code}`);
    }
  }

  /** 执行页全量加载：记录 + 房间 + 检查项（按路线排序，中断续作入口）。 */
  async getAggregate(inspectionId: number): Promise<InspectionAggregate | null> {
    const db = await DbManager.getStore(this.ctx);
    try {
      const ins = await this.getById(inspectionId);
      if (ins === null) {
        return null;
      }
      const agg = new InspectionAggregate();
      agg.inspection = ins;

      const houseRs = await db.querySql('SELECT * FROM house WHERE id = ?', [ins.houseId]);
      if (houseRs.goToNextRow()) {
        agg.house.name = DbManager.rsString(houseRs, 'name');
        agg.house.layout = DbManager.rsString(houseRs, 'layout');
        agg.house.recordLocation = DbManager.rsBool(houseRs, 'record_location');
      }
      houseRs.close();

      const roomRs = await db.querySql('SELECT * FROM room WHERE inspection_id = ? ORDER BY sort', [inspectionId]);
      while (roomRs.goToNextRow()) {
        agg.rooms.push(InspectionRepo.rowToRoom(roomRs));
      }
      roomRs.close();

      const itemRs = await db.querySql(
        `SELECT ci.* FROM check_item ci JOIN room r ON ci.room_id = r.id
         WHERE r.inspection_id = ? ORDER BY r.sort, ci.sort`, [inspectionId]);
      while (itemRs.goToNextRow()) {
        const item = InspectionRepo.rowToItem(itemRs);
        const list = agg.itemsByRoom.get(item.roomId);
        if (list === undefined) {
          agg.itemsByRoom.set(item.roomId, [item]);
        } else {
          list.push(item);
        }
      }
      itemRs.close();
      return agg;
    } catch (err) {
      const e = err as BusinessError;
      throw new Error(`检查聚合加载失败 code=${e.code}`);
    }
  }

  /** FROZEN 只读红线：检查项写入前校验其所属检查仍为 DRAFT（item → room → inspection）。 */
  private async assertItemMutable(db: relationalStore.RdbStore, itemId: number): Promise<void> {
    const rs = await db.querySql(
      `SELECT i.status FROM inspection i JOIN room r ON r.inspection_id = i.id
        JOIN check_item ci ON ci.room_id = r.id WHERE ci.id = ?`, [itemId]);
    let status: string = '';
    if (rs.goToNextRow()) {
      status = DbManager.rsString(rs, 'status');
    }
    rs.close();
    if (status !== InspectionStatus.DRAFT) {
      throw new DbError(`记录不可写（status=${status}）：冻结后不可修改，请创建修订版本`);
    }
  }

  /** 检查项状态：每次操作即时写库（中断续作基础）。 */
  async updateItemStatus(itemId: number, status: ItemStatus): Promise<void> {
    const db = await DbManager.getStore(this.ctx);
    await this.assertItemMutable(db, itemId);
    const bucket: relationalStore.ValuesBucket = {
      'status': status,
      'updated_at': Date.now()
    };
    const pre = new relationalStore.RdbPredicates(T_ITEM);
    pre.equalTo('id', itemId);
    try {
      await db.update(bucket, pre);
    } catch (err) {
      const e = err as BusinessError;
      throw new Error(`检查项状态写入失败 code=${e.code}`);
    }
  }

  /** 检查项备注：M1 阶段 raw 与 final 同值，M2 语音/中性化后分离。 */
  async updateItemNote(itemId: number, noteRaw: string, noteFinal: string): Promise<void> {
    const db = await DbManager.getStore(this.ctx);
    await this.assertItemMutable(db, itemId);
    const bucket: relationalStore.ValuesBucket = {
      'note_raw': noteRaw,
      'note_final': noteFinal,
      'updated_at': Date.now()
    };
    const pre = new relationalStore.RdbPredicates(T_ITEM);
    pre.equalTo('id', itemId);
    try {
      await db.update(bucket, pre);
    } catch (err) {
      const e = err as BusinessError;
      throw new Error(`检查项备注写入失败 code=${e.code}`);
    }
  }

  /** R4"说明原因通过"：写入豁免标记与原因（完整度页使用）。 */
  async updateItemWaiver(itemId: number, waiver: boolean, reason: string): Promise<void> {
    const db = await DbManager.getStore(this.ctx);
    await this.assertItemMutable(db, itemId);
    const bucket: relationalStore.ValuesBucket = {
      'waiver': waiver ? 1 : 0,
      'waiver_reason': reason.length > 0 ? reason : null,
      'updated_at': Date.now()
    };
    const pre = new relationalStore.RdbPredicates(T_ITEM);
    pre.equalTo('id', itemId);
    try {
      await db.update(bucket, pre);
    } catch (err) {
      const e = err as BusinessError;
      throw new Error(`检查项豁免写入失败 code=${e.code}`);
    }
  }

  /** 完整度 R2 轻量查询：某次检查的全部表读数记录。 */
  async listMeters(inspectionId: number): Promise<MeterReadingEntity[]> {
    const db = await DbManager.getStore(this.ctx);
    try {
      const rs = await db.querySql('SELECT * FROM meter_reading WHERE inspection_id = ?', [inspectionId]);
      const list: MeterReadingEntity[] = [];
      while (rs.goToNextRow()) {
        const m = new MeterReadingEntity();
        m.id = DbManager.rsLong(rs, 'id');
        m.inspectionId = DbManager.rsLong(rs, 'inspection_id');
        m.meterType = DbManager.rsString(rs, 'meter_type');
        m.valueText = DbManager.rsString(rs, 'value_text');
        m.confirmed = DbManager.rsBool(rs, 'confirmed');
        m.naFlag = DbManager.rsBool(rs, 'na_flag');
        m.ocrRawText = DbManager.rsString(rs, 'ocr_raw_text');
        m.ocrConf = DbManager.rsDouble(rs, 'ocr_conf');
        m.photoId = DbManager.rsLong(rs, 'photo_id');
        m.note = DbManager.rsString(rs, 'note');
        list.push(m);
      }
      rs.close();
      return list;
    } catch (err) {
      const e = err as BusinessError;
      throw new Error(`表读数查询失败 code=${e.code}`);
    }
  }

  /** 完整度 R3 轻量查询：某次检查的钥匙门禁交接记录（无则 null）。 */
  async getHandover(inspectionId: number): Promise<HandoverEntity | null> {
    const db = await DbManager.getStore(this.ctx);
    try {
      const rs = await db.querySql('SELECT * FROM handover WHERE inspection_id = ?', [inspectionId]);
      let result: HandoverEntity | null = null;
      if (rs.goToNextRow()) {
        const h = new HandoverEntity();
        h.inspectionId = DbManager.rsLong(rs, 'inspection_id');
        h.keyCount = DbManager.rsLong(rs, 'key_count');
        h.accessCardCount = DbManager.rsLong(rs, 'access_card_count');
        h.confirmed = DbManager.rsBool(rs, 'confirmed');
        h.parkingOrStorage = DbManager.rsString(rs, 'parking_or_storage');
        h.note = DbManager.rsString(rs, 'note');
        result = h;
      }
      rs.close();
      return result;
    } catch (err) {
      const e = err as BusinessError;
      throw new Error(`交接记录查询失败 code=${e.code}`);
    }
  }

  /** PDF 生成后回填校验值（小写 sha256，L9 数据写入项）。 */
  async updatePdfSha256(inspectionId: number, sha256: string): Promise<void> {
    const db = await DbManager.getStore(this.ctx);
    const bucket: relationalStore.ValuesBucket = {
      'pdf_sha256': sha256
    };
    const pre = new relationalStore.RdbPredicates(T_INSPECTION);
    pre.equalTo('id', inspectionId);
    try {
      await db.update(bucket, pre);
    } catch (err) {
      const e = err as BusinessError;
      throw new Error(`PDF 校验值写入失败 code=${e.code}`);
    }
  }

  /**
   * 完整度检查输入装配（ReviewPage / ConfirmSignPage 共用，避免两页重复拼装）。
   * 检查记录不存在时返回 null；模板未知场景回退为"无表具、无交接"。
   */
  async buildCompletenessInput(inspectionId: number): Promise<CompletenessInput | null> {
    const db = await DbManager.getStore(this.ctx);
    const ins = await this.getById(inspectionId);
    if (ins === null) {
      return null;
    }
    try {
      const input = new CompletenessInput();

      const roomRs = await db.querySql('SELECT * FROM room WHERE inspection_id = ? ORDER BY sort', [inspectionId]);
      while (roomRs.goToNextRow()) {
        const cr = new CompRoom();
        cr.id = DbManager.rsLong(roomRs, 'id');
        cr.templateKey = DbManager.rsString(roomRs, 'template_key');
        cr.name = DbManager.rsString(roomRs, 'name');
        input.rooms.push(cr);
      }
      roomRs.close();

      const itemRs = await db.querySql(
        `SELECT ci.* FROM check_item ci JOIN room r ON ci.room_id = r.id
         WHERE r.inspection_id = ? ORDER BY r.sort, ci.sort`, [inspectionId]);
      while (itemRs.goToNextRow()) {
        const ci = new CompItem();
        ci.id = DbManager.rsLong(itemRs, 'id');
        ci.roomId = DbManager.rsLong(itemRs, 'room_id');
        ci.required = DbManager.rsBool(itemRs, 'required');
        ci.status = DbManager.rsString(itemRs, 'status') as ItemStatus;
        ci.noteRaw = DbManager.rsString(itemRs, 'note_raw');
        ci.noteFinal = DbManager.rsString(itemRs, 'note_final');
        ci.noteSuggestion = DbManager.rsString(itemRs, 'note_suggestion');
        ci.waiver = DbManager.rsBool(itemRs, 'waiver');
        input.items.push(ci);
      }
      itemRs.close();

      const photoRs = await db.querySql(
        'SELECT room_id, item_id, kind FROM photo WHERE inspection_id = ?', [inspectionId]);
      while (photoRs.goToNextRow()) {
        const cp = new CompPhoto();
        cp.roomId = DbManager.rsLong(photoRs, 'room_id');
        cp.itemId = DbManager.rsLong(photoRs, 'item_id');
        cp.kind = DbManager.rsString(photoRs, 'kind') as PhotoKind;
        input.photos.push(cp);
      }
      photoRs.close();

      const meterRs = await db.querySql(
        'SELECT meter_type, confirmed, na_flag FROM meter_reading WHERE inspection_id = ?', [inspectionId]);
      while (meterRs.goToNextRow()) {
        const cm = new CompMeter();
        cm.meterType = DbManager.rsString(meterRs, 'meter_type');
        cm.confirmed = DbManager.rsBool(meterRs, 'confirmed');
        cm.naFlag = DbManager.rsBool(meterRs, 'na_flag');
        input.meters.push(cm);
      }
      meterRs.close();

      // 模板配置：custom 等无内置模板场景回退为无表具、无交接
      try {
        const tpl = TemplateEngine.getBuiltin(ins.sceneKey);
        for (const m of tpl.meters) {
          input.meterTypes.push(m);
        }
        input.hasHandover = tpl.handover;
      } catch (err) {
        input.meterTypes = [];
        input.hasHandover = false;
      }
      const handover = await this.getHandover(inspectionId);
      input.handoverConfirmed = handover !== null && handover.confirmed;
      return input;
    } catch (err) {
      const e = err as BusinessError;
      throw new Error(`完整度输入装配失败 code=${e.code}`);
    }
  }

  /**
   * 冻结全流程（技术设计文档 §6.1，L8 一致性核心）：
   * ①状态机守卫（仅 DRAFT）→ ②reportNo 当日序号 → ③照片逐张 SHA-256 回填（幂等，已算跳过）
   * → ④ManifestBuilder.build + ManifestRepo.save（DELETE+INSERT 幂等 + manifest.json 落盘）
   * → ⑤单事务 UPDATE inspection 置 FROZEN（含完整度快照）→ ⑥home_dirty 刷新信号。
   * 任一步失败抛 DbError（带阶段信息）：①~④ 均可安全重跑（幂等），⑤ 为最终提交点。
   */
  async freeze(inspectionId: number, participants: string, extraNote: string,
    requiredRate: number, suggestedRate: number): Promise<void> {
    const db = await DbManager.getStore(this.ctx);

    // ① 状态机守卫：仅 DRAFT 可冻结
    const ins = await this.getById(inspectionId);
    if (ins === null) {
      throw new DbError('冻结失败：检查记录不存在');
    }
    try {
      InspectionStateMachine.assertTransition(ins.status, InspectionStatus.FROZEN);
    } catch (err) {
      throw new DbError(`冻结失败：当前状态为 ${ins.status}，仅草稿可冻结`);
    }

    // ② 报告号：当日已有 RB-YYYYMMDD- 前缀计数 + 1
    const now = Date.now();
    const d = new Date(now);
    const ymd = `${d.getFullYear()}${d.getMonth() + 1 < 10 ? '0' : ''}${d.getMonth() + 1}${d.getDate() < 10 ? '0' : ''}${d.getDate()}`;
    let seq: number = 1;
    try {
      const rs = await db.querySql(
        'SELECT COUNT(*) AS cnt FROM inspection WHERE report_no LIKE ?', [`RB-${ymd}-%`]);
      if (rs.goToNextRow()) {
        seq = DbManager.rsLong(rs, 'cnt') + 1;
      }
      rs.close();
    } catch (err) {
      const e = err as BusinessError;
      throw new DbError(`冻结失败：报告号序号查询失败 code=${e.code}`);
    }
    let reportNo: string = '';
    try {
      reportNo = ManifestBuilder.generateReportNo(ymd, seq);
    } catch (err) {
      throw new DbError('冻结失败：报告号生成失败');
    }

    // ③ 照片哈希回填：跳过已有 sha256（中断重跑只算缺失）
    const photos = await new PhotoRepo(this.ctx).listByInspection(inspectionId);
    const inspDir = ManifestRepo.inspectionDir(this.ctx, inspectionId);
    const files: ManifestFile[] = [];
    for (const p of photos) {
      let bytes: number = 0;
      try {
        const stat = fs.statSync(p.path);
        bytes = stat.size;
      } catch (err) {
        throw new DbError(`冻结失败：照片文件读取失败 ${p.path}`);
      }
      let sha = p.sha256;
      if (sha.length === 0) {
        try {
          // hash.hash 返回大写十六进制（技术文档 D6），存库统一转小写
          sha = (await hash.hash(p.path, 'sha256')).toLowerCase();
        } catch (err) {
          const e = err as BusinessError;
          throw new DbError(`冻结失败：照片哈希计算失败 code=${e.code}`);
        }
        try {
          const bucket: relationalStore.ValuesBucket = { 'sha256': sha };
          const pre = new relationalStore.RdbPredicates('photo');
          pre.equalTo('id', p.id);
          await db.update(bucket, pre);
        } catch (err) {
          const e = err as BusinessError;
          throw new DbError(`冻结失败：照片哈希回填失败 code=${e.code}`);
        }
      }
      const mf = new ManifestFile();
      // photo.path 为绝对路径，relPath 取相对检查目录的 'photos/{文件名}' 形式
      mf.relPath = p.path.startsWith(`${inspDir}/`) ? p.path.substring(inspDir.length + 1) : p.path;
      mf.bytes = bytes;
      mf.sha256 = sha;
      files.push(mf);
    }

    // ④ 构建并保存校验清单（表 + manifest.json，幂等）
    const content = ManifestBuilder.build(reportNo, inspectionId, ins.revisionNo, now, files);
    try {
      await new ManifestRepo(this.ctx).save(inspectionId, ins.revisionNo, content);
    } catch (err) {
      throw new DbError('冻结失败：校验清单写入失败');
    }

    // ⑤ 单事务置 FROZEN（最终提交点：此前所有步骤均可安全重跑）
    db.beginTransaction();
    try {
      const bucket: relationalStore.ValuesBucket = {
        'status': InspectionStatus.FROZEN,
        'frozen_at': now,
        'report_no': reportNo,
        'participants': participants.length > 0 ? participants : null,
        'extra_note': extraNote.length > 0 ? extraNote : null,
        'complete_required': requiredRate,
        'complete_suggested': suggestedRate
      };
      const pre = new relationalStore.RdbPredicates(T_INSPECTION);
      pre.equalTo('id', inspectionId);
      // 谓词同时限定 DRAFT：并发/重入场景下非草稿记录 0 行命中，事务回滚不产生副作用
      pre.equalTo('status', InspectionStatus.DRAFT);
      const rows = await db.update(bucket, pre);
      if (rows === 0) {
        throw new DbError('冻结失败：记录已不在草稿状态（仅 DRAFT 可冻结）');
      }
      db.commit();
    } catch (err) {
      db.rollBack();
      if (err instanceof DbError) {
        throw err;
      }
      const e = err as BusinessError;
      throw new DbError(`冻结失败：状态更新失败 code=${e.code} message=${e.message}`);
    }

    // ⑥ 首页/记录列表刷新信号
    AppStorage.setOrCreate('home_dirty', Date.now());
  }

  /**
   * F3 草稿清理：删除一条进行中草稿及其全部关联数据。
   * 守卫：仅 DRAFT 可删（冻结记录不可删除，数据完整性红线）。
   * 顺序：先递归清沙箱照片目录（失败不阻塞），再单事务内按外键安全序删行，
   * 最后发 home_dirty 刷新信号。
   */
  async deleteDraft(inspectionId: number): Promise<void> {
    const ins = await this.getById(inspectionId);
    if (ins === null) {
      throw new DbError('删除失败：检查记录不存在');
    }
    if (ins.status !== InspectionStatus.DRAFT) {
      throw new DbError('删除失败：仅进行中草稿可删除');
    }
    InspectionRepo.removeDirRecursive(ManifestRepo.inspectionDir(this.ctx, inspectionId));

    const db = await DbManager.getStore(this.ctx);
    db.beginTransaction();
    try {
      await db.executeSql('DELETE FROM compare_result WHERE inspection_id = ?', [inspectionId]);
      await db.executeSql('DELETE FROM meter_reading WHERE inspection_id = ?', [inspectionId]);
      await db.executeSql('DELETE FROM photo WHERE inspection_id = ?', [inspectionId]);
      await db.executeSql('DELETE FROM signature WHERE inspection_id = ?', [inspectionId]);
      await db.executeSql('DELETE FROM manifest WHERE inspection_id = ?', [inspectionId]);
      await db.executeSql('DELETE FROM handover WHERE inspection_id = ?', [inspectionId]);
      await db.executeSql(
        'DELETE FROM check_item WHERE room_id IN (SELECT id FROM room WHERE inspection_id = ?)', [inspectionId]);
      await db.executeSql('DELETE FROM room WHERE inspection_id = ?', [inspectionId]);
      await db.executeSql('DELETE FROM inspection WHERE id = ?', [inspectionId]);
      db.commit();
    } catch (err) {
      db.rollBack();
      const e = err as BusinessError;
      throw new DbError(`草稿删除失败 code=${e.code} message=${e.message}`);
    }
    AppStorage.setOrCreate('home_dirty', Date.now());
  }

  /**
   * 创建修订版本（产品文档 §5.3 / 链路 L10 / 状态机 FROZEN→DRAFT 语义）：
   * 仅 FROZEN 记录可修订。单事务复制 inspection/room/check_item（含状态与备注，
   * 在新版本上继续编辑）；新记录 DRAFT、revision_no+1、parent_revision_id 指向原记录，
   * baseline_inspection_id 原样继承（退租修订仍需对比基线）。
   * 不复制照片/表读数/钥匙交接/对比结果——修订后按 L7→L8 重新采集并重新冻结。
   * 返回新检查 id，调用方直接进入检查执行页。
   */
  async createRevision(originId: number): Promise<number> {
    const db = await DbManager.getStore(this.ctx);
    const origin = await this.getById(originId);
    if (origin === null) {
      throw new DbError('修订失败：原记录不存在');
    }
    try {
      InspectionStateMachine.assertTransition(origin.status, InspectionStatus.DRAFT);
    } catch (err) {
      throw new DbError(`修订失败：仅已冻结记录可修订（当前状态 ${origin.status}）`);
    }

    db.beginTransaction();
    let newId: number = -1;
    try {
      const insBucket: relationalStore.ValuesBucket = {
        'house_id': origin.houseId,
        'scene_key': origin.sceneKey,
        'status': InspectionStatus.DRAFT,
        'baseline_inspection_id': origin.baselineInspectionId > 0 ? origin.baselineInspectionId : null,
        'parent_revision_id': originId,
        'revision_no': origin.revisionNo + 1,
        'started_at': Date.now()
      };
      newId = await db.insert(T_INSPECTION, insBucket);

      const roomRs = await db.querySql('SELECT * FROM room WHERE inspection_id = ? ORDER BY sort', [originId]);
      const rooms: RoomEntity[] = [];
      while (roomRs.goToNextRow()) {
        rooms.push(InspectionRepo.rowToRoom(roomRs));
      }
      roomRs.close();

      for (const room of rooms) {
        const roomBucket: relationalStore.ValuesBucket = {
          'inspection_id': newId,
          'template_key': room.templateKey,
          'name': room.name,
          'sort': room.sort
        };
        const roomId = await db.insert(T_ROOM, roomBucket);

        const itemRs = await db.querySql(
          'SELECT * FROM check_item WHERE room_id = ? ORDER BY sort', [room.id]);
        const items: ItemEntity[] = [];
        while (itemRs.goToNextRow()) {
          items.push(InspectionRepo.rowToItem(itemRs));
        }
        itemRs.close();

        for (const item of items) {
          const itemBucket: relationalStore.ValuesBucket = {
            'room_id': roomId,
            'template_key': item.templateKey,
            'name': item.name,
            'sort': item.sort,
            'required': item.required ? 1 : 0,
            'guide': item.guide,
            'status': item.status,
            'note_raw': item.noteRaw.length > 0 ? item.noteRaw : null,
            'note_suggestion': item.noteSuggestion.length > 0 ? item.noteSuggestion : null,
            'note_final': item.noteFinal.length > 0 ? item.noteFinal : null,
            'waiver': item.waiver ? 1 : 0,
            'waiver_reason': item.waiverReason.length > 0 ? item.waiverReason : null,
            'updated_at': item.updatedAt > 0 ? item.updatedAt : null
          };
          await db.insert(T_ITEM, itemBucket);
        }
      }
      db.commit();
    } catch (err) {
      db.rollBack();
      const e = err as BusinessError;
      throw new DbError(`修订版本创建失败 code=${e.code} message=${e.message}`);
    }
    AppStorage.setOrCreate('home_dirty', Date.now());
    return newId;
  }

  /** 递归删除目录：目录/子项不存在或删除失败均静默（下次清理重试）。 */
  private static removeDirRecursive(dir: string): void {
    try {
      if (!fs.accessSync(dir)) {
        return;
      }
    } catch (err) {
      return;
    }
    try {
      const names = fs.listFileSync(dir);
      for (const name of names) {
        const full = `${dir}/${name}`;
        try {
          const stat = fs.statSync(full);
          if (stat.isDirectory()) {
            InspectionRepo.removeDirRecursive(full);
          } else {
            fs.unlinkSync(full);
          }
        } catch (err) {
          // 单个条目删除失败不阻塞整体清理
        }
      }
      fs.rmdirSync(dir);
    } catch (err) {
      // 目录本身删除失败静默
    }
  }
}
