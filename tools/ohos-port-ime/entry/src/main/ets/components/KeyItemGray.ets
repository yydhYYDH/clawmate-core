import { KeyStyle } from '../common/styleConfiguration'

//无大小写的灰色组件
@Component
export struct keyItemGray {
  private keyValue: string = ""
  @Link inputStyle: KeyStyle
  @Link menuType: number

  @State isChinese: boolean = AppStorage.get<boolean>("isChinese") ?? false
  @State isNineKey: boolean = AppStorage.get<boolean>("isNineKey") ?? false
  @State isNineKeyBack: boolean = AppStorage.get<boolean>("isNineKeyBack") ?? false


  @Styles pressedStyles() {
    .backgroundColor("#868b95")
  }

  @Styles normalStyles() {
    .backgroundColor("#a8abb7")
  }

  build() {
    Stack() {
      Text(this.keyValue).fontSize(this.inputStyle.switchNumberFontSize).fontColor('black')
    }
    .backgroundColor('#a8abb7')
    .borderRadius(4)
    .onClick(() => {
      if (this.keyValue === "?123"  || this.keyValue === "#@￥") {
        this.menuType = 1 //数字
        if (this.isNineKey === true && this.keyValue === "#@￥") {
          AppStorage.SetOrCreate('isNineKey',false)
          AppStorage.SetOrCreate('isNineKeyBack',true)
        }
      } else if (this.keyValue === "=/\<") {
        this.menuType = 2 //符号
      } else if (this.keyValue === 'PY') {
        this.menuType = 3 // 拼音
        AppStorage.SetOrCreate('isChinese',true)
      } else if (this.keyValue === 'ABC') {
        if (this.isNineKey === true) {
          AppStorage.SetOrCreate('isNineKey',false)
          AppStorage.SetOrCreate('isNineKeyBack',true)
        }
        AppStorage.SetOrCreate('isChinese',false)
        this.menuType = 0 //英文
      }
      else {
        console.log('may-->000:' + this.menuType)
        if (this.isNineKeyBack === true) {
          AppStorage.SetOrCreate('isNineKey',true)
          AppStorage.SetOrCreate('isNineKeyBack',false)
        }else {
          if (this.isChinese) {
            this.menuType = 3
          } else {
            this.menuType = 0
          }
        }
      }
    })
    .height('100%')
    .width(this.isNineKey ? this.inputStyle.nineButtonWidth : this.inputStyle.switchButtonWidth)
    .shadow({ radius: 1, color: '#76787c', offsetY: 3 })
    .stateStyles({
      normal: this.normalStyles, pressed: this.pressedStyles
    })
  }
}
