/*
 * Copyright (c) 2024 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF InputStyle KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import inputMethod from '@ohos.inputMethod';
import Log from '../model/Log';
import { BusinessError } from '@ohos.base';
import promptAction from '@ohos.promptAction';

const TAG: string = 'PrivatePreview->';

@Entry
@Component
struct PrivatePreview {
  @State message: string = 'Hello World';
  @State accountText: string = '';
  @State preViewText: string = '';
  @StorageLink('isTextPreviewSupported') isTextPreviewSupported: boolean = true;
  controllerPrivate: TextInputController = new TextInputController();
  controllerPreview: TextInputController = new TextInputController();

  @State imList: inputMethod.InputMethodProperty[] = [];
  @State showImeChooseSheet: boolean = false;
  @StorageLink('currentIME') currentIME: string = '';
  @State isTouched: boolean = false;

  aboutToAppear() {
    this.addLog(`private preview aboutToAppear begin!`);
    inputMethod.getSetting().getAllInputMethods().then(val => {
      this.imList = val;
    });
    const nowIMEInfo = inputMethod.getCurrentInputMethod();
    if (nowIMEInfo != undefined) {
      this.currentIME = nowIMEInfo.label ?? nowIMEInfo.name;
    }
  }

  onPageShow() {
    this.addLog(`private command onPageShow!`);
  }

  addLog(message: string): void {
    Log.showInfo(TAG, `kikaInput-new: ${message}`);
  }

  @Builder
  imeChooseSheet() {
    List({ space: 12 }) {
      ForEach(this.imList, (im: inputMethod.InputMethodProperty) => {
        ListItem() {
          Row({ space: 12 }) {
            Text(im.label ?? im.name)
            Radio({
              group: 'ime',
              value: im.id
            })
              .checked(this.currentIME == im.label || this.currentIME == im.name)
              .onChange(val => {
                if (val) {
                  inputMethod.switchInputMethod(im).then(() => {
                    this.currentIME = im.label ?? im.name;
                    this.showImeChooseSheet = false;
                  })
                    .catch((reason: BusinessError) => {
                      promptAction.showToast({ message: reason.message })
                    })
                }
              })
          }
          .height(56)
          .borderRadius(18)
          .width('100%')
          .padding(12)
          .justifyContent(FlexAlign.SpaceBetween)
          .backgroundColor($r('app.color.start_window_background'))
        }
      })
    }
    .height(500)
    .padding(12)
  }

  build() {
    Column() {
      // Text($r('app.string.Preview_Text'))
      //   .width('100%')
      //   .height(56)
      //   .fontFamily('HarmonyHeiTi-Medium')
      //   .fontSize('16fp')
      //   .fontColor('#182431')
      //   .lineHeight(22)
      //   .fontWeight(500)
      //
      // TextInput({
      //   text: this.preViewText,
      //   placeholder: $r('app.string.Preview_tip'),
      //   controller: this.controllerPreview
      // })
      //   .placeholderFont({ size: 16, weight: 400 })
      //   .width('100%')
      //   .height(56)
      //   .margin(10)
      //   .fontSize(16)
      //   .fontColor('#182431')
      //   .backgroundColor('#FFFFFF')
      //   .border({ width: 1, color: Color.Gray, radius: 18 })
      //   .maxLength(50)
      //   .onChange((value: string) => {
      //     this.addLog('preViewText onChange.');
      //   })
      //   .onSubmit(() => {
      //     this.addLog('preViewText onSubmit.');
      //   })

      Navigation()
        .title("中文输入法")
        .hideToolBar(true)
        .align(Alignment.Start)
        .width('100%').height("56vp")
        .hideBackButton(true)
        .titleMode(NavigationTitleMode.Mini)

      Column({ space: 12 }) {
        Text('输入法管理:')
          .width('100%')
          .height(56)
          .fontFamily('HarmonyHeiTi-Medium')
          .fontSize('16fp')
          .fontColor('#182431')
          .lineHeight(22)
          .fontWeight(500)

        Flex({ justifyContent: FlexAlign.SpaceBetween, alignItems: ItemAlign.Center }) {
          Row() {
            Text('默认输入法')
              .fontSize(16)
              .lineHeight(22)
              .fontWeight(FontWeight.Medium)
              .margin({ left: 8 })
              .textAlign(TextAlign.Start);
          }

          Row() {
            Text(this.currentIME)
              .fontSize(14)
              .lineHeight(19)
              .fontWeight(FontWeight.Regular)
              .fontColor($r('sys.color.ohos_id_color_text_secondary'))
              .margin({ right: 4 })
              .textAlign(TextAlign.End);
            Image($r('app.media.ic_arrow_right'))
              .width(12)
              .height(24)
              .margin({ right: 8 })
              .fillColor($r("sys.color.ohos_id_color_primary"))
              .opacity(2)
          }
        }
        // .height(ComponentConfig.WH_100_100)
        .width("100%")
        .borderRadius(18)
        .backgroundColor(this.isTouched ? '#43777777' : $r('app.color.start_window_background'))
        .onClick(() => {
          this.showImeChooseSheet = true;
        })
        .bindSheet(this.showImeChooseSheet, this.imeChooseSheet, {
          onDisappear: () => this.showImeChooseSheet = false,
          dragBar: false,
          showClose: $r('app.media.ic_public_close'),
          title: {
            title: '选择输入法'
          }
        });
      }
      .margin({ bottom: 48 })

      Text("输入测试：")
        .width('100%')
        .height(56)
        .fontFamily('HarmonyHeiTi-Medium')
        .fontSize('16fp')
        .fontColor('#182431')
        .lineHeight(22)
        .fontWeight(500)

      TextInput({
        text: this.preViewText,
        placeholder: "输入文本",
        controller: this.controllerPreview
      })
        .placeholderFont({ size: 16, weight: 400 })
        .width('100%')
        .height(56)
        .margin(10)
        .fontSize(16)
        .fontColor('#182431')
        .backgroundColor('#FFFFFF')
        .border({ width: 1, color: Color.Gray, radius: 18 })
        .maxLength(50)
        .onChange((value: string) => {
          this.addLog('preViewText onChange.');
        })
        .onSubmit(() => {
          this.addLog('preViewText onSubmit.');
        })
    }
    .width('100%')
    .padding(20)
  }
}