import hilog from '@ohos.hilog';
// import pinyinNapi from 'libime_pinyin.so'
import pinyinNapi from 'libime_pinyin.so'
import resourceManager from '@ohos.resourceManager';

let TAG: string = 'imePinYin';
let DOMAIN: number = 0x0000;

export class PinYinService {
    static pinYinService: PinYinService = new PinYinService();

    private inited: boolean = false;

    private mUsr_dict_file: string;

    private fileDescriptor: resourceManager.RawFileDescriptor;

    private isDebug = false;

    public addLog(message: string): void {
        if (this.isDebug) {
            hilog.info(DOMAIN, TAG, message);
        }
    }

    public setRawFileDescriptor(descriptor: resourceManager.RawFileDescriptor) {
        this.fileDescriptor = descriptor;
    }

    public setFilePath(filePath: string) {
        this.mUsr_dict_file = filePath + "usr_dict.dat"
    }

    public initPinyinEngine() {
        if (!this.fileDescriptor) {
            this.addLog('initPinyinEngine return');
            return
        }
        this.inited = pinyinNapi.nativeImOpenDecoderFd(this.fileDescriptor.fd,
        this.fileDescriptor.offset, this.fileDescriptor.length, this.mUsr_dict_file);
        this.addLog('initPinyinEngine inited: ' + this.inited);
    }

    public destroyEngine() {
        let ret = pinyinNapi.nativeImCloseDecoder();
        this.inited = false;
        this.addLog('destroyEngine ret: ' + ret);
    }

    public imResetSearch() {
        pinyinNapi.nativeImResetSearch();
    }

    public imSearch(pyBuf: string, pyLen: number): number {
        let ret = pinyinNapi.nativeImSearch(pyBuf, pyLen);
        this.addLog('imSearch ret: ' + ret);
        return ret;
    }

    public imDelSearch(pos: number, is_pos_in_splid: boolean,
                       clear_fixed_this_step: boolean): number {
        let ret = pinyinNapi.nativeImDelSearch(pos, is_pos_in_splid,
            clear_fixed_this_step);
        this.addLog('imDelSearch ret: ' + ret);
        return ret;
    }

    public imChoose(choiceId: number): number {
        let ret = pinyinNapi.nativeImChoose(choiceId);
        this.addLog('imChoose ret: ' + ret);
        return ret;
    }

    public imGetSplStart(): number[] {
        let ret = pinyinNapi.nativeImGetSplStart();
        this.addLog('imGetSplStart ret: ' + ret);
        return ret;
    }

    public imGetPyStr(decoded: boolean): string {
        let ret = pinyinNapi.nativeImGetPyStr(decoded);
        this.addLog('imGetPyStr ret: ' + ret);
        return ret;
    }

    public imGetPyStrLen(decoded: boolean): number {
        let ret = pinyinNapi.nativeImGetPyStrLen(decoded);
        this.addLog('imGetPyStrLen ret: ' + ret);
        return ret;
    }

    public imGetChoice(choiceId: number): string {
        let ret = pinyinNapi.nativeImGetChoice(choiceId);
        this.addLog('imGetChoice ret: ' + ret);
        return ret;
    }

    public imGetFixedLen(): number {
        let ret = pinyinNapi.nativeImGetFixedLen();
        this.addLog('imGetFixedLen ret: ' + ret);
        return ret;
    }

    public imGetChoiceList(choicesStart: number, choicesNum: number, sentFixedLen: number): Array<string> {
        let choiceList: Array<string> = [];
        for (let i = choicesStart; i < choicesStart + choicesNum; i++) {
            let retStr = pinyinNapi.nativeImGetChoice(i);
            if (0 == i) retStr = retStr.substring(sentFixedLen);
            choiceList.push(retStr);
        }
        this.addLog('imGetChoiceList choiceList: ' + choiceList);
        return choiceList;
    }

    public imGetPredictList(predictsStart: number, predictsNum: number): Array<string> {
        let predictList: Array<string> = [];
        for (let i = predictsStart; i < predictsStart + predictsNum; i++) {
            predictList.push(pinyinNapi.nativeImGetPredictItem(i));
        }
        this.addLog('imGetPredictList predictList: ' + predictList);
        return predictList;
    }

    public imGetPredictsNum(fixedStr: string): number {
        let ret = pinyinNapi.nativeImGetPredictsNum(fixedStr);
        this.addLog('imGetPredictsNum ret: ' + ret);
        return ret;
    }
}
