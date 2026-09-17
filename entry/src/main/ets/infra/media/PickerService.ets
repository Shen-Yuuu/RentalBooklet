import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { picker, fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';

/** 待导出文件：沙箱内源路径 + 用户目录中的目标文件名。 */
export class ExportFile {
  srcPath: string = '';
  name: string = '';

  constructor(srcPath: string, name: string) {
    this.srcPath = srcPath;
    this.name = name;
  }
}

/** 导出结果：exportedCount=0 表示用户取消。 */
export class ExportOutcome {
  exportedCount: number = 0;
  /** true 表示文件数超限，本次降级仅导出数据库。 */
  degraded: boolean = false;
}

/**
 * 相册导入：系统图库选择器，无需媒体库权限。
 * 导入的照片由调用方强制标记 source=IMPORTED（"从相册导入"）。
 * 数据导出：DocumentViewPicker.save 免权限保存到用户选择目录（应用数据逃生口）。
 */
export class PickerService {
  /** 单次 save 的文件数上限：超出后降级为仅导出数据库，避免选择器过差体验。 */
  static readonly MAX_SAVE_FILES: number = 200;

  static async pickImage(): Promise<string | null> {
    try {
      const picker = new photoAccessHelper.PhotoViewPicker();
      const opts: photoAccessHelper.PhotoSelectOptions = {
        MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE,
        maxSelectNumber: 1
      };
      const result = await picker.select(opts);
      if (result.photoUris.length > 0) {
        return result.photoUris[0];
      }
      return null;
    } catch (err) {
      return null;
    }
  }

  /**
   * 导出全部数据：数据库文件 + filesDir 下所有照片原图/缩略图。
   * 用户取消静默返回 exportedCount=0；IO 错误抛出。
   */
  static async exportAllData(ctx: common.UIAbilityContext, dbPath: string): Promise<ExportOutcome> {
    const files: ExportFile[] = [];

    // 数据库主文件 + WAL/SHM 伴随文件（存在才导出，保证拷贝副本自洽）
    if (fs.accessSync(dbPath)) {
      files.push(new ExportFile(dbPath, PickerService.baseNameOf(dbPath)));
    } else {
      throw new Error('暂无可导出的数据（数据库尚未创建）');
    }
    const walPath = `${dbPath}-wal`;
    if (fs.accessSync(walPath)) {
      files.push(new ExportFile(walPath, `${PickerService.baseNameOf(dbPath)}-wal`));
    }
    const shmPath = `${dbPath}-shm`;
    if (fs.accessSync(shmPath)) {
      files.push(new ExportFile(shmPath, `${PickerService.baseNameOf(dbPath)}-shm`));
    }

    // filesDir 递归收集照片原图/缩略图，目录分隔符压平为下划线保证文件名唯一
    const photoFiles: ExportFile[] = [];
    PickerService.collectFiles(ctx.filesDir, '', photoFiles);

    const outcome = new ExportOutcome();
    if (files.length + photoFiles.length > PickerService.MAX_SAVE_FILES) {
      outcome.degraded = true;
    } else {
      for (const f of photoFiles) {
        files.push(f);
      }
    }

    outcome.exportedCount = await PickerService.exportFiles(ctx, files);
    return outcome;
  }

  /**
   * 逐文件导出到用户选择目录（DocumentViewPicker.save，免权限）。
   * 返回导出文件数；0 表示用户取消。文件数与保存结果不一致时抛错。
   */
  static async exportFiles(ctx: common.UIAbilityContext, files: ExportFile[]): Promise<number> {
    if (files.length === 0) {
      throw new Error('没有可导出的文件');
    }
    const names: string[] = [];
    for (const f of files) {
      names.push(f.name);
    }
    const uris = await PickerService.saveAs(names, ctx);
    if (uris.length === 0) {
      return 0; // 用户取消
    }
    if (uris.length !== files.length) {
      throw new Error(`保存文件数与预期不一致（${uris.length}/${files.length}）`);
    }
    for (let i = 0; i < files.length; i++) {
      const dst = fs.openSync(uris[i], fs.OpenMode.READ_WRITE);
      try {
        fs.copyFileSync(files[i].srcPath, dst.fd);
      } finally {
        fs.closeSync(dst);
      }
    }
    return files.length;
  }

  /** 拉起系统保存选择器（免权限），用户取消返回空数组。 */
  private static async saveAs(fileNames: string[], ctx: common.UIAbilityContext): Promise<string[]> {
    try {
      const options = new picker.DocumentSaveOptions();
      options.newFileNames = fileNames;
      const docPicker = new picker.DocumentViewPicker(ctx);
      const uris: string[] = await docPicker.save(options);
      return uris;
    } catch (err) {
      const e = err as BusinessError;
      throw new Error(`文件保存选择失败 code=${e.code} message=${e.message}`);
    }
  }

  /** 递归收集目录下全部文件；rel 为压平后的相对名（目录分隔符 → '_'）。 */
  private static collectFiles(dir: string, rel: string, out: ExportFile[]): void {
    let names: string[] = [];
    try {
      names = fs.listFileSync(dir);
    } catch (err) {
      return; // 目录不存在或不可读，跳过
    }
    for (const n of names) {
      const full = `${dir}/${n}`;
      const childRel = rel.length > 0 ? `${rel}_${n}` : n;
      if (fs.statSync(full).isDirectory()) {
        PickerService.collectFiles(full, childRel, out);
      } else {
        out.push(new ExportFile(full, childRel));
      }
    }
  }

  private static baseNameOf(path: string): string {
    const idx = path.lastIndexOf('/');
    return idx >= 0 ? path.substring(idx + 1) : path;
  }
}
