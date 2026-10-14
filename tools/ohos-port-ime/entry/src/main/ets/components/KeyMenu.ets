import { keySourceListType} from '../model/keyboardKeyData'
import { keyItemNumber } from './KeyItemNumber'
import { DeleteItem } from './DeleteItem'
import { keyItemGray } from './KeyItemGray'
import { keyItem } from './KeyItem'
import { SpaceItem } from './SpaceItem'
import { ChangeItem } from './ChangeItem'
import { ReturnItem } from './ReturnItem'
import { KeyStyle } from '../common/styleConfiguration'

//key键盘
@Component
export struct keyMenu {
  @Link inputStyle: KeyStyle
  private keyList: keySourceListType[] = []
  @State public upper: number= 0
  @Link menuType: number

  @Styles pressedStyles() {
    .backgroundColor("#868b95")
  }

  @Styles normalStyles() {
    .backgroundColor("#a8abb7")
  }

  build() {
    Flex({ direction: FlexDirection.Column,
      alignItems: ItemAlign.Center }) {
      Flex({ justifyContent: FlexAlign.SpaceBetween,
        alignItems: ItemAlign.Center }) {
        ForEach(this.keyList.slice(0, 10), (item: keySourceListType) => {
          keyItemNumber({ keyValue: item, upper: $upper,
            inputStyle: $inputStyle })
        }, (item: keySourceListType) => item.content)
      }
      .width('100%')
      .height(this.inputStyle.basicButtonHeight)
      .margin({ top: this.inputStyle.paddingTop })

      Flex({ justifyContent: FlexAlign.SpaceBetween,
        alignItems: ItemAlign.Center }) {
        Stack() {
        }.width('4%').height(0)

        ForEach(this.keyList.slice(10, 19), (item: keySourceListType) => {
          keyItemNumber({ keyValue: item, upper: $upper,
            inputStyle: $inputStyle })
        }, (item: keySourceListType) => item.content)
        Stack() {
        }.width('4%').height(0)
      }
      .width('100%')
      .height(this.inputStyle.basicButtonHeight)
      .margin({ top: this.inputStyle.paddingTop })

      Flex({ justifyContent: FlexAlign.SpaceBetween,
        alignItems: ItemAlign.Center }) {
        Stack() {
          Image($rawfile(this.upper === 1 ? 'shift light.svg' :
              this.upper === 2 ? 'shift light long.svg' : 'shift.svg'))
            .width(this.inputStyle.featurePicSize)
            .height(this.inputStyle.featurePicSize)
        }
        .backgroundColor('#a8abb7')
        .borderRadius(4)
        .onClick(() => {
          if (this.upper === 0) {
            this.upper = 1
          } else if (this.upper === 1) {
            this.upper = 2
          } else if (this.upper === 2) {
            this.upper = 0
          }
        })
        .height('100%')
        .width(this.inputStyle.switchButtonWidth)
        .shadow({ radius: 1, color: '#76787c', offsetY: 3 })
        .stateStyles({
          normal: this.normalStyles, pressed: this.pressedStyles
        })

        ForEach(this.keyList.slice(19), (item: keySourceListType) => {
          keyItemNumber({ keyValue: item, upper: $upper,
            inputStyle: $inputStyle })
        }, (item: keySourceListType) => item.content)

        DeleteItem({inputStyle: $inputStyle})
      }
      .width('100%')///mxg
      .height(this.inputStyle.basicButtonHeight)
      .margin({ top: this.inputStyle.paddingTop })

      Flex({ justifyContent: FlexAlign.SpaceBetween,
        alignItems: ItemAlign.Center }) {
        keyItemGray({ keyValue: '?123', menuType: $menuType,
          inputStyle: $inputStyle })
        ChangeItem({ keyValue: 'PY', menuType: $menuType,
          inputStyle: $inputStyle })
        keyItem({ keyValue: { content: ',', title: ',', upperContent: ',' },
          color: '#a8abb7', inputStyle: $inputStyle })
        SpaceItem({ inputStyle: $inputStyle })

        keyItem({ keyValue: { content: '.', title: '.', upperContent: '.' },
          color: '#a8abb7', inputStyle: $inputStyle })
        ReturnItem({ inputStyle: $inputStyle })

      }
      .width('100%')
      .height(this.inputStyle.basicButtonHeight)
      .margin({ top: this.inputStyle.paddingTop})

    }
    .width('100%')
    .height('100%')
    .padding({
      left: this.inputStyle.paddingLeftRight,
      right: this.inputStyle.paddingLeftRight
    })
  }
}
