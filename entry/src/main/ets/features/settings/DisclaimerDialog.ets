@Component
export struct DisclaimerDialog {
  onAccept: () => void = () => {};
  onDecline: () => void = () => {};

  build() {
    Column() {
      Column({ space: 16 }) {
        Text('使用须知')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
        Scroll() {
          Column({ space: 12 }) {
            Text('本应用仅帮助您整理和保存房屋状况记录，不构成法律取证、司法鉴定或官方存证工具，也不能判断任何责任归属。')
              .fontSize(14)
            Text('“记录完整度”仅反映本次记录的齐全程度，不代表证据效力。')
              .fontSize(14)
            Text('从相册导入的照片将被明确标记为“从相册导入”，不会伪装成应用内即时拍摄。')
              .fontSize(14)
            Text('文件校验值（SHA-256）仅用于检测文件在生成后是否发生变化，不代表司法鉴定或官方存证。')
              .fontSize(14)
            Text('您的数据保存在本机，不会上传。请以实际需要自行决定如何使用本应用产出的材料。')
              .fontSize(14)
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
        }
        .layoutWeight(1)
        .align(Alignment.Top)
        .scrollBar(BarState.Auto)

        Row({ space: 12 }) {
          Button('暂不使用')
            .layoutWeight(1)
            .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
            .onClick(() => {
              this.onDecline();
            })
          Button('同意并继续')
            .layoutWeight(1)
            .onClick(() => {
              this.onAccept();
            })
        }
        .width('100%')
      }
      .padding(24)
      .backgroundColor($r('app.color.disclaimer_bg'))
      .borderRadius(16)
      .width('100%')
      .height(420)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding(24)
    .backgroundColor($r('app.color.disclaimer_scrim'))
  }
}
