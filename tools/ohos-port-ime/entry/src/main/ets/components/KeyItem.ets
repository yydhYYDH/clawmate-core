import { keySourceListType} from '../model/keyboardKeyData'
import { KeyStyle } from '../common/styleConfiguration'
import { InputHandler } from '../model/KeyboardController'

//无大小写的按键组件
@Component
export struct keyItem {
  private keyValue: keySourceListType = {
    title: "",
    content: "",
    upperContent: ""
  }
  private color: string = ""
  @Link inputStyle: KeyStyle
  @Styles pressedStyles() {
    .backgroundColor("#AEB3BD")
  }

  @Styles normalStyles() {
    .backgroundColor("#ffffff")
  }

  build() {
    Flex({ direction: FlexDirection.Column, alignItems: ItemAlign.Center, justifyContent: FlexAlign.Center }) {
      Text(this.keyValue.content)
        .fontSize(this.inputStyle.symbol_fontSize)
        .fontColor('#000')
    }
    .backgroundColor('#fff')
    .borderRadius(4)
    .width(this.inputStyle.basicButtonWidth)
    .height('100%')
    .shadow({ radius: 1, color: '#76787c', offsetY: 3 })
    // .padding({ top: '5%', bottom: '5%' })
    .onClick(() => {
      InputHandler.getInstance().insertText(this.keyValue.content);
    })
    .stateStyles({
      normal: this.normalStyles, pressed: this.pressedStyles
    })
  }
}
