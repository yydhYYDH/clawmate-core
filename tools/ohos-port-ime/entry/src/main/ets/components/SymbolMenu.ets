import { sourceListType } from '../model/keyboardKeyData'
import { DeleteItem } from './DeleteItem'
import { keyItemGray } from './KeyItemGray'
import { keyItem } from './KeyItem'
import { SpaceItem } from './SpaceItem'
import { ReturnItem } from './ReturnItem'
import { KeyStyle } from '../common/styleConfiguration'

//符号键盘
@Component
export struct SymbolMenu {
  @Link inputStyle: KeyStyle
  private symbolList: sourceListType[] = []
  @Link menuType: number

  @Styles pressedStyles() {
    .backgroundColor("#AEB3BD")
  }

  @Styles normalStyles() {
    .backgroundColor("#ffffff")
  }

  build() {
    Flex({ direction: FlexDirection.Column, alignItems: ItemAlign.Center }) {
      Flex({ justifyContent: FlexAlign.SpaceBetween, alignItems: ItemAlign.Center }) {
        ForEach(this.symbolList.slice(0, 10), (item: sourceListType) => {
          keyItem({
            keyValue: { content: item.content, title: item.content, upperContent: item.content },
            color: '#ffffff',
            inputStyle: $inputStyle
          })
        }, (item: sourceListType) => item.content)
      }
      .width('100%')
      .height(this.inputStyle.basicButtonHeight)
      .margin({ top: this.inputStyle.paddingTop })

      Flex({ justifyContent: FlexAlign.SpaceBetween, alignItems: ItemAlign.Center }) {
        ForEach(this.symbolList.slice(10, 20), (item: sourceListType) => {
          keyItem({
            keyValue: { content: item.content, title: item.content, upperContent: item.content },
            color: '#ffffff',
            inputStyle: $inputStyle
          })
        }, (item: sourceListType) => item.content)
      }
      .width('100%')
      .height(this.inputStyle.basicButtonHeight)
      .margin({ top: this.inputStyle.paddingTop })

      Flex({ justifyContent: FlexAlign.SpaceBetween, alignItems: ItemAlign.Center }) {
        keyItemGray({ keyValue: '?123', menuType: $menuType, inputStyle: $inputStyle })
        ForEach(this.symbolList.slice(20), (item: sourceListType) => {
          keyItem({
            keyValue: { content: item.content, title: item.content, upperContent: item.content },
            color: '#ffffff',
            inputStyle: $inputStyle
          })
        }, (item: sourceListType) => item.content)
        DeleteItem({ inputStyle: $inputStyle })
      }
      .width('100%')
      .height(this.inputStyle.basicButtonHeight)
      .margin({ top: this.inputStyle.paddingTop })


      Flex({ justifyContent: FlexAlign.SpaceBetween, alignItems: ItemAlign.Center }) {
        keyItemGray({ keyValue: 'ABC', menuType: $menuType,
          inputStyle: $inputStyle })
        keyItem({ keyValue: { content: '<', title: '<', upperContent: '<' },
          color: '#a8abb7',inputStyle: $inputStyle })
        keyItem({ keyValue: { content: '>', title: '>', upperContent: '>' },
          color: '#a8abb7', inputStyle: $inputStyle })
        Flex({ direction: FlexDirection.Column, alignItems: ItemAlign.Center,
          justifyContent: FlexAlign.Center }) {
          Text('12').fontSize(this.inputStyle.number1234ontFSize).fontColor('black')
          Text('34').fontSize(this.inputStyle.number1234ontFSize).fontColor('black')
        }
        .backgroundColor('#fff')
        .borderRadius(4)
        .width(this.inputStyle.basicButtonWidth)
        .height(this.inputStyle.basicButtonHeight)
        .shadow({ radius: 1, color: '#76787c', offsetY: 3 })
        .stateStyles({
          normal: this.normalStyles, pressed: this.pressedStyles
        })

        SpaceItem({ inputStyle: $inputStyle })
        keyItem({ keyValue: { content: '.', title: '.', upperContent: '.' },
          color: '#a8abb7', inputStyle: $inputStyle })
        ReturnItem({ inputStyle: $inputStyle })
      }
      .width('100%')
      .height(this.inputStyle.basicButtonHeight)
      .margin({ top: this.inputStyle.paddingTop })
    }
    .padding({
      left: this.inputStyle.paddingLeftRight,
      right: this.inputStyle.paddingLeftRight
    })
  }
}