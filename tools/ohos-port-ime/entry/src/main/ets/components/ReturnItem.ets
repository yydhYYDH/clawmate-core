import { KeyStyle } from '../common/styleConfiguration'
import { InputHandler } from '../model/KeyboardController'

//返回组件
@Component
export struct ReturnItem {
  @Link inputStyle: KeyStyle

  @Styles pressedStyles() {
    .backgroundColor("#868b95")
  }

  @Styles normalStyles() {
    .backgroundColor("#a8abb7")
  }

  build() {
    Stack() {
      Image($rawfile('return.svg'))
        .width(this.inputStyle.returnPicSize)
        .height(this.inputStyle.returnPicSize)
    }
    .backgroundColor('#a8abb7')
    .width(this.inputStyle.returnButtonWidthType_2) //mxg this.returnWidth
    .borderRadius(4)
    .height(this.inputStyle.basicButtonHeight)
    .shadow({ radius: 1, color: '#76787c', offsetY: 3 })
    .onClick(() => {
      InputHandler.getInstance().sendKeyFunction();
    })
    .stateStyles({
      normal: this.normalStyles, pressed: this.pressedStyles
    })
  }
}