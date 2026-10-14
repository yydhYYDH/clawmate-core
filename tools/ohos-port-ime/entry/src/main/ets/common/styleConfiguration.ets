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

export interface KeyStyle {
  deviceType?: string,
  basicButtonWidth: Resource,
  basicButtonHeight: Resource,
  featurePicSize: Resource,
  switchButtonWidth: Resource,
  returnPicSize: Resource,
  returnButtonWidthType_1: Resource,
  returnButtonWidthType_2: Resource,
  spaceButtonWidth_1: Resource,
  spaceButtonWidth_2: Resource,
  paddingTop: Resource,
  paddingLeftRight: Resource,
  downMenuHeight: Resource,
  downMenuPicWidth: Resource,
  downMenuPicHeight: Resource,
  downMenuWidth: Resource,
  litterNumberFontSize: Resource,
  en_fontSize: Resource,
  symbol_fontSize: Resource,
  switchNumberFontSize: Resource,
  switchNumberFontSize_g: Resource,
  number1234ontFSize?: Resource,
  chineseCandidateHeight: Resource,
  nineButtonWidth: Resource,
  nineButtonHeight: Resource,
  pinyinBarHeight: Resource,
  keyboardHeight: Resource,
  bodyHeight: Resource,
  editDriverLeft: Resource
}

export class StyleConfiguration {
  static getInputStyle(islandSpace: boolean, isRkDevice: boolean, deviceType: string): KeyStyle {
    if (isRkDevice) {
      return {
        basicButtonWidth: $r("app.float.rk_basic_button_width"),
        basicButtonHeight: $r("app.float.rk_basic_button_height"),
        featurePicSize: $r("app.float.rk_feature_picSize"),
        switchButtonWidth: $r("app.float.rk_switch_button_width"),
        returnPicSize: $r("app.float.rk_return_picSize"),
        returnButtonWidthType_1: $r("app.float.rk_return_button_widthType_1"),
        returnButtonWidthType_2: $r("app.float.rk_return_button_widthType_2"),
        spaceButtonWidth_1: $r("app.float.rk_space_button_width_1"),
        spaceButtonWidth_2: $r("app.float.rk_space_button_width_2"),
        paddingTop: $r("app.float.rk_padding_top"),
        paddingLeftRight: $r("app.float.rk_padding_left_right"),
        downMenuHeight: $r("app.float.rk_downMenu_height"),
        downMenuPicWidth: $r("app.float.rk_downMenu_pic_width"),
        downMenuPicHeight: $r("app.float.rk_downMenu_pic_height"),
        downMenuWidth: $r("app.float.rk_downMenu_width"),
        litterNumberFontSize: $r("app.float.rk_litter_number_fontSize"),
        en_fontSize: $r("app.float.rk_en_fontSize"),
        symbol_fontSize: $r("app.float.rk_en_fontSize"),
        switchNumberFontSize: $r("app.float.rk_switch_number_fontSize"),
        switchNumberFontSize_g: $r("app.float.rk_switch_number_fontSize_g"),
        number1234ontFSize: $r("app.float.rk_number_1234_fontSize"),
        chineseCandidateHeight: $r("app.float.rk_chinese_candidate_height"),
        nineButtonWidth: $r("app.float.rk_basic_button_width"),
        nineButtonHeight: $r("app.float.rk_basic_button_height"),
        pinyinBarHeight: $r("app.float.rk_feature_picSize"),
        bodyHeight: $r("app.float.rk_body_height"),
        keyboardHeight: $r("app.float.rk_keyboard_height"),
        editDriverLeft: $r('app.float.rk_edit_driver_left')
      }
    } else if(deviceType == 'tablet') {
      if (islandSpace) {
        return {
          deviceType: 'tablet_landSpace',
          basicButtonWidth: $r("app.float.landSpace_basic_button_width"),
          basicButtonHeight: $r("app.float.landSpace_basic_button_height"),
          featurePicSize: $r("app.float.landSpace_feature_picSize"),
          switchButtonWidth: $r("app.float.landSpace_switch_button_width"),
          returnPicSize: $r("app.float.landSpace_return_picSize"),
          returnButtonWidthType_1: $r("app.float.landSpace_return_button_widthType_1"),
          returnButtonWidthType_2: $r("app.float.landSpace_return_button_widthType_2"),
          spaceButtonWidth_1: $r("app.float.landSpace_space_button_width_1"),
          spaceButtonWidth_2: $r("app.float.landSpace_space_button_width_2"),
          paddingTop: $r("app.float.landSpace_padding_top"),
          paddingLeftRight: $r("app.float.landSpace_padding_left_right"),
          downMenuHeight: $r("app.float.landSpace_downMenu_height"),
          downMenuPicWidth: $r("app.float.landSpace_downMenu_pic_width"),
          downMenuPicHeight: $r("app.float.landSpace_downMenu_pic_height"),
          downMenuWidth: $r("app.float.landSpace_downMenu_width"),
          litterNumberFontSize: $r("app.float.landSpace_litter_number_fontSize"),
          en_fontSize: $r("app.float.landSpace_en_fontSize"),
          symbol_fontSize: $r("app.float.landSpace_symbol_fontSize"),
          switchNumberFontSize: $r("app.float.landSpace_switch_number_fontSize"),
          switchNumberFontSize_g: $r("app.float.landSpace_switch_number_fontSize_g"),
          chineseCandidateHeight: $r("app.float.landSpace_chinese_candidate_height"),
          nineButtonWidth: $r("app.float.landSpace_nine_button_width"),
          nineButtonHeight: $r("app.float.landSpace_nine_button_height"),
          pinyinBarHeight: $r("app.float.rk_feature_picSize"),
          bodyHeight: $r("app.float.landSpace_body_height"),
          keyboardHeight: $r("app.float.landSpace_keyboard_height"),
          editDriverLeft: $r('app.float.rk_edit_driver_left')
        }
      } else {
        return {
          deviceType: 'tablet_portrait',
          basicButtonWidth: $r("app.float.portrait_basic_button_width"),
          basicButtonHeight: $r("app.float.portrait_basic_button_height"),
          featurePicSize: $r("app.float.portrait_feature_picSize"),
          switchButtonWidth: $r("app.float.portrait_switch_button_width"),
          returnPicSize: $r("app.float.portrait_return_picSize"),
          returnButtonWidthType_1: $r("app.float.portrait_return_button_widthType_1"),
          returnButtonWidthType_2: $r("app.float.portrait_return_button_widthType_2"),
          spaceButtonWidth_1: $r("app.float.portrait_space_button_width_1"),
          spaceButtonWidth_2: $r("app.float.portrait_space_button_width_2"),
          paddingTop: $r("app.float.portrait_padding_top"),
          paddingLeftRight: $r("app.float.portrait_padding_left_right"),
          downMenuHeight: $r("app.float.portrait_downMenu_height"),
          downMenuPicWidth: $r("app.float.portrait_downMenu_pic_width"),
          downMenuPicHeight: $r("app.float.portrait_downMenu_pic_height"),
          downMenuWidth: $r("app.float.portrait_downMenu_width"),
          litterNumberFontSize: $r("app.float.portrait_litter_number_fontSize"),
          en_fontSize: $r("app.float.portrait_en_fontSize"),
          symbol_fontSize: $r("app.float.landSpace_symbol_fontSize"),
          switchNumberFontSize: $r("app.float.portrait_switch_number_fontSize"),
          switchNumberFontSize_g: $r("app.float.portrait_switch_number_fontSize_g"),
          chineseCandidateHeight: $r("app.float.portrait_chinese_candidate_height"),
          nineButtonWidth: $r("app.float.portrait_nine_button_width"),
          nineButtonHeight: $r("app.float.portrait_nine_button_height"),
          pinyinBarHeight: $r("app.float.rk_feature_picSize"),
          bodyHeight: $r("app.float.portrait_body_height"),
          keyboardHeight: $r("app.float.portrait_keyboard_height"),
          editDriverLeft: $r('app.float.rk_edit_driver_left')
        }
      }
    }
    else {
      if (!islandSpace) {
        return {
          basicButtonWidth: $r("app.float.s_basic_button_width"),
          basicButtonHeight: $r("app.float.s_basic_button_height"),
          featurePicSize: $r("app.float.s_feature_picSize"),
          switchButtonWidth: $r("app.float.s_switch_button_width"),
          returnPicSize: $r("app.float.return_picSize"),
          returnButtonWidthType_1: $r("app.float.s_return_button_widthType_1"),
          returnButtonWidthType_2: $r("app.float.s_return_button_widthType_2"),
          spaceButtonWidth_1: $r("app.float.s_space_button_width_1"),
          spaceButtonWidth_2: $r("app.float.s_space_button_width_2"),
          paddingTop: $r("app.float.s_padding_top"),
          paddingLeftRight: $r("app.float.s_padding_left_right"),
          downMenuHeight: $r("app.float.downMenu_height"),
          downMenuPicWidth: $r("app.float.downMenu_pic_width"),
          downMenuPicHeight: $r("app.float.downMenu_pic_height"),
          downMenuWidth: $r("app.float.downMenu_width"),
          litterNumberFontSize: $r("app.float.litter_number_fontSize"),
          en_fontSize: $r("app.float.en_fontSize"),
          symbol_fontSize: $r("app.float.en_fontSize"),
          switchNumberFontSize: $r("app.float.switch_number_fontSize"),
          switchNumberFontSize_g: $r("app.float.switch_number_fontSize_g"),
          number1234ontFSize: $r("app.float.number_1234_fontSize"),
          chineseCandidateHeight: $r("app.float.chinese_candidate_height"),
          nineButtonWidth: $r("app.float.s_nine_button_width"),
          nineButtonHeight: $r("app.float.s_nine_button_height"),
          pinyinBarHeight: $r("app.float.rk_feature_picSize"),
          bodyHeight: $r("app.float.body_height"),
          keyboardHeight: $r("app.float.keyboard_height"),
          editDriverLeft: $r('app.float.s_edit_driver_left')
        }
      } else {
        return {
          basicButtonWidth: $r("app.float.h_basic_button_width"),
          basicButtonHeight: $r("app.float.h_basic_button_height"),
          featurePicSize: $r("app.float.h_feature_picSize"),
          switchButtonWidth: $r("app.float.h_switch_button_width"),
          returnPicSize: $r("app.float.return_picSize"),
          returnButtonWidthType_1: $r("app.float.h_return_button_widthType_1"),
          returnButtonWidthType_2: $r("app.float.h_return_button_widthType_2"),
          spaceButtonWidth_1: $r("app.float.h_space_button_width_1"),
          spaceButtonWidth_2: $r("app.float.h_space_button_width_2"),
          paddingTop: $r("app.float.h_padding_top"),
          paddingLeftRight: $r("app.float.h_padding_left_right"),
          downMenuHeight: $r("app.float.downMenu_height"),
          downMenuPicWidth: $r("app.float.downMenu_pic_width"),
          downMenuPicHeight: $r("app.float.downMenu_pic_height"),
          downMenuWidth: $r("app.float.downMenu_width"),
          litterNumberFontSize: $r("app.float.litter_number_fontSize"),
          en_fontSize: $r("app.float.en_fontSize"),
          symbol_fontSize: $r("app.float.en_fontSize"),
          switchNumberFontSize: $r("app.float.switch_number_fontSize"),
          switchNumberFontSize_g: $r("app.float.switch_number_fontSize_g"),
          number1234ontFSize: $r("app.float.number_1234_fontSize"),
          chineseCandidateHeight: $r("app.float.chinese_candidate_height"),
          nineButtonWidth: $r("app.float.h_nine_button_width"),
          nineButtonHeight: $r("app.float.h_nine_button_height"),
          pinyinBarHeight: $r("app.float.rk_feature_picSize"),
          bodyHeight: $r("app.float.body_height"),
          keyboardHeight: $r("app.float.keyboard_height"),
          editDriverLeft: $r('app.float.s_edit_driver_left')
        }
      }

    }
  }
}