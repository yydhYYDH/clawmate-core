/*
 * Copyright (c) 2023-2024 Huawei Device Co., Ltd.
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


import deviceInfo from '@ohos.deviceInfo';
import inputMethodEngine from '@ohos.inputMethodEngine';
import InputMethodExtensionContext from '@ohos.InputMethodExtensionContext';
import display from '@ohos.display';
import Log from './Log';
import { BusinessError } from '@ohos.base';
import { GetHardKeyValue } from './HardKeyUtils';
import { KeyCode } from '@ohos.multimodalInput.keyCode';
import { StyleConfiguration } from '../common/StyleConfiguration';
// import { MessageEvents, worker } from '@kit.ArkTS';
// import { resourceManager } from '@kit.LocalizationKit';
import {
  MessageType,
  PinyinChooseMessage,
  PinyinInitMessage,
  PinyinKeyMessage,
  PinyinMessage,
  PinyinResultMessage,
  PinyinUpdateMessage
} from './PinyinMessage';
import { ChineseDataSource } from './ChineseDataSource';
import worker, { MessageEvents } from '@ohos.worker';
import resourceManager from '@ohos.resourceManager';

interface DeviceSize {
  width: number;
  height: number;
}

interface CursorInfo {
  x: number;
  y: number;
  height: number
}

const previewContent: string = 'hello world';
const InputMethodEngine: inputMethodEngine.InputMethodAbility = inputMethodEngine.getInputMethodAbility();
const TAG: string = 'KeyboardController->';
const isDebug: boolean = false;
// 定义不同设备的宽高，用于键盘显示适配不同设备
const DEVICE_PHONE: DeviceSize = {
  width: 1344,
  height: 2772
}
const DEVICE_RK: DeviceSize = {
  width: 720,
  height: 1280
}
const DEVICE_BIG: DeviceSize = {
  width: 2560,
  height: 1600
}
// 定义键盘在不同设备上占设备高度的比例，用于键盘显示适配不同设备
const KEYBOARD_HEIGHT_RATE_DEFAULT: number = 0.412;
const KEYBOARD_HEIGHT_RATE_PHONE: number = 0.38;
const KEYBOARD_HEIGHT_RATE_PHONE_LAND: number = 0.5;
const KEYBOARD_HEIGHT_RATE_BIG_LAND: number = 0.38;
const KEYBOARD_HEIGHT_RATE_BIG: number = 0.3;
// 定义默认的底部导航栏高度
const NAVIGATIONBAR_HEIGHT_DEFAULT: number = 72;

let KEYCODE_DEL: number = 67

export class InputHandler {
  private mKbController: inputMethodEngine.KeyboardController | undefined;
  private mTextInputClient: inputMethodEngine.InputClient | undefined;
  private mEditorAttribute: inputMethodEngine.EditorAttribute | undefined;
  private cursorInfo: CursorInfo = { x: 0, y: 0, height: 0 };
  private selectInfo: string = '';
  private textInfo: string = '';
  private inputInfo: string = '';
  // private intputText: string = '';

  private dataSource: ChineseDataSource = new ChineseDataSource();
  private workerInstance?: worker.ThreadWorker = undefined;

  private constructor() {
    this.mKbController = undefined;
    this.mTextInputClient = undefined;
    this.mEditorAttribute = undefined;
  }

  public static getInstance(): InputHandler {
    let instance = AppStorage.get<InputHandler>('inputHandler');
    if (instance === undefined) {
      instance = new InputHandler();
      AppStorage.setOrCreate('inputHandler', instance);
    }
    return instance;
  }

  /**初始和系统连接*/
  public onInputStart(kbController: inputMethodEngine.KeyboardController, textInputClient: inputMethodEngine.InputClient): void {
    this.mKbController = kbController;
    this.mTextInputClient = textInputClient;
    let editorAttribute = this.mTextInputClient.getEditorAttribute();
    this.addLog(`onInputStart editorAttribute = ${JSON.stringify(editorAttribute)}`);
    editorAttribute.then((res: inputMethodEngine.EditorAttribute) => {
      this.mEditorAttribute = res;
      AppStorage.setOrCreate('enterKeyType', res.enterKeyType);
      AppStorage.setOrCreate('inputPattern', res.inputPattern);

      // this.setInputInfo('EditorInfo：enterKeyType = ' + this.mEditorAttribute.enterKeyType + ';inputPattern = ' + this.mEditorAttribute.inputPattern +
      //   '; isTextPreviewSupported = ' + this.mEditorAttribute.isTextPreviewSupported);
    })
    // try {
    //   this.addLog(`onInputStart sendPrivateCommand begin`);
    //   let record: Record<string, inputMethodEngine.CommandDataType> = {
    //     'previewTextStyle': 'underline'
    //   };
    //
    //   this.mTextInputClient.sendPrivateCommand(record).then((err) => {
    //     this.addLog(`insertText sendPrivateCommand success`);
    //   }).catch((err:BusinessError) => {
    //     if (err !== undefined) {
    //       let error = err as BusinessError;
    //       this.addLog(`insertText sendPrivateCommand catch error: ${error.code} ${error.message}`);
    //     }
    //   });
    // } catch (err) {
    //   let error = err as BusinessError;
    //   this.addLog(`insertText sendPrivateCommand catch error: ${error.code} ${error.message}`);
    // }
  }

  public hideKeyboardSelf(): void {
    this.addLog('hideKeyboardSelf');
    if (this.mKbController !== undefined) {
      this.mKbController.hide();
    } else {
      this.addLog('hideKeyboardSelf this.mKbController is undefined');
    }
  }

  public sendKeyFunction(): void {
    this.addLog('sendKeyFunction')
    if (this.mTextInputClient && this.mEditorAttribute) {
      this.mTextInputClient.sendKeyFunction(this.mEditorAttribute.enterKeyType);

      //调用结束预上屏接口, 预上屏内容将被系统正式上屏
      // this.mTextInputClient.finishTextPreview().then(() => {
      //   this.addLog('Succeeded in finishing text preview.');
      // }).catch((err: BusinessError) => {
      //   console.error(`Failed to finishTextPreview: ${JSON.stringify(err)}`);
      // });
    } else {
      this.addLog('sendKeyFunction this.mTextInputClient is undefined');
    }
  }

  public deleteBackward(length: number): void {
    this.addLog('deleteBackward');
    if (this.mTextInputClient !== undefined) {
      this.mTextInputClient.deleteBackward(length);
    } else {
      this.addLog('deleteBackward this.mTextInputClient is undefined');
    }
    if (isDebug) {
      this.refreshInfo();
    }
  }

  // 删除光标右侧字符的公共函数
  public deleteForward(length: number, isPinyin: boolean): void {
    // 1. 打印日志：表明函数被调用
    this.addLog('deleteForward');
    // 2. 确保与系统文本框的通信通道已经建立
    if (this.mTextInputClient !== undefined) {
      // 3. 【已注释】原逻辑：直接让系统删除光标右侧 length 个字符
      // this.mTextInputClient.deleteForward(length);

      // 4. 如果当前处于中文拼音输入状态
      if (isPinyin) {
        // 4-1. 把“删除”动作当成一次拼音退格键事件，
        // 交给拼音 Worker 处理，用于撤销拼音字母而非真实文本
        this.onKeyClick('', KEYCODE_DEL);
      } else {
        // 4-2. 普通模式：直接调用系统接口删除光标右侧 length 个字符
        this.mTextInputClient!.deleteForward(length);
      }
    } else {
      // 5. 通信通道未建立，记录错误日志
      this.addLog('deleteForward this.mTextInputClient is undefined');
    }

    // 6. 调试模式下，刷新调试信息（光标、选区、文本等）
    if (isDebug) {
      this.refreshInfo();
    }
  }

  /**
   *
   * @param text 输入文本内容
   * @param isChinese 当前是否正在输入中文拼音
   * @param isSelText 当前是否是在候选栏里“选中”某个候选词
   * @param selNum 当 isSelText=true 时，告诉拼音引擎选中了第几个候选
   */
  public insertText(text: string, isChinese?: boolean, isSelText?: boolean, selNum: number = 0): void {
    this.addLog(`insertText = ${text}`);
    this.addLog('insertText:' + text + '-->isChinese:' + isChinese + '-->isSelText:' + isSelText)

    // 无论发生任何变化候选词下标清零
    setCandidateStartInx(0);

    if (this.mTextInputClient !== undefined) {

      // 需要过滤替换的字符
      const csEns = ',./'.split('')
      let idx = csEns.indexOf(text);
      if (isChinese && !isSelText && idx >= 0) {
        // ps :这个if判断没有经过严整的推演,仅用于解决中文下物理键盘不能输入某些符号的bug

        // 如果是需要替换的标点符号
        const csZns = '，。/'.split('')
        // 需要替换的字符串
        this.mTextInputClient!.insertText(csZns[idx])

      // Literal digits bypass the pinyin decoder; hardware candidate selection is handled above.
      } else if (isChinese && !isSelText && !/^[0-9]+$/.test(text)) {
        this.onKeyClick(text, 0);
      } else if (isSelText) {
        this.chooseCandidate(selNum);
      } else {
        this.mTextInputClient!.insertText(text);

        // let indexCursor: number = 0;
        // indexCursor = this.mTextInputClient.getTextIndexAtCursorSync();
        // this.intputText = this.mTextInputClient.getForwardSync(indexCursor);
        // this.intputText = this.intputText + text;

        // //设置预上屏数据
        // let length = 2;
        // let textPre: string = this.mTextInputClient.getForwardSync(length);
        // this.addLog('insertText textPre:' + textPre);
        //
        // // 取出的内容为当前输入之前的字符，不包含当前的字符,需将当前字符加上
        // textPre = textPre + text;
        // if (textPre == 'hel') {
        //   this.addLog('insertText hel');
        //   try {
        //     //把当前字符计算在内
        //     let endRange: number = indexCursor + 1;
        //     this.addLog('insertText start ' + (indexCursor - length).toString());
        //     this.addLog('insertText end ' + (indexCursor).toString());
        //     let range: inputMethodEngine.Range = { start: indexCursor - length, end: endRange };
        //     this.mTextInputClient.setPreviewText(previewContent, range).then(() => {
        //       this.addLog('insertText preViewText Succeeded in setting preview text.');
        //     }).catch((err: BusinessError) => {
        //       this.addLog(`insertText preViewText Failed to setPreviewText: ${JSON.stringify(err)}`);
        //     });
        //   } catch (err) {
        //     this.addLog(`insertText preViewText Failed to setPreviewText: ${JSON.stringify(err)}`);
        //   }
        // } else if (this.intputText.length > length + 1) {
        //   this.addLog('insertText this.intputText ' + this.intputText);
        //
        //   let indexSubStrStart: number = this.intputText.lastIndexOf('hel');
        //   this.addLog('insertText indexSubStrStart ' + indexSubStrStart.toString());
        //
        //   if (indexSubStrStart >= 0) {
        //     // 当前文本框存在预上屏的部分内容
        //     let subStr: string = this.intputText.substring(indexSubStrStart, indexCursor);
        //     this.addLog('insertText indexSubStrStart subStr ' + subStr);
        //
        //     if((previewContent != subStr) && (previewContent.includes(subStr))) {
        //       // 文本框的子串与预上屏内容吻合，则调用预上屏接口，替换文本框的子串
        //       this.addLog('insertText previewContent indexSubStrStart ' + indexSubStrStart.toString());
        //       this.addLog('insertText previewContent end ' + (indexCursor).toString());
        //       let range: inputMethodEngine.Range = { start: indexSubStrStart, end: indexCursor + 1 };
        //       this.mTextInputClient.setPreviewText(previewContent, range).then(() => {
        //         this.addLog('insertText preViewText Succeeded in setting preview text.');
        //       }).catch((err: BusinessError) => {
        //         this.addLog(`insertText preViewText Failed to setPreviewText: ${JSON.stringify(err)}`);
        //       });
        //     }
        //   }
        // }
      }
    } else {
      this.addLog('insertText this.mTextInputClient is undefined');
    }
    if (isDebug) {
      this.refreshInfo();
    }

  }

  public addLog(message: string): void {
    Log.showInfo(TAG, `kikaInput-js: ${message}`);
  }

  public setCursorInfo(info: CursorInfo): void {
    this.addLog(`setCursorInfo info = ${JSON.stringify(info)}`);
    this.cursorInfo = info;
  }

  // 编写

  public moveCursor(direction: inputMethodEngine.Direction): void {
    if (this.mTextInputClient !== undefined) {
      this.addLog(`moveCursor direction = ${direction}`);
      this.mTextInputClient.moveCursor(direction);
    } else {
      this.addLog('moveCursor this.mTextInputClient is undefined');
    }
  }

  public async moveCursorToBegin(): Promise<void> {
    if (this.mTextInputClient !== undefined) {
      this.mTextInputClient.selectByRange({ start: 0, end: 0 });
    } else {
      this.addLog('moveCursor this.mTextInputClient is undefined');
    }
  }

  public async moveCursorToEnd(): Promise<void> {
    if (this.mTextInputClient !== undefined) {
      this.addLog(`moveCursorToEnd`);
      this.mTextInputClient.selectByRange({ start: 1000, end: 1000 });
    } else {
      this.addLog('moveCursor this.mTextInputClient is undefined');
    }
  }

  public selectByMovement(direction: inputMethodEngine.Direction): void {
    if (this.mTextInputClient !== undefined) {
      this.mTextInputClient.selectByMovement({ direction: direction }, (err: BusinessError) => {
        this.addLog(`selectByMovement err is ${JSON.stringify(err)}`);
      });
    } else {
      this.addLog('selectByMovement this.mTextInputClient is undefined');
    }
  }

  public async selectToBegin(): Promise<void> {
    if (this.mTextInputClient !== undefined) {
      let index = await this.mTextInputClient.getTextIndexAtCursor();
      this.addLog(`selectToBegin index= ${index}, x = ${this.cursorInfo.x}`);
      if (index > 0) {
        this.mTextInputClient.selectByRange({ start: 0, end: index });
      } else {
        this.mTextInputClient.selectByRange({ start: 0, end: this.cursorInfo.x });
      }
    } else {
      this.addLog('selectToBegin this.mTextInputClient is undefined');
    }
  }

  public async selectToEnd(): Promise<void> {
    if (this.mTextInputClient !== undefined) {
      let index = await this.mTextInputClient.getTextIndexAtCursor();
      this.addLog(`selectToEnd index= ${index}, x = ${this.cursorInfo.x}`);
      if (index > 0) {
        this.mTextInputClient.selectByRange({ start: index, end: 1000 });
      } else {
        this.mTextInputClient.selectByRange({ start: this.cursorInfo.x, end: 1000 });
      }
    } else {
      this.addLog('selectToEnd this.mTextInputClient is undefined');
    }
  }

  public sendExtendAction(action: inputMethodEngine.ExtendAction): void {
    if (this.mTextInputClient !== undefined) {
      this.mTextInputClient.sendExtendAction(action);
    } else {
      this.addLog('sendExtendAction this.mTextInputClient is undefined');
    }
  }

  public setSelectInfo(info: string): void {
    this.selectInfo = info;
    this.addLog(`setSelectInfo info = ${info}`);
  }

  public setTextInfo(info: string): void {
    this.textInfo = info;
    this.addLog(`setTextInfo info = ${info}`);
  }

  public setInputInfo(info: string): void {
    this.inputInfo = info;
    this.addLog(`setInputInfo info = ${info}`);
  }

  public refreshInfo(): void {
    this.addLog('refreshInfo');
    let showText = '';
    this.addLog('refreshInfo1');
    if (this.mTextInputClient) {
      showText += 'five chars: before：[' + this.mTextInputClient.getForward(5) + '];after：[' + this.mTextInputClient.getBackward(5) + ']\n';
    }
    this.addLog('refreshInfo2');
    showText += this.cursorInfo + "\n";
    this.addLog('refreshInfo3');
    showText += this.selectInfo + "\n";
    this.addLog('refreshInfo4');
    showText += this.textInfo + "\n";
    this.addLog('refreshInfo5');
    showText += this.inputInfo;
    this.addLog('refreshInfo6');
    AppStorage.set<string>('showLog', showText);
    this.addLog('refreshInfo7');
    this.addLog('result is = ' + showText);
  }

  public initPinyin(descriptor: resourceManager.RawFileDescriptor, filePath: string) {
    this.addLog(`initPinyin`);
    //  主线程中创建Worker对象
    let workerInstance = new worker.ThreadWorker("entry/ets/worker/worker.ts");
    workerInstance.onmessage = (e: MessageEvents): void => {
      // e : MessageEvents, 用法如下：
      // let data = e.data;
      console.log("onmessage");
      let data = e.data as PinyinMessage;
      let type = data.type;
      switch (type) {
        case MessageType.UPDATE: {
          let updateData = data as PinyinUpdateMessage
          this.updateAppStorage(updateData);
          this.addLog(`workerPort.onmessage update`);
          break;
        }
        case MessageType.RESULT: {
          let resultData = data as PinyinResultMessage
          this.addLog(`workerPort.onmessage result str: ${resultData.resultStr}}`);
          if (this.mTextInputClient != undefined) {
            this.mTextInputClient.insertText(resultData.resultStr);
          }
          break;
        }
      }
    }
    workerInstance.onexit = (code) => {
      this.addLog("workerInstance onexit");
    }
    let data = new PinyinInitMessage(descriptor, filePath);
    workerInstance.postMessage(data);

    this.workerInstance = workerInstance;
  }

  /** 拼音引擎：生命期管理 */
  public destroyPinyin() {
    this.addLog(`destroyPinyin`);
    if (this.workerInstance != undefined) {
      try {
        let data = new PinyinMessage(MessageType.CLOSE);
        this.workerInstance!.postMessage(data);
        this.workerInstance!.terminate();
      } catch (_) {
      }
    }
  }

  /** 拼音引擎：重置状态 */
  public resetPinyin() {
    if (this.workerInstance != undefined) {
      try {
        let data = new PinyinMessage(MessageType.RESET);
        this.workerInstance!.postMessage(data);
      } catch (_) {
      }
    }
  }

  /** 拼音引擎：普通按键 */
  private onKeyClick(keyChar: string, keyCode: number) {
    if (this.workerInstance != undefined) {
      try {
        let data = new PinyinKeyMessage(keyChar, keyCode);
        this.workerInstance!.postMessage(data);
      } catch (_) {
      }
    }
  }

  /** 拼音引擎：候选词选择 */
  private chooseCandidate(candId: number) {
    if (this.workerInstance != undefined) {
      try {
        let data = new PinyinChooseMessage(candId);
        this.workerInstance!.postMessage(data);
      } catch (_) {
      }
    }
  }

  /**拼音引擎：收到子线程回包*/
  private updateAppStorage(data: PinyinUpdateMessage) {
    if (data.candidates.length <= 0) {
      AppStorage.setOrCreate('isMoreText', false);
    }
    AppStorage.setOrCreate('pinyin', data.pinyin);
    this.dataSource.setData(data.candidates);
  }

  /**拼音引擎：给 UI 拿数据源*/
  public getDataSource(): ChineseDataSource {
    return this.dataSource;
  }
}

class KeyboardController {
  private barPosition: number = 0;
  /**当前所有被按下的key 的code数组*/
  private keyCodes: Array<number> = [];
  /**当前键盘按下记录，最大按下的按键数*/
  private maxKeyCodesLen: number = 0;
  private mContext: InputMethodExtensionContext | undefined;
  private panel: inputMethodEngine.Panel | undefined;
  private isSpecialKeyPress: boolean = false;
  private isKeyboardShow: boolean = false;
  private inputHandle: InputHandler = InputHandler.getInstance();
  private mKeyboardDelegate: inputMethodEngine.KeyboardDelegate | undefined;

  constructor() {
    this.mContext = undefined;
    this.panel = undefined;
    this.mKeyboardDelegate = undefined;
  }

  public onCreate(context: InputMethodExtensionContext): void {
    this.mContext = context;
    this.inputHandle.addLog('onCreate');
    this.initWindow();
    this.registerListener();
  }

  public onDestroy(): void {
    this.inputHandle.addLog('onDestroy');
    this.unRegisterListener();
    this.destroyPanel();
  }

  private initWindow(): void {
    if (this.mContext === undefined) {
      return;
    }
    this.inputHandle.addLog('initWindow');
    let dis = display.getDefaultDisplaySync();
    this.inputHandle.addLog("initWindow-oncall display");
    let dWidth = dis.width;
    let dHeight = dis.height;
    let navigationBar_height = NAVIGATIONBAR_HEIGHT_DEFAULT;
    let keyHeightRate = KEYBOARD_HEIGHT_RATE_DEFAULT;
    AppStorage.setOrCreate('windowWidth', dis.width);
    AppStorage.setOrCreate('windowHeight', dis.height);
    let isLandscape = false;
    let isRkDevice = false;
    if (dis.width > dis.height) {
      isLandscape = true;
      AppStorage.setOrCreate('isLandscape', true);
    } else {
      AppStorage.setOrCreate('isLandscape', false);
    }
    if (dWidth === DEVICE_PHONE.width && dHeight === DEVICE_PHONE.height) {
      navigationBar_height = 0;
      keyHeightRate = KEYBOARD_HEIGHT_RATE_PHONE;
    } else if (dWidth === DEVICE_PHONE.height && dHeight === DEVICE_PHONE.width) {
      navigationBar_height = 0;
      keyHeightRate = KEYBOARD_HEIGHT_RATE_PHONE_LAND;
    } else if (dWidth === DEVICE_RK.width && dHeight === DEVICE_RK.height) {
      navigationBar_height = KEYBOARD_HEIGHT_RATE_DEFAULT;
      AppStorage.setOrCreate('isRkDevice', true);
      isRkDevice = true;
    } else if (dWidth === DEVICE_BIG.width && dHeight === DEVICE_BIG.height) {
      navigationBar_height = 0;
      keyHeightRate = KEYBOARD_HEIGHT_RATE_BIG_LAND;
    } else if (dWidth === DEVICE_BIG.height && dHeight === DEVICE_BIG.width) {
      navigationBar_height = 0;
      keyHeightRate = KEYBOARD_HEIGHT_RATE_BIG;
    }
    let keyHeight = Math.round(dHeight * keyHeightRate);
    this.barPosition = dHeight - keyHeight - navigationBar_height;
    this.inputHandle.addLog(`initWindow-dWidth = ${dWidth};dHeight = ${dHeight};keyboard height = ${keyHeight};;navibar height = navigationBar_height`);
    this.inputHandle.addLog(`initWindow-deviceType = ${deviceInfo.deviceType}`);
    let panelInfo: inputMethodEngine.PanelInfo = {
      type: inputMethodEngine.PanelType.SOFT_KEYBOARD,
      flag: inputMethodEngine.PanelFlag.FLG_FIXED
    }
    let inputStyle = StyleConfiguration.getInputStyle(isLandscape, isRkDevice, deviceInfo.deviceType);
    AppStorage.setOrCreate('inputStyle', inputStyle);
    InputMethodEngine.createPanel(this.mContext, panelInfo).then((panel: inputMethodEngine.Panel) => {
      this.panel = panel;
      panel.resize(dWidth, keyHeight).then(() => {
        panel.moveTo(0, this.barPosition).then(() => {
          panel.setUiContent('pages/Index').then(() => {
            this.inputHandle.addLog('loadContent finished');
          })
        })
      })
    })
  }

  private destroyPanel(): void {
    this.inputHandle.addLog('destroyPanel');
    if (this.panel) {
      InputMethodEngine.destroyPanel(this.panel);
    }
  }

  private resizePanel(): void {
    this.inputHandle.addLog('resizeWindow');
    let dis = display.getDefaultDisplaySync();
    this.inputHandle.addLog('resizeWindow-oncall display');
    let dWidth = dis.width;
    let dHeight = dis.height;
    let navigationBar_height = dHeight * 0.07; // 有些产品导航栏高度为0，默认为0.07
    let keyHeightRate = KEYBOARD_HEIGHT_RATE_DEFAULT;
    AppStorage.setOrCreate<number>('windowWidth', dis.width);
    AppStorage.setOrCreate<number>('windowHeight', dis.height);
    let isLandscape = false;
    let isRkDevice = false;
    if (dis.width > dis.height) {
      isLandscape = true;
      AppStorage.setOrCreate('isLandscape', true);
    } else {
      AppStorage.setOrCreate('isLandscape', false);
    }
    if (dWidth === DEVICE_PHONE.width && dHeight === DEVICE_PHONE.height) {
      navigationBar_height = 0;
      keyHeightRate = KEYBOARD_HEIGHT_RATE_PHONE;
    } else if (dWidth === DEVICE_PHONE.height && dHeight === DEVICE_PHONE.width) {
      navigationBar_height = 0;
      keyHeightRate = KEYBOARD_HEIGHT_RATE_PHONE_LAND;
    } else if (dWidth === DEVICE_RK.width && dHeight === DEVICE_RK.height) {
      navigationBar_height = KEYBOARD_HEIGHT_RATE_DEFAULT;
      AppStorage.setOrCreate('isRkDevice', true);
      isRkDevice = true;
    } else if (dWidth === DEVICE_BIG.width && dHeight === DEVICE_BIG.height) {
      navigationBar_height = 0;
      keyHeightRate = KEYBOARD_HEIGHT_RATE_BIG_LAND;
    } else if (dWidth === DEVICE_BIG.height && dHeight === DEVICE_BIG.width) {
      navigationBar_height = 0;
      keyHeightRate = KEYBOARD_HEIGHT_RATE_BIG;
    }
    let keyHeight = Math.round(dHeight * keyHeightRate);
    let inputStyle = StyleConfiguration.getInputStyle(isLandscape, isRkDevice, deviceInfo.deviceType);
    AppStorage.setOrCreate('inputStyle', inputStyle);
    if (this.panel) {
      this.panel.resize(dWidth, keyHeight).then(() => {
        if (this.panel) {
          this.panel.moveTo(0, dHeight - keyHeight - navigationBar_height).then(() => {
            this.inputHandle.addLog('resizePanel-moveTo success');
          })
        }
      }).catch((err: BusinessError) => {
        this.inputHandle.addLog('resizePanel-moveTo err' + JSON.stringify(err));
      })
    }
  }

  /**
   * 注册键盘监听器，这个函数一次性注册
   */
  private registerListener(): void {
    this.inputHandle.addLog('registerListener');
    // 当屏幕发生变化
    display.on('change', () => {
      this.inputHandle.addLog('screenChangeEvent');
      this.resizePanel();
    });
    //监听输入法启动
    InputMethodEngine.on('inputStart', (kbController: inputMethodEngine.KeyboardController, textInputClient: inputMethodEngine.InputClient) => {
      this.inputHandle.addLog('keyboard inputStart');
      this.inputHandle.onInputStart(kbController, textInputClient);
    })
    InputMethodEngine.on('inputStop', () => {
      this.inputHandle.addLog('keyboard inputStop');
      this.onDestroy();
      if (this.mContext) {
        this.mContext.destroy();
      }
    });

    // this.inputHandle.addLog('pre on privateCommand');
    // try {
    //   InputMethodEngine.on('privateCommand', (record : Record<string, inputMethodEngine.CommandDataType>) => {
    //     this.inputHandle.addLog('keyboard privateCommand' + JSON.stringify(record));
    //     Object.keys(record).forEach((key: string) => {
    //       this.inputHandle.addLog(`onPageShow private command key: ${key}, value: ${record[key]}`);
    //     })
    //   });
    // } catch (err) {
    //   let error = err as BusinessError;
    //   this.inputHandle.addLog(`on privateCommand sendPrivateCommand catch error: ${error.code} ${error.message}`);
    // }

    this.mKeyboardDelegate = inputMethodEngine.getKeyboardDelegate();

    this.mKeyboardDelegate.on('keyDown', (keyEvent: inputMethodEngine.KeyEvent) => {
      if (this.isKeyboardShow) {
        this.inputHandle.hideKeyboardSelf();
      }
      this.inputHandle.addLog(`keyDown: code = ${keyEvent.keyCode}`);
      let result = this.onKeyDown(keyEvent);
      // 刷新当前按下的数量长度
      this.maxKeyCodesLen = (
        this.maxKeyCodesLen > this.keyCodes.length ?
        this.maxKeyCodesLen : this.keyCodes.length
      )

      this.inputHandle.addLog(`keyDown: result = ${result}`);
      return result;
    });

    this.mKeyboardDelegate.on('keyUp', (keyEvent: inputMethodEngine.KeyEvent) => {
      this.inputHandle.addLog(`keyUp: code = ${keyEvent.keyCode}`);
      let result = this.onKeyUp(keyEvent);
      // 如果清空了所有按键，那么代表松手了，清空按键列表长度
      if (this.keyCodes.length == 0)
        this.maxKeyCodesLen = 0;
      this.inputHandle.addLog(`keyUp: result = ${result}`);
      return result;
    });
    this.mKeyboardDelegate.on('cursorContextChange', (x: number, y: number, height: number) => {
      let cursorInfo: CursorInfo = { x: x, y: y, height: height };
      this.inputHandle.setCursorInfo(cursorInfo);
    });
    if (isDebug) {
      this.mKeyboardDelegate.on('selectionChange', (oldBegin: number, oldEnd: number, newBegin: number, newEnd: number) => {
        this.inputHandle.setSelectInfo('selectInfo: from(' + oldBegin + ',' + oldEnd + ') to (' + newBegin + ',' + newEnd + ')');
      });
      this.mKeyboardDelegate.on('textChange', (text: string) => {
        this.inputHandle.setTextInfo('textInfo: ' + text);
      });
    }
  }

  public isShiftKeyHold(): boolean {
    if (this.keyCodes.length === 0) {
      return false;
    }
    let preDownKey = this.keyCodes[0];
    return preDownKey === KeyCode.KEYCODE_SHIFT_LEFT || preDownKey === KeyCode.KEYCODE_SHIFT_RIGHT;
  }

  /**在物理键盘或软键盘上按下某个键时*/
  public onKeyDown(keyEvent: inputMethodEngine.KeyEvent): boolean {
    this.inputHandle.addLog('onKeyDown: code = ' + keyEvent.keyCode);
    let keyCode = keyEvent.keyCode;
    let idx = this.keyCodes.indexOf(keyCode);
    if (idx === -1 && keyCode != 2054) { // 按下回车2054 可能会导致软键盘关闭，值卡在keyCodes 中，所以不能让2054进入keyCodes
      this.keyCodes.push(keyCode);
    } else {
      this.inputHandle.addLog(`keyCode down is intercepted: ${keyCode}}`);
    }
    this.inputHandle.addLog(`onKeyDown: this.keyCodes =  ${JSON.stringify(this.keyCodes)}`);
    // 如果按下shift时按下了非文字内容，那么输出特殊字符
    if (this.isShiftKeyHold() && this.keyCodes.length === 2 && !this.isKeyCodeAZ(keyCode)) {

      const flag = this.isShiftKeyHold() && this.keyCodes.length === 2 && !this.isKeyCodeAZ(keyCode);
      this.inputHandle.addLog(`onKeyDown: isShiftKeyHold${this.isShiftKeyHold()}` +
        `keyCode: ${keyCode === KeyCode.KEYCODE_ALT_LEFT || keyCode === KeyCode.KEYCODE_ALT_RIGHT}`);
      this.isSpecialKeyPress = true;
      return false;
    }
    if (this.isSpecialKeyPress || keyCode === KeyCode.KEYCODE_ALT_LEFT || keyCode === KeyCode.KEYCODE_ALT_RIGHT) {
      this.inputHandle.addLog(`onKeyDown: isSpecialKeyPress：${this.isSpecialKeyPress} ${keyCode === KeyCode.KEYCODE_ALT_LEFT || keyCode === KeyCode.KEYCODE_ALT_RIGHT}`);

      return false;
    }
    //获取当前按下按键对应的值
    let keyValue: string = GetHardKeyValue(keyCode, this.isShiftKeyHold());
    if (keyValue === '') {
      this.inputHandle.addLog('onKeyDown: unknown keyCode');
      this.isSpecialKeyPress = true;
      return false;
    }
    return this.inputHardKeyCode(keyValue, keyCode);
  }

  // 当物理键盘或软键盘上的某个键被“抬起”时，系统会调用这个函数
  public onKeyUp(keyEvent: inputMethodEngine.KeyEvent): boolean {
    // 1. 打印日志：当前抬起的键码是多少
    this.inputHandle.addLog('OnKeyUp: code = ' + keyEvent.keyCode);
    // 2. 把事件里的键码取出来，存到局部变量 keyCode，后面都用它
    let keyCode = keyEvent.keyCode;
    // 3. 在“当前正按着的键”数组里找这个键码的索引
    let idx = this.keyCodes.indexOf(keyCode);
    // 4. 如果找到了（>=0），说明之前确实按下了，就把它从数组里删掉
    if (idx !== -1) {
      this.keyCodes.splice(idx, 1);
    } else {
      // 4-1. 如果没找到，说明这次抬起事件被提前拦截或异常，打印日志
      this.inputHandle.addLog(`keyCode KeyUp is intercepted: ${keyCode}`);
    }
    // 5. 再次打印日志：当前还剩哪些键没松开
    this.inputHandle.addLog(`OnKeyUp: this.keyCodes = ${JSON.stringify(this.keyCodes)}`);


    // ✅ 只在松开时判断是否为“仅 Shift”
    const wasOnlyShift =
      (keyCode === KeyCode.KEYCODE_SHIFT_LEFT || keyCode === KeyCode.KEYCODE_SHIFT_RIGHT) &&
        this.keyCodes.length === 0 && this.maxKeyCodesLen == 1;


    if (wasOnlyShift) {
      // 这里可以触发“单击 Shift”行为 , 修改是否是中文输入法
      setIsChinese(!getIsChinese())
      this.inputHandle.addLog(`onKeyUp Shift 被单独按下并释放 ,当前中文状态 ${getIsChinese()}`);
    }


    /* 6-1. 下面这些键码（删除、方向键等功能键）已经在 onKeyDown 里处理过，这里直接拦截，不再往下传，防止重复处理 */
    // For KEYCODE_DEL/KEYCODE_FORWARD_DEL, processed in OnKeyDown, so just intercept it
    if (keyCode === 2055 || keyCode === 2071 || (keyCode >= 2012 && keyCode <= 2016)) {
      this.inputHandle.addLog(`special code: ${keyCode}`);
      return true;
    }
    if (keyCode === 2057 || keyCode === 2058) {
      this.inputHandle.addLog(`special code: ${keyCode}`);
      return true;
    }
    // 如果当前存在候选词，并且当前按下是空格，代表默认你插入第一个候选词
    if (this.inputHandle.getDataSource().totalCount() != 0 && keyCode == 2050) {
      return true;
    }

    // 7. 如果正处于“特殊组合键”状态（如 Shift+Enter）
    if (this.isSpecialKeyPress) {
      // 7-1. 根据当前键码和 Shift 是否按住，拿到对应的字符/键值
      let keyValue = GetHardKeyValue(keyCode, this.isShiftKeyHold());
      // 7-2. 如果拿不到有效字符（空串），继续保持特殊键标记
      if (!keyValue) {
        this.isSpecialKeyPress = true;
      }
      // 7-3. 当所有按键都已松开（数组为空），就退出特殊键状态
      if (this.keyCodes.length === 0) {
        this.inputHandle.addLog("this.isSpecialKeyPress = false;")
        this.isSpecialKeyPress = false;
      }
      // 7-4. 打印日志：当前特殊键标记的最新值
      this.inputHandle.addLog(`OnKeyUp: this.isSpecialKeyPress: ${this.isSpecialKeyPress}`);
      // 7-5. 返回 false，告诉系统“这个事件我处理完了，别再往下传”
      return false;
    }
    // 8. 既不是特殊键，也不是拦截键，返回 true，事件继续向系统上层传递
    return true;
  }

  public isKeyCodeAZ(keyCode: number): boolean {
    return keyCode >= KeyCode.KEYCODE_A && keyCode <= KeyCode.KEYCODE_Z;
  }

  public isKeyCodeNumber(keyCode: number): boolean {
    return (keyCode >= KeyCode.KEYCODE_0 && keyCode <= KeyCode.KEYCODE_9) || (keyCode >= KeyCode.KEYCODE_NUMPAD_0 && keyCode <= KeyCode.KEYCODE_NUMPAD_9);
  }

  /**处理字符或功能键*/
  public inputHardKeyCode(keyValue: string, keyCode: number): boolean {
    this.inputHandle.addLog(`inputHardKeyCode keyValue is: ${keyValue}`);
    if (this.processFunctionKeys(keyValue)) {
      return true;
    }
    if (this.shiftKeys(keyValue)) {
      return false;
    }
    // text – 输入文本内容

    //  isChinese – 当前是否正在输入中文拼音
    let isChinese: boolean = getIsChinese();
    // isSelText – 当前是否是在候选栏里“选中”某个候选词
    let isSelText: boolean | undefined = undefined;
    // selNum – 当 isSelText=true 时，告诉拼音引擎选中了第几个候选
    let selNum: number | undefined = undefined;

    this.inputHandle.insertText(keyValue, isChinese, isSelText, selNum);
    return true;
  }

  public shiftKeys(keyValue: string): boolean {
    this.inputHandle.addLog(`shiftKeys keyValue is: ${keyValue}`);
    switch (keyValue) {
      case 'KEYCODE_SHIFT_LEFT':
      case 'KEYCODE_SHIFT_RIGHT':
        return true;
      default:
        return false;
    }
  }

  /**用来处理键盘上的功能键*/
  public processFunctionKeys(keyValue: string): boolean {
    this.inputHandle.addLog(`processFunctionKeys keyValue is: -${keyValue}-`);
    const pinyin = AppStorage.get<string>("pinyin") ?? "";
    switch (keyValue) {
      case " ":
      // 如果按下空格后，存在候选词，那么默认选择第一个候选词
        const dataSource = this.inputHandle.getDataSource();
        // ClawMate adaptation: select only a real Chinese candidate; preserve English spaces.
        if (getIsChinese() && dataSource.totalCount() > 0) {
          this.inputHandle.insertText("", true, true, 0)
        } else {
          this.inputHandle.insertText(" ", false);
        }

        return true;
      case "KEYCODE_DEL":
      // 获取当前正在输入的拼音内容
        this.inputHandle.deleteForward(1, pinyin.length > 0);
        return true;
      case "KEYCODE_FORWARD_DEL":
        this.inputHandle.deleteBackward(1);
        return true;
      case "KEYCODE_DPAD_UP":
        this.inputHandle.moveCursor(inputMethodEngine.Direction.CURSOR_UP);
        return true;
      case "KEYCODE_DPAD_DOWN":
        this.inputHandle.moveCursor(inputMethodEngine.Direction.CURSOR_DOWN);
        return true;
      case "KEYCODE_DPAD_LEFT":
        this.inputHandle.moveCursor(inputMethodEngine.Direction.CURSOR_LEFT);
        return true;
      case "KEYCODE_DPAD_RIGHT":
        this.inputHandle.moveCursor(inputMethodEngine.Direction.CURSOR_RIGHT);
        return true;

      case "1":
      case "2":
      case "3":
      case "4":
      case "5":
      case "6":
      case "7": {
        // 如果是中文输入法模式下 存在预选词,预选词没有越界,那么自动选中那个预选词
        let s = this.inputHandle.getDataSource()
        // 当前输入的下标
        const inx = Number(keyValue)
        // 当前应当选中的下标
        const selNum = 0 + inx + getCandidateStartInx() - 1;

        this.inputHandle.addLog(
          `processFunctionKeys: ${keyValue} ` +
            `candidateStartInx: ${getCandidateStartInx()} ` +
            `selNum: ${selNum} `
        )
        if (getIsChinese()//是否是中文输入法
          && s && s.totalCount() > 0//存在预选词
          && selNum < s.totalCount()//预选词未越界
        ) {
          this.inputHandle.insertText("", true, true, selNum)
          return true;
        }
      }
        return false;

      case "-":
        console.log("kikaInput-js: 做翻页")
        if (getCandidateStartInx() - 7 >= 0) {
          setCandidateStartInx(getCandidateStartInx() - 7);
          return getIsChinese();
        }
        return false;

      case "=":
        console.log("kikaInput-js: 右翻页")
        setCandidateStartInx(getCandidateStartInx() + 7);
        return getIsChinese();
      default:
        return false;
    }
  }

  private unRegisterListener(): void {
    this.inputHandle.addLog('unRegisterListener');

    InputMethodEngine.off('inputStop', () => {
      this.inputHandle.addLog('inputStop off');
    });
    if (this.mKeyboardDelegate) {
      this.mKeyboardDelegate.off('keyDown');
      this.mKeyboardDelegate.off('keyUp');
      if (isDebug) {
        this.mKeyboardDelegate.off('cursorContextChange');
        this.mKeyboardDelegate.off('selectionChange');
        this.mKeyboardDelegate.off('textChange');
      }
    }
  }
}


/**获取是否是中文输入法*/
function getIsChinese() {
  let isChinese: boolean = AppStorage.get<boolean>("isChinese") ?? false;
  InputHandler.getInstance().addLog(`IsChinese ${isChinese}`)
  return isChinese
}

/**设置是否是中文输入法*/
function setIsChinese(isChinese: boolean) {
  AppStorage.set("isChinese", isChinese)
  // return AppStorage.setAndLink("isChinese", isChinese);

  // let isChinese: boolean = AppStorage.get<boolean>("isChinese") ?? false;
}

/**获取候选词开始下标*/
function getCandidateStartInx() {
  let candidateStartInx: number = AppStorage.get<number>("candidateStartInx") ?? 0;
  return candidateStartInx
}

/**设置候选词开始下标*/
function setCandidateStartInx(candidateStartInx: number) {
  return AppStorage.set("candidateStartInx", candidateStartInx)
}


export const keyboardController: KeyboardController = new KeyboardController();
