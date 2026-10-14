import { KeyStyle } from '../common/styleConfiguration'

// 中英文切换
@Component
export struct ChangeItem {
  @Link inputStyle: KeyStyle
  private keyValue: string = ""
  @Link menuType: number
  @StorageLink('isChinese') @Watch('changeisChinese') isChinese: boolean = AppStorage.get<boolean>("isChinese") ?? false

  @Styles
  pressedStyles() {
    .backgroundColor("#868b95")
  }

  @Styles
  normalStyles() {
    .backgroundColor("#a8abb7")
  }

  build() {
    Flex({ direction: FlexDirection.Column, alignItems: ItemAlign.Center, justifyContent: FlexAlign.Center }) {
      if (this.isChinese) {
        Row() {
          Text("中").fontSize(this.inputStyle.switchNumberFontSize).fontColor('black')
          Text("/英").fontSize(this.inputStyle.switchNumberFontSize_g).fontColor('black')
        }
      } else {
        Row() {
          Text("英").fontSize(this.inputStyle.switchNumberFontSize).fontColor('black')
          Text("/中").fontSize(this.inputStyle.switchNumberFontSize_g).fontColor('black')
        }
      }
    }
    .backgroundColor('#a8abb7')
    .borderRadius(6)
    .height(this.inputStyle.basicButtonHeight)
    .width(this.inputStyle.switchButtonWidth) //mxg inputStyle.switchButtonWidth
    .shadow({ radius: 1, color: '#76787c', offsetY: 3 })
    .stateStyles({
      normal: this.normalStyles, pressed: this.pressedStyles
    })

    .onClick(() => {
      if (this.keyValue === 'PY') {
        // this.menuType = 3 // 拼音
        AppStorage.SetOrCreate('isChinese', true)
      } else {
        // this.menuType = 0 //英文
        AppStorage.SetOrCreate('isChinese', false)
      }
    })
  }

  /** 监听中文状态的响应，进行监听 */
  changeisChinese() {
    if (this.keyValue === 'PY') {
      this.menuType = this.isChinese ? 3 : 0
    }
  }
}