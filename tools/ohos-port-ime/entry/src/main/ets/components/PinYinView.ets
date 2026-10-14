import { KeyStyle } from '../common/styleConfiguration'

@Component
export struct PinYinView {
  @Link inputStyle: KeyStyle
  @StorageLink("pinyin") pinyin: string = ""
  build() {
    Row() {
      if (this.pinyin.length > 0) {
        Stack() {
          Text(this.pinyin)
            .fontColor('#333333')
            .padding({left: 12, right: 12})
            .textAlign(TextAlign.Center)
        }
        .height("100%")
        .borderRadius({topLeft: 4, topRight: 4})
        .backgroundColor('#ffffff')
        .borderColor('#aaaaaa')
        .borderWidth(0.5)
      } else  {
        Stack() {
          Text("")
            .padding({left: 12, right: 12})
            .textAlign(TextAlign.Center)
        }
      }
    }.backgroundColor('#00ffffff')
    .height(this.inputStyle.pinyinBarHeight)
  }
}