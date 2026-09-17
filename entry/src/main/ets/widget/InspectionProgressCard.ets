/**
 * 检查进度卡片（F1，2x2）：
 * - 数据由 FormAbility/主应用通过 formProvider.updateForm 推送，
 *   五个字段经 LocalStorageProp 接收（key 与 WidgetService.CardData 一一对应）；
 * - 点击卡片 postCardAction router 拉起主应用 EntryAbility 并携带 inspectionId 深链；
 * - 卡片页禁止业务 import，仅使用 ArkUI 内建组件与 postCardAction。
 */
let storage = new LocalStorage();

@Entry(storage)
@Component
struct InspectionProgressCard {
  @LocalStorageProp('houseName') houseName: string = '租房留证册';
  @LocalStorageProp('sceneTitle') sceneTitle: string = '';
  @LocalStorageProp('progressText') progressText: string = '正在读取检查进度…';
  @LocalStorageProp('statusText') statusText: string = '';
  @LocalStorageProp('inspectionId') inspectionId: number = 0;

  build() {
    Column() {
      Column({ space: 2 }) {
        Text(this.houseName)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#333333')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.sceneTitle.length > 0) {
          Text(this.sceneTitle)
            .fontSize(11)
            .fontColor('#888888')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')

      Text(this.progressText)
        .fontSize(12)
        .fontColor('#555555')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text(this.statusText)
        .fontSize(11)
        .fontColor('#4A90D9')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .justifyContent(FlexAlign.SpaceBetween)
    .alignItems(HorizontalAlign.Start)
    .padding(12)
    .width('100%')
    .height('100%')
    .onClick(() => {
      const action: Record<string, Object> = {
        'action': 'router',
        'abilityName': 'EntryAbility',
        'params': { 'inspectionId': this.inspectionId } as Record<string, Object>
      };
      postCardAction(this, action);
    })
  }
}
