import { common } from '@kit.AbilityKit';
import { PhotoEntity } from '../../domain/model/Entities';
import { PhotoKind, PhotoSource } from '../../domain/model/CoreEnums';
import { PhotoRepo } from '../../data/repo/PhotoRepo';
import { CaptureService } from '../../infra/media/CaptureService';
import { PickerService } from '../../infra/media/PickerService';
import { ImagePipeline } from '../../infra/media/ImagePipeline';
import { LocationService } from '../../infra/location/LocationService';
import { QualityHeuristics } from '../../domain/media/QualityHeuristics';
import { PermissionManager } from '../../infra/permission/PermissionManager';
import { FEATURE_PHOTO_LOCATION, PermissionGrant } from '../../domain/permission/PermissionSpec';
import { StorageStat } from '../../common/StorageStat';

/** 检查项照片区：拍全景/细节、相册导入（强制"导入"标记）、缩略图与质量角标。 */
@Component
export struct PhotoSection {
  @Prop @Watch('onItemChanged') itemId: number = 0;
  @Prop inspectionId: number = 0;
  @Prop recordLocation: boolean = false;
  /** FROZEN 只读加固：冻结记录不渲染拍照/导入入口，隐藏删除。 */
  @Prop frozen: boolean = false;
  onPhotosChanged: () => void = () => {};
  @State photos: PhotoEntity[] = [];
  @State busy: boolean = false;
  @State errorText: string = '';
  /** L4 拍前存储预检阈值：剩余不足 20MB 拦截拍摄/导入（异常分支总表）。 */
  static readonly MIN_FREE_BYTES: number = 20 * 1024 * 1024;

  aboutToAppear(): void {
    this.load();
  }

  onItemChanged(): void {
    this.load();
  }

  build() {
    Column({ space: 8 }) {
      if (!this.frozen) {
        Row({ space: 8 }) {
          Button('拍全景照')
            .layoutWeight(1)
            .fontSize(13)
            .height(36)
            .enabled(!this.busy)
            .backgroundColor($r('app.color.brand'))
            .onClick(() => {
              this.take(PhotoKind.PANORAMA);
            })
          Button('拍细节照')
            .layoutWeight(1)
            .fontSize(13)
            .height(36)
            .enabled(!this.busy)
            .backgroundColor($r('app.color.brand'))
            .onClick(() => {
              this.take(PhotoKind.DETAIL);
            })
          Button('相册导入')
            .layoutWeight(1)
            .fontSize(13)
            .height(36)
            .enabled(!this.busy)
            .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
            .onClick(() => {
              this.importPhoto();
            })
        }
        .width('100%')
      }

      if (this.errorText.length > 0) {
        Text(this.errorText).fontSize(12).fontColor($r('app.color.danger')).width('100%')
      }

      if (this.photos.length > 0) {
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
          ForEach(this.photos, (p: PhotoEntity) => {
            Stack({ alignContent: Alignment.TopEnd }) {
              Column({ space: 3 }) {
                Image(`file://${p.thumbPath}`)
                  .width(84)
                  .height(84)
                  .borderRadius(8)
                  .objectFit(ImageFit.Cover)
                Row({ space: 4 }) {
                  Text(p.source === PhotoSource.IMPORTED ? '导入' : PhotoSection.kindLabel(p.kind))
                    .fontSize(10)
                    .fontColor(p.source === PhotoSource.IMPORTED ? $r('app.color.amber') : $r('app.color.text_sec'))
                  if (p.qualityFlags.indexOf('TOO_DARK') >= 0) {
                    Text('偏暗').fontSize(10).fontColor($r('app.color.danger'))
                  }
                }
              }
              if (!this.frozen) {
                Text('×')
                  .fontSize(13)
                  .fontColor(Color.White)
                  .backgroundColor('#CC000000')
                  .borderRadius(9)
                  .width(18)
                  .height(18)
                  .textAlign(TextAlign.Center)
                  .margin(3)
                  .onClick(() => {
                    this.removePhoto(p);
                  })
              }
            }
            .margin(4)
          }, (p: PhotoEntity) => `${p.id}`)
        }
        .width('100%')
      }
    }
    .width('100%')
  }

  private static kindLabel(kind: PhotoKind): string {
    switch (kind) {
      case PhotoKind.PANORAMA:
        return '全景';
      case PhotoKind.METER:
        return '表数';
      case PhotoKind.DOC:
        return '凭证';
      case PhotoKind.SIGN:
        return '签名';
      default:
        return '细节';
    }
  }

  private load(): void {
    if (this.itemId <= 0) {
      return;
    }
    const uiCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    new PhotoRepo(uiCtx).listByItem(this.itemId).then((list: PhotoEntity[]) => {
      this.photos = list;
    });
  }

  private async addPhoto(kind: PhotoKind, source: PhotoSource, uri: string): Promise<void> {
    const uiCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const baseName = `${Date.now()}_${Math.floor(Math.random() * 1000)}`;
    const files = await ImagePipeline.transcode(uiCtx, uri, this.inspectionId, baseName);
    const photo = new PhotoEntity();
    photo.inspectionId = this.inspectionId;
    photo.itemId = this.itemId;
    photo.kind = kind;
    photo.source = source;
    photo.path = files.originPath;
    photo.thumbPath = files.thumbPath;
    photo.width = files.width;
    photo.height = files.height;
    photo.shotAt = Date.now();
    photo.qualityFlags = QualityHeuristics.qualityFlagFor(files.avgLuma);
    if (this.recordLocation) {
      // 位置权限按需申请（FEATURE_PHOTO_LOCATION）；拒绝时不阻塞拍摄，仅本次不记录位置
      const grant = await PermissionManager.requestFeature(uiCtx, FEATURE_PHOTO_LOCATION);
      if (grant === PermissionGrant.GRANTED) {
        const point = await LocationService.currentPoint();
        if (point !== null) {
          photo.location = JSON.stringify(point);
        }
      }
    }
    await new PhotoRepo(uiCtx).addPhoto(photo);
    this.load();
    this.onPhotosChanged();
  }

  /** L4 拍前存储预检：剩余空间不足时拦截（文案见异常分支总表）；查询失败放行。 */
  private async ensureStorage(): Promise<boolean> {
    const uiCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const free = await StorageStat.freeBytes(uiCtx.filesDir);
    if (free >= 0 && free < PhotoSection.MIN_FREE_BYTES) {
      this.errorText = '剩余空间不足，请清理草稿';
      return false;
    }
    return true;
  }

  private async take(kind: PhotoKind): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.errorText = '';
    try {
      if (!(await this.ensureStorage())) {
        return;
      }
      const uiCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const uri = await CaptureService.takePhoto(uiCtx);
      if (uri !== null) {
        await this.addPhoto(kind, PhotoSource.CAPTURED, uri);
      }
    } catch (err) {
      this.errorText = (err as Error).message;
    } finally {
      this.busy = false;
    }
  }

  private async importPhoto(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.errorText = '';
    try {
      if (!(await this.ensureStorage())) {
        return;
      }
      const uri = await PickerService.pickImage();
      if (uri !== null) {
        await this.addPhoto(PhotoKind.DETAIL, PhotoSource.IMPORTED, uri);
      }
    } catch (err) {
      this.errorText = (err as Error).message;
    } finally {
      this.busy = false;
    }
  }

  private async removePhoto(p: PhotoEntity): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    try {
      const uiCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await new PhotoRepo(uiCtx).deletePhoto(p.id);
      this.load();
      this.onPhotosChanged();
    } catch (err) {
      this.errorText = (err as Error).message;
    } finally {
      this.busy = false;
    }
  }
}
