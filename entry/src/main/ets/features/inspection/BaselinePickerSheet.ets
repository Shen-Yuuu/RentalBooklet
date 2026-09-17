import { Inspection } from '../../domain/model/Entities';
import { DateUtil } from '../../common/DateUtil';

/**
 * 退租基线选择半模态（E1，产品文档 §5.6）：列出同房屋已冻结入住报告，
 * 默认勾选最近一次；显示"报告号·冻结日期"。确认/取消由回调交还入口页。
 */
@Component
export struct BaselinePickerSheet {
  candidates: Inspection[] = [];
  houseName: string = '';
  @State selectedId: number = 0;
  onConfirm: (baselineId: number) => void = (baselineId: number) => {};
  onCancel: () => void = () => {};

  aboutToAppear(): void {
    // 默认勾选最近一次入住检查（候选已按 started_at 倒序）
    this.selectedId = this.candidates.length > 0 ? this.candidates[0].id : 0;
  }

  build() {
    Column({ space: 12 }) {
      Text(this.houseName.length > 0 ? `${this.houseName} · 选择入住基线` : '选择入住基线')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .width('100%')

      Text('选择一条已冻结的入住报告作为对比基线，创建后可在"前后对比"页逐项对照。')
        .fontSize(12)
        .opacity(0.6)
        .width('100%')

      List() {
        ForEach(this.candidates, (ins: Inspection) => {
          ListItem() {
            Row({ space: 10 }) {
              Column({ space: 3 }) {
                Text(ins.reportNo.length > 0 ? ins.reportNo : `入住检查 #${ins.id}`)
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                Text(`${DateUtil.formatDateTime(ins.frozenAt)} 冻结`)
                  .fontSize(12)
                  .opacity(0.6)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Text(this.selectedId === ins.id ? '✓' : '')
                .fontSize(16)
                .fontColor($r('app.color.brand'))
                .fontWeight(FontWeight.Bold)
            }
            .width('100%')
            .padding(12)
            .borderRadius(10)
            .border({
              width: this.selectedId === ins.id ? 1.5 : 1,
              color: this.selectedId === ins.id ? $r('app.color.brand') : $r('app.color.divider')
            })
            .backgroundColor(this.selectedId === ins.id ? $r('app.color.brand_light') : Color.Transparent)
            .onClick(() => {
              this.selectedId = ins.id;
            })
          }
        }, (ins: Inspection) => `${ins.id}-${this.selectedId === ins.id}`)
      }
      .width('100%')
      .constraintSize({ maxHeight: 260 })
      .scrollBar(BarState.Auto)

      Row({ space: 10 }) {
        Button('暂不设置')
          .layoutWeight(1)
          .fontSize(14)
          .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
          .onClick(() => {
            this.onCancel();
          })
        Button('确认创建')
          .layoutWeight(2)
          .fontSize(14)
          .backgroundColor($r('app.color.brand'))
          .enabled(this.selectedId > 0)
          .onClick(() => {
            if (this.selectedId > 0) {
              this.onConfirm(this.selectedId);
            }
          })
      }
      .width('100%')
    }
    .padding(16)
    .width('100%')
  }
}
