import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { fileIo as fs, hash } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { DbManager, DbError } from '../db/DbManager';
import { ManifestBuilder } from '../../domain/manifest/ManifestBuilder';

const TABLE: string = 'manifest';

/** 校验复查单文件结果：OK=一致 / CHANGED=哈希不一致 / MISSING=文件缺失。 */
export class VerifyItemResult {
  relPath: string = '';
  status: string = '';
}

/** 校验复查报告：found=false 表示无清单；ok=true 表示全部一致。 */
export class VerifyReport {
  found: boolean = false;
  ok: boolean = false;
  total: number = 0;
  items: VerifyItemResult[] = [];
}

/**
 * 校验清单仓库：manifest 表读写 + manifest.json 文件镜像落盘。
 * 目录规则与照片目录同级（实际存储见 ImagePipeline）：{filesDir}/insp/{inspectionId}/manifest.json。
 */
export class ManifestRepo {
  private ctx: common.UIAbilityContext;

  constructor(ctx: common.UIAbilityContext) {
    this.ctx = ctx;
  }

  /** 某次检查的沙箱根目录（照片/清单的同级父目录）。 */
  static inspectionDir(ctx: common.UIAbilityContext, inspectionId: number): string {
    return `${ctx.filesDir}/insp/${inspectionId}`;
  }

  /**
   * 保存清单：UNIQUE(inspection_id, revision_no) 冲突先 DELETE 再 INSERT（幂等）；
   * 同时把 content 覆盖写入该检查目录 manifest.json。
   */
  async save(inspectionId: number, revisionNo: number, content: string): Promise<void> {
    const db = await DbManager.getStore(this.ctx);
    let generatedAt: number = Date.now();
    try {
      const parsed = ManifestBuilder.parse(content);
      if (parsed.generatedAt > 0) {
        generatedAt = parsed.generatedAt;
      }
    } catch (err) {
      // generatedAt 解析失败时回退为当前时间，不阻塞保存
    }
    try {
      db.beginTransaction();
      const pre = new relationalStore.RdbPredicates(TABLE);
      pre.equalTo('inspection_id', inspectionId).equalTo('revision_no', revisionNo);
      await db.delete(pre);
      const bucket: relationalStore.ValuesBucket = {
        'inspection_id': inspectionId,
        'revision_no': revisionNo,
        'algorithm': ManifestBuilder.ALGORITHM,
        'generated_at': generatedAt,
        'content': content
      };
      await db.insert(TABLE, bucket);
      db.commit();
    } catch (err) {
      db.rollBack();
      const e = err as BusinessError;
      throw new DbError(`校验清单写库失败 code=${e.code} message=${e.message}`);
    }

    const dir = ManifestRepo.inspectionDir(this.ctx, inspectionId);
    try {
      fs.mkdirSync(dir, true);
    } catch (err) {
      // 目录已存在时忽略
    }
    const filePath = `${dir}/manifest.json`;
    try {
      const file = fs.openSync(filePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, content);
      } finally {
        fs.closeSync(file.fd);
      }
    } catch (err) {
      const e = err as BusinessError;
      throw new DbError(`校验清单文件写入失败 code=${e.code} message=${e.message}`);
    }
  }

  /** 读取最新 revision 的清单内容；无记录返回 null。 */
  async latest(inspectionId: number): Promise<string | null> {
    const db = await DbManager.getStore(this.ctx);
    try {
      const rs = await db.querySql(
        'SELECT content FROM manifest WHERE inspection_id = ? ORDER BY revision_no DESC LIMIT 1', [inspectionId]);
      let result: string | null = null;
      if (rs.goToNextRow()) {
        result = DbManager.rsString(rs, 'content');
      }
      rs.close();
      return result;
    } catch (err) {
      const e = err as BusinessError;
      throw new DbError(`校验清单查询失败 code=${e.code}`);
    }
  }

  /**
   * 校验复查（L10）：读最新清单 → 逐文件存在性检查 + SHA-256 重算比对。
   * 措辞红线：结果仅描述"文件是否变化"，不做篡改定性。
   */
  async verify(inspectionId: number): Promise<VerifyReport> {
    const content = await this.latest(inspectionId);
    const report = new VerifyReport();
    if (content === null) {
      return report;
    }
    const manifest = ManifestBuilder.parse(content);
    const baseDir = ManifestRepo.inspectionDir(this.ctx, inspectionId);
    let allOk = true;
    for (const f of manifest.files) {
      const item = new VerifyItemResult();
      item.relPath = f.relPath;
      const fullPath = `${baseDir}/${f.relPath}`;
      let exists = true;
      try {
        fs.accessSync(fullPath);
      } catch (err) {
        exists = false;
      }
      if (!exists) {
        item.status = 'MISSING';
        allOk = false;
      } else {
        const sha = (await hash.hash(fullPath, 'sha256')).toLowerCase();
        if (sha === f.sha256.toLowerCase()) {
          item.status = 'OK';
        } else {
          item.status = 'CHANGED';
          allOk = false;
        }
      }
      report.items.push(item);
    }
    report.found = true;
    report.total = manifest.files.length;
    report.ok = allOk;
    return report;
  }
}
