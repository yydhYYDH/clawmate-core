import { KeyStyle } from '../common/styleConfiguration'
import { InputHandler } from '../model/KeyboardController'

//删除组件
@Component
export struct DeleteItem {
  @Link inputStyle: KeyStyle
  @StorageLink("pinyin") pinyin: string = ""
  @StorageLink('isChinese') isChinese: boolean =  false
  @State isNineKey: boolean = AppStorage.get<boolean>("isNineKey") ?? false

  @Styles pressedStyles() {
    .backgroundColor("#868b95")
  }

  @Styles normalStyles() {
    .backgroundColor("#a8abb7")
  }

  build() {
    Stack() {
      Image($rawfile('delete.svg'))
        .width(this.inputStyle.featurePicSize)
        .height(this.inputStyle.featurePicSize)
    }
    .backgroundColor('#a8abb7')
    .borderRadius(4)
    .onClick(() => {
      InputHandler.getInstance().deleteForward(1, this.pinyin.length > 0);
    })
    .width(this.isNineKey ? this.inputStyle.nineButtonWidth : this.inputStyle.switchButtonWidth)
    .height(this.isNineKey ? this.inputStyle.nineButtonHeight : this.inputStyle.basicButtonHeight)
    .shadow({ radius: 1, color: '#76787c', offsetY: 3 })
    .stateStyles({
      normal: this.normalStyles, pressed: this.pressedStyles
    })
  }
}