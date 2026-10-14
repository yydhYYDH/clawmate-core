// 大写九宫格的按键组件

import { keyNineChinaType } from '../model/keyboardKeyData'
import { KeyStyle } from '../common/styleConfiguration'
import { InputHandler } from '../model/KeyboardController'

@Component
export struct KeyNineItem {
  @Link inputStyle: KeyStyle
  private keyValue: keyNineChinaType = {
    title: "",
    content: ""
  }
  @StorageLink("isUpper") upper: number = 0;
  @StorageLink("isChinese") isChinese: boolean = true;
  @State keyBgc: string = "#fff"
  @State keyFontColor: string = "#000"
  @State handlePopup: boolean = false
  @State isCurrentTouch: boolean = false

  @Styles pressedStyles() {
    .backgroundColor("#eee")
  }

  @Styles normalStyles() {
    .backgroundColor("#fff")
  }

  build() {
    Stack() {
      Flex({ direction: FlexDirection.Column,
        alignItems: ItemAlign.Center, justifyContent: FlexAlign.Start }) {
        Text(this.keyValue.content).fontSize(10).fontColor('#888').margin({ top: '2vp', bottom: '6vp' })
        Text(this.keyValue.title).fontSize(16)
      }.onClick((_) => {
        InputHandler.getInstance().insertText(this.keyValue.content, this.isChinese);
      })
    }
    .stateStyles({
      normal: this.normalStyles, pressed: this.pressedStyles
    })
    .borderRadius(6)
    .width("20%")
    .height(this.inputStyle.nineButtonHeight)
    .onTouch((event: TouchEvent) => {

    })
  }
}