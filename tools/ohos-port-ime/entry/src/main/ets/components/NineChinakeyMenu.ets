
import { keyNineChinaType } from '../model/keyboardKeyData'
import { DeleteItem } from './DeleteItem'
import { keyItemGray } from './KeyItemGray'
import { KeyNineItem } from './KeyNineItem'
import { KeyStyle } from '../common/styleConfiguration'

// 九宫格中文键盘
@Component
export struct NineChinaKeyMenu {
  @Link inputStyle: KeyStyle
  private keyList: keyNineChinaType[] = []
  @StorageLink("isUpper") isUpper: boolean = false;
  @StorageLink("isChinese") isChinese: boolean = true;
  @State isNineKey: boolean = AppStorage.get<boolean>("isNineKey") ?? false
  @State handlePopup: boolean = false
  @State symbolColor: string = "#a8abb7"
  @Link switchScreen: boolean
  @Link menuType: number

  @Styles pressedStyles() {
    .backgroundColor("#eee")
  }

  @Styles normalStyles() {
    .backgroundColor("#fff")
  }

  build() {
    Flex({ direction: FlexDirection.Column, alignItems: ItemAlign.Center, justifyContent: FlexAlign.SpaceBetween }) {
      Flex({ justifyContent: FlexAlign.SpaceBetween }) {
        keyItemGray({ keyValue: '？', menuType: $menuType, inputStyle: $inputStyle })
        ForEach(this.keyList.slice(0, 3), (item: keyNineChinaType) => {
          KeyNineItem({
            keyValue: item, inputStyle: $inputStyle
          })
        }, (item: keyNineChinaType) => item.content)
        DeleteItem({ inputStyle: $inputStyle })
      }
      .width("96%")
      .height(this.inputStyle.nineButtonHeight)

      Flex({ justifyContent: FlexAlign.SpaceBetween }) {
        keyItemGray({ keyValue: '！', menuType: $menuType, inputStyle: $inputStyle })
        ForEach(this.keyList.slice(3, 6), (item: keyNineChinaType) => {
          KeyNineItem({
            keyValue: item, inputStyle: $inputStyle
          })
        }, (item: keyNineChinaType) => item.content)

        Stack() {
          Text("清空").fontSize(16)
        }
        .backgroundColor(this.symbolColor)
        .borderRadius(4)
        .width(this.inputStyle.nineButtonWidth)
        .height(this.inputStyle.nineButtonHeight)
        .shadow({ radius: 1, color: '#76787c', offsetY: 3 })
        .onTouch((event: TouchEvent) => {
        })
      }
      .width("96%")
      .height(this.inputStyle.nineButtonHeight)

      Flex({ justifyContent: FlexAlign.SpaceBetween }) {
        keyItemGray({ keyValue: '，', menuType: $menuType, inputStyle: $inputStyle })
        ForEach(this.keyList.slice(6, 9), (item: keyNineChinaType) => {
          KeyNineItem({
            keyValue: item, inputStyle: $inputStyle
          })
        }, (item: keyNineChinaType) => item.content)

        keyItemGray({ keyValue: '。', menuType: $menuType, inputStyle: $inputStyle })
      }
      .width("96%")
      .height(this.inputStyle.nineButtonHeight)

      Flex({ justifyContent: FlexAlign.SpaceBetween }) {
        keyItemGray({ keyValue: '符号', menuType: $menuType, inputStyle: $inputStyle })

        Stack() {
          Text("中/英").fontSize(16)
        }
        .stateStyles({
          normal: this.normalStyles, pressed: this.pressedStyles
        })
        .borderRadius(6)
        .width("20%")
        .height(this.inputStyle.nineButtonHeight)
        .onTouch((event: TouchEvent) => {

        })

        KeyNineItem({
          keyValue: this.keyList[9], inputStyle: $inputStyle
        })

        Stack() {
          Text("123").fontSize(16)
        }
        .stateStyles({
          normal: this.normalStyles, pressed: this.pressedStyles
        })
        .borderRadius(6)
        .width("20%")
        .height(this.inputStyle.nineButtonHeight)
        .onTouch((event: TouchEvent) => {

        })

        Stack() {
          Text("完成").fontSize(16)
        }
        .backgroundColor(this.symbolColor)
        .borderRadius(4)
        .width(this.inputStyle.nineButtonWidth)
        .height(this.inputStyle.nineButtonHeight)
        .shadow({ radius: 1, color: '#76787c', offsetY: 3 })
        .onTouch((event: TouchEvent) => {
        })
      }
      .width("96%")
      .height(this.inputStyle.nineButtonHeight)
    }.margin({ top: "4%", bottom: "4%" })
  }
}