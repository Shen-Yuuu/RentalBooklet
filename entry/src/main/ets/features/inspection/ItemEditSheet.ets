import { common } from '@kit.AbilityKit';
import { ItemStatus } from '../../domain/model/CoreEnums';
import { PhotoSection } from './PhotoSection';
import { SpeechService } from '../../infra/speech/SpeechService';
import { PermissionManager } from '../../infra/permission/PermissionManager';
import { TextRefiner } from '../../domain/refine/TextRefiner';
import { FEATURE_SPEECH_NOTE, PermissionGrant } from '../../domain/permission/PermissionSpec';

/** 检查项编辑半模态：三态标记 + 语音/文字备注（中性化建议）+ 照片区。 */
@Component
export struct ItemEditSheet {
  @Prop itemName: string = '';
  @Prop itemStatus: ItemStatus = ItemStatus.PENDING;
  @Prop initNote: string = '';
  @Prop inspectionId: number = 0;
  @Prop itemId: number = 0;
  @Prop recordLocation: boolean = false;
  /** FROZEN 只读加固：冻结记录禁用一切编辑入口（状态/备注/语音/照片）。 */
  @Prop frozen: boolean = false;
  @State rawText: string = '';
  @State note: string = '';
  @State suggestion: string = '';
  @State recording: boolean = false;
  @State speechError: string = '';
  @State voiceUsed: boolean = false;
  private speech: SpeechService = new SpeechService();
  onStatus: (s: ItemStatus) => void = (s: ItemStatus) => {};
  onSaveNote: (raw: string, final: string) => void = (raw: string, final: string) => {};
  onPhotosChanged: () => void = () => {};

  aboutToAppear(): void {
    this.rawText = this.initNote;
    this.note = this.initNote;
    this.voiceUsed = false;
    this.suggestion = '';
    this.speechError = '';
  }

  build() {
    Column({ space: 12 }) {
      Text(this.itemName)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .width('100%')

      Row({ space: 8 }) {
        this.chip('正常', ItemStatus.OK, $r('app.color.success'))
        this.chip('存在问题', ItemStatus.ISSUE, $r('app.color.warning'))
        this.chip('不适用', ItemStatus.NA, $r('app.color.text_ter'))
        this.chip('未检查', ItemStatus.PENDING, $r('app.color.text_ter'))
      }
      .width('100%')

      PhotoSection({
        itemId: this.itemId,
        inspectionId: this.inspectionId,
        recordLocation: this.recordLocation,
        frozen: this.frozen,
        onPhotosChanged: () => {
          this.onPhotosChanged();
        }
      })

      Text('备注').fontSize(13).opacity(0.7).width('100%')

      if (!this.frozen) {
        Row({ space: 8 }) {
          Button(this.recording ? '● 停止录音' : '🎤 语音描述')
            .layoutWeight(1)
            .fontSize(13)
            .height(36)
            .backgroundColor(this.recording ? $r('app.color.danger') : $r('app.color.brand'))
            .onClick(() => {
              this.toggleRecording();
            })
          Button('中性化改写')
            .layoutWeight(1)
            .fontSize(13)
            .height(36)
            .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
            .enabled(this.note.length > 0)
            .onClick(() => {
              this.computeSuggestion(this.note);
            })
        }
        .width('100%')
      }

      if (this.recording) {
        Text('正在听…说清楚"位置 + 对象 + 现象 + 尺寸"')
          .fontSize(12)
          .fontColor($r('app.color.danger'))
          .width('100%')
      }

      if (this.speechError.length > 0) {
        Text(this.speechError).fontSize(12).fontColor($r('app.color.danger')).width('100%')
      }

      if (this.suggestion.length > 0 && this.suggestion !== this.note) {
        Column({ space: 6 }) {
          Text('AI 仅整理语言，不判断成因与责任。建议表述：')
            .fontSize(11)
            .opacity(0.6)
            .width('100%')
          Text(this.suggestion)
            .fontSize(13)
            .padding(8)
            .borderRadius(8)
            .backgroundColor($r('app.color.card_bg'))
            .width('100%')
          Row({ space: 8 }) {
            Button('采纳建议')
              .layoutWeight(1)
              .height(32)
              .fontSize(13)
              .backgroundColor($r('app.color.success'))
              .onClick(() => {
                this.note = this.suggestion;
                this.suggestion = '';
              })
            Button('忽略')
              .layoutWeight(1)
              .height(32)
              .fontSize(13)
              .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
              .onClick(() => {
                this.suggestion = '';
              })
          }
          .width('100%')
        }
        .width('100%')
      }

      TextArea({ text: this.note, placeholder: '手动输入或语音描述，建议句式：位置 + 对象 + 现象 + 尺寸' })
        .height(88)
        .width('100%')
        .enabled(!this.frozen)
        .onChange((v: string) => {
          this.note = v;
          if (!this.voiceUsed) {
            this.rawText = v;
          }
        })

      if (!this.frozen) {
        Button('保存')
          .width('100%')
          .onClick(() => {
            this.onSaveNote(this.rawText, this.note);
          })
      }
    }
    .padding(16)
    .width('100%')
  }

  @Builder
  chip(label: string, st: ItemStatus, color: ResourceColor) {
    Button(label)
      .fontSize(13)
      .height(32)
      .layoutWeight(1)
      .padding({ left: 4, right: 4 })
      .backgroundColor(this.itemStatus === st ? color : Color.Transparent)
      .fontColor(this.itemStatus === st ? Color.White : $r('app.color.text_sec'))
      .border({ width: 1, color: this.itemStatus === st ? color : $r('app.color.divider'), radius: 16 })
      .enabled(!this.frozen)
      .onClick(() => {
        this.onStatus(st);
      })
  }

  private computeSuggestion(text: string): void {
    if (text.trim().length === 0) {
      return;
    }
    const r = TextRefiner.refine(text);
    this.suggestion = r.changes.length > 0 ? r.refined : '';
    if (r.changes.length === 0) {
      this.speechError = '没有需要改写的表述';
    }
  }

  private async toggleRecording(): Promise<void> {
    if (this.recording) {
      await this.speech.stop();
      this.recording = false;
      this.computeSuggestion(this.rawText);
      return;
    }
    const uiCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const grant = await PermissionManager.requestFeature(uiCtx, FEATURE_SPEECH_NOTE);
    if (grant !== PermissionGrant.GRANTED) {
      this.speechError = '需要麦克风权限用于语音备注，可在设置中开启';
      return;
    }
    try {
      await this.speech.start({
        onPartial: (t: string) => {
          this.note = t;
        },
        onFinal: (t: string) => {
          this.voiceUsed = true;
          this.rawText = t;
          this.note = t;
          this.recording = false;
          this.computeSuggestion(t);
        },
        onError: (m: string) => {
          this.speechError = m;
          this.recording = false;
        }
      });
      this.recording = true;
      this.speechError = '';
      setTimeout(() => {
        if (this.recording) {
          this.toggleRecording();
        }
      }, 60000);
    } catch (err) {
      this.speechError = (err as Error).message;
    }
  }
}
