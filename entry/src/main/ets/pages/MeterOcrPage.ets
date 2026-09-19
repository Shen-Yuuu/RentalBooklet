import { common } from '@kit.AbilityKit';
import { MeterOcrParam } from '../common/NavParams';
import { MeterReadingEntity, PhotoEntity } from '../domain/model/Entities';
import { InspectionStatus, MeterType, PhotoKind, PhotoSource } from '../domain/model/CoreEnums';
import { InspectionRepo } from '../data/repo/InspectionRepo';
import { MeterRepo } from '../data/repo/MeterRepo';
import { PhotoRepo } from '../data/repo/PhotoRepo';
import { CaptureService } from '../infra/media/CaptureService';
import { PickerService } from '../infra/media/PickerService';
import { ImagePipeline } from '../infra/media/ImagePipeline';
import { OcrService } from '../infra/vision/OcrService';
import { OcrCandidate } from '../domain/vision/OcrCandidateFilter';
import { QualityHeuristics } from '../domain/media/QualityHeuristics';

/**
 * 表读数确认页（产品文档 §5.8，链路 L5）。
 * 确认门闩红线：保存即确认（confirmed=1）；未确认数据绝不落库，绝不进入报告。
 * OCR 候选仅辅助，用户必须点选或手动输入后「确认保存」才写入。
 * FROZEN 记录只读展示，禁拍禁存。
 */
@Builder
export function meterOcrBuilder() {
  MeterOcrPage();
}

@Component
struct MeterOcrPage {
  @State inspectionId: number = 0;
  @State meterType: string = '';
  @State meterTitle: string = '表';
  @State paramError: string = '';
  @State loaded: boolean = false;
  @State frozen: boolean = false;
  @State valueText: string = '';
  @State noteText: string = '';
  @State naFlag: boolean = false;
  @State photoId: number = 0;
  @State photoThumb: string = '';
  @State candidates: OcrCandidate[] = [];
  @State ocrHint: string = '';
  @State ocrRunning: boolean = false;
  @State busy: boolean = false;
  /** 本次会话新建的表盘照片 id（未确认离开时清理，避免孤儿照片计入 manifest 却永不渲染）。 */
  private createdPhotoId: number = 0;
  private savedThisSession: boolean = false;
  private pathStack: NavPathStack = new NavPathStack();
  private ocrRawText: string = '';

  build() {
    NavDestination() {
      if (this.paramError.length > 0) {
        Column({ space: 10 }) {
          Text(this.paramError).fontSize(14).opacity(0.6)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else if (!this.loaded) {
        Column({ space: 10 }) {
          LoadingProgress().width(36).height(36)
          Text('正在加载…').fontSize(13).opacity(0.6)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        Column({ space: 12 }) {
          Text(`${this.meterTitle}读数`)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .width('100%')

          if (this.frozen) {
            Text('该记录已冻结 · 只读')
              .fontSize(12)
              .fontColor($r('app.color.text_ter'))
              .width('100%')
          }

          if (!this.frozen) {
            Row({ space: 8 }) {
              Button('拍摄表盘')
                .layoutWeight(1)
                .fontSize(13)
                .height(36)
                .backgroundColor($r('app.color.brand'))
                .enabled(!this.busy && !this.ocrRunning)
                .onClick(() => {
                  this.acquirePhoto(PhotoSource.CAPTURED);
                })
              Button('从相册导入')
                .layoutWeight(1)
                .fontSize(13)
                .height(36)
                .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
                .enabled(!this.busy && !this.ocrRunning)
                .onClick(() => {
                  this.acquirePhoto(PhotoSource.IMPORTED);
                })
            }
            .width('100%')
          }

          Text('取景引导：将表盘对正拍入，读数窗完整清晰、光线充足、避免反光')
            .fontSize(11)
            .opacity(0.6)
            .width('100%')

          if (this.busy || this.ocrRunning) {
            Row({ space: 8 }) {
              LoadingProgress().width(18).height(18)
              Text(this.ocrRunning ? '正在识别表盘…' : '正在处理照片…')
                .fontSize(12)
                .opacity(0.6)
            }
            .width('100%')
          }

          if (this.photoThumb.length > 0) {
            Image(`file://${this.photoThumb}`)
              .width('100%')
              .height(160)
              .objectFit(ImageFit.Contain)
              .borderRadius(12)
              .backgroundColor($r('app.color.card_bg'))
          }

          if (this.candidates.length > 0) {
            Text('识别候选（点击填入，请核对后保存）')
              .fontSize(12)
              .opacity(0.6)
              .width('100%')
            Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
              ForEach(this.candidates, (c: OcrCandidate) => {
                Text(c.value)
                  .fontSize(14)
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .borderRadius(10)
                  .backgroundColor(this.valueText === c.value ? $r('app.color.brand') : $r('app.color.card_bg'))
                  .fontColor(this.valueText === c.value ? Color.White : $r('app.color.text_pri'))
                  .margin(4)
                  .onClick(() => {
                    this.valueText = c.value;
                  })
              }, (c: OcrCandidate) => c.value)
            }
            .width('100%')
          } else if (this.ocrHint.length > 0) {
            Text(this.ocrHint)
              .fontSize(12)
              .fontColor($r('app.color.warning'))
              .width('100%')
          }

          if (!this.naFlag) {
            TextInput({ placeholder: '读数（必填，请核对表盘原值）', text: this.valueText })
              .enabled(!this.frozen)
              .onChange((value: string) => {
                this.valueText = value;
              })
          }

          TextInput({ placeholder: '备注（选填）', text: this.noteText })
            .enabled(!this.frozen)
            .onChange((value: string) => {
              this.noteText = value;
            })

          if (!this.frozen) {
            Row({ space: 8 }) {
              Checkbox()
                .select(this.naFlag)
                .onChange((value: boolean) => {
                  this.naFlag = value;
                })
              Text('无表具/无法读取')
                .fontSize(14)
                .onClick(() => {
                  this.naFlag = !this.naFlag;
                })
            }
            .width('100%')
          } else if (this.naFlag) {
            Text('已标记：无表具/无法读取')
              .fontSize(12)
              .opacity(0.6)
              .width('100%')
          }

          if (!this.frozen) {
            Button('确认保存')
              .width('100%')
              .backgroundColor($r('app.color.brand'))
              .enabled(this.canSave() && !this.busy && !this.ocrRunning)
              .onClick(() => {
                this.save();
              })
            Text('保存即确认：仅确认后的读数会写入报告')
              .fontSize(11)
              .opacity(0.5)
              .width('100%')
              .textAlign(TextAlign.Center)
          }
        }
        .padding(16)
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.bg_page'))
      }
    }
    .title(`${this.meterTitle}读数确认`)
    .onDisAppear(() => {
      // 未确认即离开：清理本次新建的表盘照片与文件（保存过则跳过）
      if (this.createdPhotoId > 0 && !this.savedThisSession && !this.frozen) {
        const uiCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
        new PhotoRepo(uiCtx).deletePhoto(this.createdPhotoId).catch(() => {
          // 清理失败静默：残留照片不进入报告（无 confirmed 读数引用）
        });
      }
    })
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
      const p = ctx.pathInfo.param as MeterOcrParam | null;
      if (p !== null && p !== undefined && p.inspectionId > 0 && this.isValidType(p.meterType)) {
        this.inspectionId = p.inspectionId;
        this.meterType = p.meterType;
        this.meterTitle = this.titleOf(p.meterType);
        this.load();
      } else {
        this.paramError = '页面参数缺失，请从检查页重新进入';
      }
    })
  }

  private isValidType(t: string): boolean {
    return t === MeterType.WATER || t === MeterType.ELECTRICITY || t === MeterType.GAS;
  }

  private titleOf(t: string): string {
    if (t === MeterType.WATER) {
      return '水表';
    }
    if (t === MeterType.ELECTRICITY) {
      return '电表';
    }
    if (t === MeterType.GAS) {
      return '燃气表';
    }
    return '表';
  }

  /** 已有记录进入：预填现值/备注/无表具标记与关联照片；重新拍照或修改后保存覆盖。 */
  private async load(): Promise<void> {
    try {
      const uiCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const ins = await new InspectionRepo(uiCtx).getById(this.inspectionId);
      if (ins === null) {
        this.paramError = '未找到该检查记录，可能已被删除';
        this.loaded = true;
        return;
      }
      this.frozen = ins.status === InspectionStatus.FROZEN;

      const meter = await new MeterRepo(uiCtx).getByType(this.inspectionId, this.meterType);
      if (meter !== null) {
        this.valueText = meter.valueText;
        this.noteText = meter.note;
        this.naFlag = meter.naFlag;
        this.ocrRawText = meter.ocrRawText;
        this.photoId = meter.photoId;
        if (meter.photoId > 0) {
          const photo = await new PhotoRepo(uiCtx).getById(meter.photoId);
          if (photo !== null) {
            this.photoThumb = photo.thumbPath.length > 0 ? photo.thumbPath : photo.path;
          }
        }
      }
      this.loaded = true;
    } catch (err) {
      this.paramError = '数据加载失败，请从检查页重新进入';
      this.loaded = true;
    }
  }

  /** 拍照或相册导入 → ImagePipeline 入库（kind=METER）→ 自动 OCR。取消则静默返回。 */
  private async acquirePhoto(source: PhotoSource): Promise<void> {
    if (this.frozen || this.busy || this.ocrRunning) {
      return;
    }
    this.busy = true;
    try {
      const uiCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const uri = source === PhotoSource.CAPTURED
        ? await CaptureService.takePhoto(uiCtx)
        : await PickerService.pickImage();
      if (uri === null) {
        return;
      }
      const baseName = `meter_${Date.now()}_${Math.floor(Math.random() * 1000)}`;
      const files = await ImagePipeline.transcode(uiCtx, uri, this.inspectionId, baseName);
      // 重复拍覆盖：删除本次会话上一张未确认的表盘照片（"保留历史可删"以已确认记录为准）
      if (this.createdPhotoId > 0) {
        try {
          await new PhotoRepo(uiCtx).deletePhoto(this.createdPhotoId);
        } catch (ignored) {
        }
        this.createdPhotoId = 0;
      }
      const photo = new PhotoEntity();
      photo.inspectionId = this.inspectionId;
      photo.kind = PhotoKind.METER;
      photo.source = source;
      photo.path = files.originPath;
      photo.thumbPath = files.thumbPath;
      photo.width = files.width;
      photo.height = files.height;
      photo.shotAt = Date.now();
      photo.qualityFlags = QualityHeuristics.qualityFlagFor(files.avgLuma);
      const id = await new PhotoRepo(uiCtx).addPhoto(photo);
      this.createdPhotoId = id;
      this.photoId = id;
      this.photoThumb = files.thumbPath;
      await this.runOcr(files.originPath);
    } catch (err) {
      this.getUIContext().getPromptAction().showToast({ message: (err as Error).message });
    } finally {
      this.busy = false;
    }
  }

  /** OCR 识别：失败/无候选不阻塞，引导手动输入。 */
  private async runOcr(imagePath: string): Promise<void> {
    this.ocrRunning = true;
    this.candidates = [];
    this.ocrHint = '';
    try {
      const list = await OcrService.recognize(imagePath);
      if (list.length === 0) {
        this.ocrHint = '未能识别，请手动输入读数';
      } else {
        this.candidates = list;
        this.ocrRawText = this.joinRaw(list);
      }
    } catch (err) {
      this.ocrHint = (err as Error).message;
    } finally {
      this.ocrRunning = false;
    }
  }

  private joinRaw(list: OcrCandidate[]): string {
    const parts: string[] = [];
    for (const c of list) {
      parts.push(c.value);
    }
    return parts.join(' | ');
  }

  /** 保存门闩：无读数且未勾选无表具时禁用（必填校验）。 */
  private canSave(): boolean {
    if (this.naFlag) {
      return true;
    }
    return this.valueText.trim().length > 0;
  }

  /** 确认保存：confirmed=1 落库（保存即确认），Toast 后返回。 */
  private async save(): Promise<void> {
    if (this.frozen || this.busy || !this.canSave()) {
      return;
    }
    this.busy = true;
    try {
      const uiCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const v = this.valueText.trim();
      await new MeterRepo(uiCtx).upsert(this.inspectionId, this.meterType,
        this.naFlag ? '' : v, this.ocrRawText, null, this.photoId, true, this.naFlag,
        this.noteText.trim());
      this.getUIContext().getPromptAction().showToast({ message: '已保存' });
      this.savedThisSession = true;
      this.pathStack.pop();
    } catch (err) {
      this.getUIContext().getPromptAction().showToast({ message: '保存失败，请重试' });
    } finally {
      this.busy = false;
    }
  }
}
