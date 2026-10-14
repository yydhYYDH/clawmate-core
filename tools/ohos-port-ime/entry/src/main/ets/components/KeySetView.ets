import { KeyStyle } from '../common/styleConfiguration'

@Component
export struct KeySetView {
  @Link inputStyle: KeyStyle
  @StorageLink("isNineKey") isNineKey: string = ""
  build() {
    Row() {
      Column() {
        Stack() {
          Image($r('app.media.ic_keyboard'))
            .width(this.inputStyle.downMenuWidth)
            .height(this.inputStyle.downMenuHeight)
            .fillColor(this.isNineKey ? '#333333' : '#0000FF')
            .onClick(() => {
              AppStorage.setOrCreate('isNineKey', false);
              AppStorage.setOrCreate('isKeySet', false);
            })
        }
        .width(this.inputStyle.downMenuWidth)

        Text("拼音26键")
          .fontColor(this.isNineKey ? '#333333' : '#0000FF')
          .fontSize('14fp')
          .margin({ top: '8vp'})
      }

      Column() {
        Stack() {
          Image($r('app.media.ic_keyboard'))
            .width(this.inputStyle.downMenuWidth)
            .height(this.inputStyle.downMenuHeight)
            .fillColor(this.isNineKey ? '#0000FF' : '#333333')
            .onClick(() => {
              AppStorage.setOrCreate('isNineKey', true);
              AppStorage.setOrCreate('isKeySet', false);
            })
        }
        .width(this.inputStyle.downMenuWidth)

        Text("拼音9键")
          .fontColor(this.isNineKey ? '#0000FF' : '#333333')
          .fontSize('14fp')
          .margin({ top: '8vp'})
      }

    }.backgroundColor('#eeeeee')
    .width('100%')
    .height(this.inputStyle.bodyHeight)
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.SpaceEvenly)

  }
}