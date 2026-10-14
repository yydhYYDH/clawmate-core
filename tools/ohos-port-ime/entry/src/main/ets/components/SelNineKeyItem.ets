import { KeyStyle } from '../common/styleConfiguration'

//九宫格切换组件
@Component
export struct SelNineKeyItem {
  @Link inputStyle: KeyStyle
  @State isNineKey: boolean = AppStorage.Get<boolean>("isNineKey")

  @Styles pressedStyles() {
    .backgroundColor("#868b95")
  }

  @Styles normalStyles() {
    .backgroundColor("#a8abb7")
  }

  build() {
    Stack() {
      Image($rawfile('key.png'))
        .width(this.inputStyle.featurePicSize)
        .height(this.inputStyle.featurePicSize)
    }
    .backgroundColor('#a8abb7')
    .borderRadius(4)
    .onClick(() => {
      if (this.isNineKey === false) {
        AppStorage.SetOrCreate('isNineKey',true)
      } else {
        AppStorage.SetOrCreate('isNineKey',false)
      }
    })
    .width(this.inputStyle.switchButtonWidth)//inputStyle.switchButtonWidth
    .height(this.inputStyle.basicButtonHeight)
    .shadow({ radius: 1, color: '#76787c', offsetY: 3 })
    .stateStyles({
      normal: this.normalStyles, pressed: this.pressedStyles
    })
  }
}