import { image } from '@kit.ImageKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { QualityHeuristics } from '../../domain/media/QualityHeuristics';

export interface PhotoFiles {
  originPath: string;
  thumbPath: string;
  width: number;
  height: number;
  avgLuma: number;
}

/**
 * 照片入库管线：相机/相册 URI → EXIF 校正 → JPEG 原图 + ≤1280px 缩略图 + 亮度抽样。
 * PDF Kit 只接受 JPEG，因此所有照片统一转码；拍照即时性由"先落盘、后建索引"保证。
 */
export class ImagePipeline {
  static readonly THUMB_MAX_SIDE: number = 1280;

  static ensureDir(dir: string): void {
    try {
      fs.mkdirSync(dir, true);
    } catch (err) {
      const e = err as BusinessError;
      if (e.code !== 13900015) {
        // 13900015: 目录已存在
      }
    }
  }

  static photoDir(ctx: common.UIAbilityContext, inspectionId: number): string {
    return `${ctx.filesDir}/insp/${inspectionId}/photos`;
  }

  /** EXIF Orientation 值转旋转角度。 */
  static angleFor(orientation: string): number {
    switch (orientation) {
      case '3':
        return 180;
      case '6':
        return 90;
      case '8':
        return 270;
      default:
        return 0;
    }
  }

  static async transcode(ctx: common.UIAbilityContext, srcUri: string,
    inspectionId: number, baseName: string): Promise<PhotoFiles> {
    const dir = ImagePipeline.photoDir(ctx, inspectionId);
    ImagePipeline.ensureDir(dir);
    const originPath = `${dir}/${baseName}.jpg`;
    const thumbPath = `${dir}/t_${baseName}.jpg`;

    const srcFile = fs.openSync(srcUri, fs.OpenMode.READ_ONLY);
    let source: image.ImageSource | null = null;
    try {
      source = image.createImageSource(srcFile.fd);
      let orientation = '0';
      try {
        // PropertyKey 枚举重载（字符串重载自 API 11 起废弃）
        orientation = await source.getImageProperty(image.PropertyKey.ORIENTATION);
      } catch (err) {
        // 无 EXIF（如经处理的导入图）按未旋转处理
        orientation = '0';
      }
      const full = await source.createPixelMap();
      const packer = image.createImagePacker();
      let originWritten = false;
      let thumbWritten = false;
      try {
        const angle = ImagePipeline.angleFor(orientation);
        if (angle > 0) {
          await full.rotate(angle);
        }
        const info = await full.getImageInfo();
        const w = info.size.width;
        const h = info.size.height;

        // packToData：packing(PixelMap) 重载自 API 13 起废弃
        const originBuf = await packer.packToData(full, { format: 'image/jpeg', quality: 95 });
        ImagePipeline.writeToFile(originPath, originBuf);
        originWritten = true;

        // 亮度抽样：先缩小到 ≤256px 再读缓冲（原来为 1/64 抽样分配全尺寸 RGBA，
        // 大图内存峰值翻倍易致转码失败）
        const lumaScale = Math.min(1, 256 / Math.max(w, h));
        const small = lumaScale < 1 ? await full.createScaledPixelMap(lumaScale, lumaScale) : full;
        let avgLuma: number = 0;
        try {
          const sInfo = await small.getImageInfo();
          const lumaBuf = new ArrayBuffer(sInfo.size.width * sInfo.size.height * 4);
          await small.readPixelsToBuffer(lumaBuf);
          avgLuma = QualityHeuristics.averageLuma(new Uint8Array(lumaBuf), 2);
        } finally {
          if (small !== full) {
            small.release();
          }
        }

        const scale = Math.min(1, ImagePipeline.THUMB_MAX_SIDE / Math.max(w, h));
        const thumb = scale < 1 ? await full.createScaledPixelMap(scale, scale) : full;
        try {
          const thumbBuf = await packer.packToData(thumb, { format: 'image/jpeg', quality: 70 });
          ImagePipeline.writeToFile(thumbPath, thumbBuf);
          thumbWritten = true;
        } finally {
          if (thumb !== full) {
            thumb.release();
          }
        }

        const files: PhotoFiles = {
          originPath: originPath,
          thumbPath: thumbPath,
          width: w,
          height: h,
          avgLuma: avgLuma
        };
        return files;
      } catch (err) {
        // 中途失败清理已落盘文件：重试文件名随机，残留即永久孤儿（还会被全量导出）
        if (originWritten) {
          try {
            fs.unlinkSync(originPath);
          } catch (ignored) {
          }
        }
        if (thumbWritten) {
          try {
            fs.unlinkSync(thumbPath);
          } catch (ignored) {
          }
        }
        const e = err as BusinessError;
        throw new Error(`照片转码失败 code=${e.code} message=${e.message}`);
      } finally {
        try {
          await packer.release();
        } catch (ignored) {
        }
        full.release();
      }
    } catch (err) {
      if (err instanceof Error && err.message.startsWith('照片转码失败')) {
        throw err;
      }
      const e = err as BusinessError;
      throw new Error(`照片转码失败 code=${e.code} message=${e.message}`);
    } finally {
      fs.closeSync(srcFile.fd);
      if (source !== null) {
        await source.release();
      }
    }
  }

  static writeToFile(path: string, buf: ArrayBuffer): void {
    const dst = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(dst.fd, buf);
    } finally {
      fs.closeSync(dst.fd);
    }
  }
}
