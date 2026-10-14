import { KeyStyle } from '../common/styleConfiguration'
import { InputHandler } from '../model/KeyboardController'

//空格组件
@Component
export struct SpaceItem {
  @Link inputStyle: KeyStyle
  private spaceWith?: Resource = undefined

  @Styles pressedStyles() {
    .backgroundColor("#AEB3BD")
  }

  @Styles normalStyles() {
    .backgroundColor("#ffffff")
  }

  build() {
    Stack() {
      Text('space')
        .fontSize(this.inputStyle.en_fontSize)
        .fontColor('black')
    }
    .backgroundColor('#ffffff')
    .width(this.spaceWith == null ? this.inputStyle.spaceButtonWidth_2 : this.spaceWith)
    .borderRadius(4)
    .height(this.inputStyle.basicButtonHeight)
    .onClick(() => {
      InputHandler.getInstance().insertText(' ');
    })
    .shadow({ radius: 1, color: '#76787c', offsetY: 3 })
    .stateStyles({
      normal: this.normalStyles, pressed: this.pressedStyles
    })
  }
}