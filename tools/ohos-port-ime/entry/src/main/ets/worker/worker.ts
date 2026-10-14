import worker from '@ohos.worker';
import { DecodingInfo, ImeState } from '../model/DecodingInfo';
import {
    PinyinMessage,
    PinyinInitMessage,
    PinyinKeyMessage,
    PinyinUpdateMessage,
    PinyinChooseMessage,
    PinyinResultMessage,
    MessageType
} from '../model/PinyinMessage'

const TAG: string = '[imePinYin worker]'

// 创建worker线程中与主线程通信的对象
const workerPort = worker.workerPort
let decInfo: DecodingInfo = new DecodingInfo()
let KEYCODE_DEL: number = 67

// worker线程接收主线程信息
workerPort.onmessage = function (e) {
    // data:主线程发送的消息
    let data = e.data as PinyinMessage;
    let type = data.type;
    switch (type) {
        case MessageType.CLOSE: {
            // 关闭线程
            console.info(`${TAG} workerPort.onmessage close`);
            decInfo.destroyPinyin();
            workerPort.close();
            break
        }

        case MessageType.INIT: {
            let initData = data as PinyinInitMessage
            console.info(`${TAG} workerPort.onmessage init: ${initData.filePath}`);
            decInfo.initPinyin(initData.descriptor, initData.filePath);
            break
        }

        case MessageType.RESET: {
            console.info(`${TAG} workerPort.onmessage reset}`);
            decInfo.reset();
            updateAppStorage();
            break
        }

        case MessageType.CHOOSE: {
            let choiceData = data as PinyinChooseMessage
            console.info(`${TAG} workerPort.onmessage choose candId: ${choiceData.candId}}`);
            chooseAndUpdate(choiceData.candId);
            break
        }

        case MessageType.KEY: {
            let keyData = data as PinyinKeyMessage
            console.info(`${TAG} workerPort.onmessage key char: ${keyData.keyChar}, code: ${keyData.keyCode}`);
            onKeyClick(keyData.keyChar, keyData.keyCode);
            break
        }

        default: {
            console.error(`${TAG} workerPort.onmessage message type error`)
        }
    }
}
// worker线程发生error的回调
workerPort.onerror = function (e) {
    console.info(`${TAG} workerPort.onerror ${JSON.stringify(e)}`)
}

function onKeyClick(keyChar: string, keyCode: number): boolean {
    if (decInfo.isSplStrFull()) {
        return true;
    }

    if ((keyChar >= 'a' && keyChar <= 'z')
    || (keyChar == '\'' && !decInfo.charBeforeCursorIsSeparator())
    || (((keyChar >= '0' && keyChar <= '9') || keyChar == ' ') && ImeState.STATE_COMPOSING == decInfo.mImeState)) {
        decInfo.addSplChar(keyChar, false);
        chooseAndUpdate(-1);
    } else if (keyCode == KEYCODE_DEL) { //KeyEvent.KEYCODE_DEL
        decInfo.prepareDeleteBeforeCursor();
        chooseAndUpdate(-1);
    }
    return true;
}

function updateAppStorage() {
    let data = new PinyinUpdateMessage(decInfo.getComposingStr(),
    decInfo.mCandidatesList.slice(0));
    workerPort.postMessage(data);
}

function chooseAndUpdate(candId: number) {
    if (ImeState.STATE_PREDICT != decInfo.mImeState) {
        decInfo.chooseDecodingCandidate(candId);
    } else {
        // Choose a prediction item.
        decInfo.choosePredictChoice(candId);
    }

    updateAppStorage();

    if (decInfo.getComposingStr().length > 0) {
        let resultStr: string;
        resultStr = decInfo.getComposingStrActivePart();

        // choiceId >= 0 means user finishes a choice selection.
        if (candId >= 0 && decInfo.canDoPrediction()) {
            //commitResultText(resultStr);
            let data = new PinyinResultMessage(resultStr);
            workerPort.postMessage(data);
            console.info(TAG + 'resultStr: ' + resultStr);
            decInfo.reset();
            updateAppStorage();
        } else {
            console.info(TAG + 'resetCandidates ');
            decInfo.resetCandidates();
        }
    } else {
        console.info(TAG + 'getComposingStr null ');
    }
}