import { KeyStyle } from '../common/styleConfiguration'
import { InputHandler } from '../model/KeyboardController';

//下拉按钮
@Component
export struct DownMenu {
  @Link inputStyle: KeyStyle

  @StorageLink("promptText") promptText: string = ""; // 搜索关键字 在各个字母点击事件内调用接口

  build() {
    Flex({ justifyContent: FlexAlign.End, alignItems: ItemAlign.Center }) {
      Stack() {

        Image($rawfile('down.svg'))
          .width(this.inputStyle.downMenuPicWidth)
          .height(this.inputStyle.downMenuPicHeight)
          .onClick(() => {
            InputHandler.getInstance().hideKeyboardSelf();
          })
      }
      .width(this.inputStyle.downMenuWidth)
      .borderRadius(4)
      .height('100%')
    }
    .width('100%')
    .height(this.inputStyle.downMenuHeight)
    .padding(1)
    .backgroundColor('#ffffff')
    .borderColor('#76787c')
    .borderWidth(0.5)
  }
}