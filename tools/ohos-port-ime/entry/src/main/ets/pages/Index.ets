/*
 * Copyright (c) 2022 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
import { keySourceListData, numberSourceListData, symbolSourceListData, keySourceListType, sourceListType,
  keyNineChinaType, keyNineChinaData, chineseSourceListData
} from '../model/keyboardKeyData'
import { DownMenu } from '../components/DownMenu'
import { SelectText } from '../components/SelectText'
import { keyMenu } from '../components/KeyMenu'
import { NumberMenu } from '../components/NumberMenu'
import { SymbolMenu } from '../components/SymbolMenu'
import { ChineseKeyMenu } from '../components/ChineseKeyMenu'
import { NineChinaKeyMenu } from '../components/NineChinakeyMenu'
import { PinYinView } from '../components/PinYinView'
import { KeySetView } from '../components/KeySetView'

import deviceInfo from '@ohos.deviceInfo'
import common from '@ohos.app.ability.common';
import { BusinessError } from '@ohos.base'
import { InputHandler } from '../model/KeyboardController'
import { KeyStyle, StyleConfiguration } from '../common/StyleConfiguration'

let deviceType = deviceInfo.deviceType
let TAG: string = 'index->'

getRawFd();

@Entry
@Component
struct Index {
  private ninekeyList: keyNineChinaType[] = keyNineChinaData
  private chineseKeyList: keySourceListType[]= chineseSourceListData
  private keyList: keySourceListType[]= keySourceListData
  private numberList: sourceListType[]= numberSourceListData
  private symbolList: sourceListType[]= symbolSourceListData
  @State menuType: number= 0
  @StorageLink("pinyin") pinyin: string = ""

  @StorageLink("isMoreText") isMoreText: boolean = false
  @StorageLink('isChinese') isChinese: boolean =  false
  @StorageLink('isNineKey') isNineKey: boolean =  false
  @StorageLink("isKeySet") isKeySet: boolean = false
  @State switchScreen: boolean = false;
  @StorageLink('isLandscape') @Watch('change') isLandscape: boolean = false
  @StorageLink('isRkDevice') isRkDevice: boolean = false;
  @StorageLink('inputStyle')  inputStyle: KeyStyle = StyleConfiguration.getInputStyle(this.isLandscape, this.isRkDevice, deviceType);

  aboutToAppear(): void {
  }

  onBackPress(): boolean{
    InputHandler.getInstance().addLog('onBackPress');
    InputHandler.getInstance().destroyPinyin();
    InputHandler.getInstance().hideKeyboardSelf();
    return true;
  }

  change() {
    AppStorage.Set('inputStyle', StyleConfiguration.getInputStyle(this.isLandscape, this.isRkDevice, deviceType))
  }
  build() {
    Stack() {
      Column() {
        PinYinView({ inputStyle: $inputStyle })
        if(this.menuType === 3) {
          SelectText({ inputStyle: $inputStyle })
        } else {
          DownMenu({ inputStyle: $inputStyle })
        }
        if (this.isKeySet === true) {
          KeySetView({ inputStyle: $inputStyle })
        } else if (!this.isMoreText || this.pinyin.length <= 0) {
          Column() {
            if (this.menuType === 0) {
              keyMenu({ keyList: this.keyList, menuType: $menuType, inputStyle: $inputStyle })
            } else if (this.menuType === 1) {
              NumberMenu({ numberList: this.numberList, menuType: $menuType, inputStyle: $inputStyle })
            } else if (this.menuType === 2) {
              SymbolMenu({ symbolList: this.symbolList, menuType: $menuType, inputStyle: $inputStyle })
            } else {
              if (this.isNineKey == true) {
                NineChinaKeyMenu({
                  keyList: this.ninekeyList,
                  switchScreen: $switchScreen, menuType: $menuType,
                  inputStyle: $inputStyle
                })

              } else {
                ChineseKeyMenu({ keyList: this.chineseKeyList, menuType: $menuType,
                  inputStyle: $inputStyle
                })
              }
            }

          }.width('100%')
          .height(this.inputStyle.bodyHeight)
          .backgroundColor('#D5D7DD')
        }
      }.width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }
}

function getRawFd() {
  try {
    InputHandler.getInstance().addLog('getRawFd');
    let context = getContext() as common.UIAbilityContext;
    context.resourceManager.getRawFd("dict_pinyin.dat").then(value => {
      InputHandler.getInstance().initPinyin(value, context.filesDir);
    }).catch((error: BusinessError) => {
    });
  } catch (error) {
  }
}
