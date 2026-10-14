import { KeyStyle } from '../common/StyleConfiguration'
import { InputHandler } from '../model/KeyboardController'

// 文字选择键盘
@Component
export struct SelectText {
  @Link inputStyle: KeyStyle
  @StorageLink("pinyin") pinyin: string = ""
  /**是否显示所有候选词*/
  @StorageLink("isMoreText") isMoreText: boolean = false
  /**显示候选词开始下标*/
  @StorageLink("candidateStartInx") candidateStartInx: number = 0
  @StorageLink("isKeySet") isKeySet: boolean = false
  @State isChinese: boolean = AppStorage.get<boolean>("isChinese") ?? false
  private scroller: Scroller = new Scroller();

  build() {
    Column() {
      if (this.pinyin.length <= 0) {
        Row() {
          Stack() {
            Image($rawfile('ic_keyboard.png'))
              .width(this.inputStyle.returnPicSize)
              .height(this.inputStyle.returnPicSize)//.fillColor(this.isKeySet ? '#0000FF' : '#333333')
              .onClick(() => {
                AppStorage.SetOrCreate('isKeySet', true);
              })
          }
          .width(this.inputStyle.downMenuWidth)
          .borderRadius(4)
          .height('100%')

          Blank()

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
      } else {
        Flex({
          direction: FlexDirection.Row,
        }) {
          if (this.isMoreText) {
            // 如果显示所有候选词
            Grid(this.scroller) {
              LazyForEach(InputHandler.getInstance().getDataSource(), (item: string, index: number) => {
                GridItem() {
                  Column() {
                    Text(item)
                      .fontSize(this.inputStyle.switchNumberFontSize)
                      .fontColor('#333333')
                      .fontWeight(FontWeight.Regular)
                      .height('100%')
                      .width('100%')
                      .textAlign(TextAlign.Center)
                  }
                  .onClick(() => {
                    AppStorage.setOrCreate('isMoreText', false);
                    InputHandler.getInstance().insertText(item, this.isChinese, true, index);
                  })
                  .height(this.inputStyle.chineseCandidateHeight)
                  .borderColor('#33000000')
                  .borderWidth(0.2)
                }
              }, (item: string) => item)
            }
            .columnsTemplate('1fr 1fr 1fr 1fr 1fr')
            .onScrollIndex((_) => {

            })
            .width('90%')
          }
          else {
            // 如果显示所有候选词 如果显示候选词略缩
            Grid() {
              LazyForEach(InputHandler.getInstance().getDataSource(), (item: string, index: number) => {
                GridItem() {
                  Column({ space: 1 }) {
                    Row() {
                      // 候选词显示
                      if ((index) < 7) {
                        // if (true) {
                        Text(`${(index + 1)}.`)
                          .fontSize(this.inputStyle.switchNumberFontSize)
                          .fontColor('#333333')
                          .fontWeight(FontWeight.Regular)
                          .textAlign(TextAlign.Center)
                      }
                      Text(InputHandler.getInstance().getDataSource().getData(index + this.candidateStartInx))
                        .fontSize(this.inputStyle.switchNumberFontSize)
                        .fontColor('#333333')
                        .fontWeight(FontWeight.Regular)
                        .textAlign(TextAlign.Center)
                    }
                  }
                  .onClick(() => {
                    AppStorage.setOrCreate('isMoreText', false);
                    InputHandler.getInstance().insertText(item, this.isChinese, true, index);
                  })
                  .padding({ left: 10, right: 10 })
                }
              }, (item: string) => item + Date.now()) // 这里需要做到频繁变化下标，所以放弃缓冲
            }
            .padding({ left: 10, right: 10 })
            .columnsGap('2%')
            .rowsGap('2%')
            .rowsTemplate('1fr')
            .onScrollIndex((_) => {

            })
            .width('90%')
          }

          Flex({
            direction: FlexDirection.Column,
            alignItems: ItemAlign.Center,
            justifyContent: FlexAlign.SpaceAround
          }) {

            if (this.isMoreText) {
              Stack() {
                Text("返回")
                  .fontSize(this.inputStyle.switchNumberFontSize)
                  .fontColor('#333333')
                  .fontWeight(FontWeight.Regular)
                  .textAlign(TextAlign.Center)
              }.onClick(() => {
                AppStorage.setOrCreate('isMoreText', false)
              })

              Stack() {
                Image($rawfile('arrow_up.svg'))
                  .width(this.inputStyle.featurePicSize)
                  .height(this.inputStyle.featurePicSize)
              }
              .onClick(() => {
                this.scroller.scrollPage({ next: false })
              })

              Stack() {
                Image($rawfile('arrow_down.svg'))
                  .width(this.inputStyle.featurePicSize)
                  .height(this.inputStyle.featurePicSize)
              }
              .onClick(() => {
                this.scroller.scrollPage({ next: true })
              })

              Stack() {
                Image($rawfile('delete.svg'))
                  .width(this.inputStyle.featurePicSize)
                  .height(this.inputStyle.featurePicSize)
              }
              .onClick(() => {
                InputHandler.getInstance().deleteForward(1, this.pinyin.length > 0);
              })
            } else {
              Stack() {
                Image($r("app.media.next"))
                  .width(this.inputStyle.featurePicSize)
                  .height(this.inputStyle.featurePicSize)
                  .padding(4)
              }.onClick(() => {
                AppStorage.setOrCreate('isMoreText', true)
              })
            }

          }
          .width(this.isMoreText ? '20%' : '10%')
          .backgroundColor(this.isMoreText ? "#eeeeee" : "#ffffff")
        }
        .width('100%')
      }
    }
    .height(this.isMoreText ? this.inputStyle.keyboardHeight : this.inputStyle.downMenuHeight)
    .width('100%')
    .backgroundColor("#ffffff")
    .borderColor('#aaaaaa')
    .borderWidth(0.5)
  }
}