import { keySourceListType} from '../model/keyboardKeyData'
import { KeyStyle } from '../common/styleConfiguration'
import { InputHandler } from '../model/KeyboardController'

//有大小写的按键组件
@Component
export struct keyItemNumber {
  private keyValue: keySourceListType = {
    title: "",
    content: "",
    upperContent: ""
  }
  @Link upper: number
  @Link inputStyle: KeyStyle
  @State isChinese: boolean = AppStorage.get<boolean>("isChinese") ?? false

  @Styles pressedStyles() {
    .backgroundColor("#AEB3BD")
  }

  @Styles normalStyles() {
    .backgroundColor("#ffffff")
  }

  build() {
    Flex({ direction: FlexDirection.Column, alignItems: ItemAlign.Center, justifyContent: FlexAlign.Center }) {
      if (this.inputStyle.deviceType == 'phone_landSpace') {
        Stack({ alignContent: Alignment.TopEnd }) {
          Text(this.isChinese ? this.keyValue.upperContent :
              this.upper === 0 ? this.keyValue.content : this.keyValue.upperContent)
            .fontSize(this.inputStyle.en_fontSize)
            .fontColor('#000')
            .fontWeight(FontWeight.Regular)
            .width('100%')
            .height('100%')
            .textAlign(TextAlign.Center)
          Text(this.keyValue.title)
            .fontSize(this.inputStyle.litterNumberFontSize)
            .fontColor('#000')
            .fontWeight(FontWeight.Regular)
            .width('12vp')
            .height('12vp')
            .textAlign(TextAlign.Center)
            .margin({ top: 1, right: 1 })
        }
        .width('100%')
        .height('100%')
      } else {
        Text(this.keyValue.title)
          .fontSize(this.inputStyle.litterNumberFontSize)
          .fontColor('#606060')
          .fontWeight(FontWeight.Regular)
          .margin({ top: 4 })
        Text(this.isChinese ? this.keyValue.upperContent :
            this.upper === 0 ? this.keyValue.content : this.keyValue.upperContent)
          .fontSize(this.inputStyle.en_fontSize)
          .fontColor('#000')
          .fontWeight(FontWeight.Regular)
      }
    }
    .backgroundColor('#ffffff')
    .borderRadius(4)
    .onClick(() => {
      if (this.upper === 0) {
        InputHandler.getInstance().insertText(this.keyValue.content,this.isChinese);
      } else {
        if (this.upper === 1) {
          this.upper = 0
        }
        InputHandler.getInstance().insertText(this.keyValue.upperContent);
      }
    })
    .width(this.inputStyle.basicButtonWidth)
    .height('100%')
    .shadow({ radius: 1, color: '#76787c', offsetY: 3 })
    .stateStyles({
      normal: this.normalStyles, pressed: this.pressedStyles
    })
  }
}