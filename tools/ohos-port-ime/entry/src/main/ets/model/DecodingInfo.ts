import { PinYinService } from './PinYinService';
import { StringBuffer } from './StringBuffer';
import resourceManager from '@ohos.resourceManager';

export enum ImeState {
    STATE_BYPASS, STATE_IDLE, STATE_INPUT, STATE_COMPOSING, STATE_PREDICT,
    STATE_APP_COMPLETION
}

export class DecodingInfo {
    /**
     * 拼音字符串的最大长度
     */
    private PY_STRING_MAX: number = 28;

    /**
     * 一页显示的最多候选词数
     */
    private MAX_PAGE_SIZE_DISPLAY: number = 200;
    /**
     * 显示选项的总数。列表可能只包含第一部分。
     * 如果用户试图导航到下一页，需要获取这些项来判断下一页是否在列表中。
     **/
    public mTotalChoicesNum: number;
    /**
     * 候选词列表，第一个是完整句子的候选者。
     */
    public mCandidatesList: Array<string> = new Array<string>();
    /**
     * 元素i存储了第i页的起始位置。
     */
    public mPageStart: Array<number> = new Array<number>();
    /**
     * 元素i存储第i页的字符数。
     */
    public mCnToPage: Array<number> = new Array<number>();
    /**
     * 在拼音字符串中要删除的位置。
     * 如果它小于0， IME将执行增量搜索，否则IME将执行删除操作。
     * 如果{@link #mIsPosInSpl}为真，IME将删除mPosDelSpl-th拼写的整个字符串，
     * 否则只会删除拼音字符串中的mPosDelSpl-th字符。
     */
    public mPosDelSpl: number = -1;
    /**
     * 如果{@link #mPosDelSpl}大于等于0，
     * 意在指示mPosDelSpl用于拼写id或字符中。
     */
    public mIsPosInSpl: boolean;
    /**
     * 拼写(拼音)字符串。
     * StringBuffer
     */
    private mSurface: StringBuffer;
    /**
     * 字节缓冲区用作本地函数调用的拼音字符串参数。
     */
    private mPyBuf: string[];
    /**
     * 编码成功的字符串长度
     */
    private mSurfaceDecodedLen: number;
    /**
     * 合成字符串。
     */
    private mComposingStr: string;
    /**
     * 合成字符串长度
     */
    private mActiveCmpsLen: number;
    /**
     * 用于显示的合成字符串，它复制自mComposingStr，并在拼写之间添加空格。
     **/
    private mComposingStrDisplay: string;
    /**
     * 用于显示的合成字符串长度
     */
    private mActiveCmpsDisplayLen: number;
    /**
     * 第一个完整的句子选择。
     */
    private mFullSent: string;
    /**
     * 固定的字符数。
     */
    private mFixedLen: number;
    /**
     * 如果标志为真，完成选择。
     */
    private mFinishSelection: boolean;
    /**
     * 每个拼写的起始位置。第一个是实际起始位置元素的数量。
     */
    private mSplStart: number[];
    /**
     * 在mSurface中编辑光标。
     */
    private mCursorPos: number = 0;
    /**
     * 应用建议的复杂信息。
     * CompletionInfo
     */
    private mAppCompletions: string[];

    public mImeState: ImeState = ImeState.STATE_IDLE;

    constructor() {
        // mSurface = new StringBuffer();
        this.mSurface = new StringBuffer();
        this.mSurfaceDecodedLen = 0;
    }

    public initPinyin(descriptor: resourceManager.RawFileDescriptor, filePath: string){
        PinYinService.pinYinService.setRawFileDescriptor(descriptor);
        PinYinService.pinYinService.setFilePath(filePath);
        PinYinService.pinYinService.initPinyinEngine();
    }

    public destroyPinyin() {
        PinYinService.pinYinService.destroyEngine();
    }

    public reset() {
        this.mSurface.delete(0, this.mSurface.length());
        this.mSurfaceDecodedLen = 0;
        this.mCursorPos = 0;
        this.mFullSent = "";
        this.mFixedLen = 0;
        this.mFinishSelection = false;
        this.mComposingStr = "";
        this.mComposingStrDisplay = "";
        this.mActiveCmpsLen = 0;
        this.mActiveCmpsDisplayLen = 0;

        this.resetCandidates();
    }

    public isCandidatesListEmpty(): boolean {
        return this.mCandidatesList.length == 0;
    }

    public isSplStrFull(): boolean {
        if (this.mSurface.length() >= this.PY_STRING_MAX - 1) return true;
        return false;
    }

    public addSplChar(ch: string, reset: boolean) {
        if (reset) {
            this.mSurface.clear();
            this.mSurfaceDecodedLen = 0;
            this.mCursorPos = 0;
            try {
                PinYinService.pinYinService.imResetSearch();
            } catch (e) {
            }
        }
        this.mSurface.insert(this.mCursorPos, ch);
        this.mCursorPos++;
    }

    // Prepare to delete before cursor. We may delete a spelling char if
    // the cursor is in the range of unfixed part, delete a whole spelling
    // if the cursor in inside the range of the fixed part.
    // This function only marks the position used to delete.
    public prepareDeleteBeforeCursor() {
        if (this.mCursorPos > 0) {
            let pos: number;
            for (pos = 0; pos < this.mFixedLen; pos++) {
                if (this.mSplStart[pos + 2] >= this.mCursorPos
                && this.mSplStart[pos + 1] < this.mCursorPos) {
                    this.mPosDelSpl = pos;
                    this.mCursorPos = this.mSplStart[pos + 1];
                    this.mIsPosInSpl = true;
                    break;
                }
            }
            if (this.mPosDelSpl < 0) {
                this.mPosDelSpl = this.mCursorPos - 1;
                this.mCursorPos--;
                this.mIsPosInSpl = false;
            }
        }
    }

    public length(): number {
        return this.mSurface.length();
    }

    public charAt(index: number): string {
        return this.mSurface.charAt(index);
    }

    public getOrigianlSplStr(): string {
        return this.mSurface.buffer();
    }

    public getSplStrDecodedLen(): number {
        return this.mSurfaceDecodedLen;
    }

    public getSplStart(): number[] {
        return this.mSplStart;
    }

    public getComposingStr(): string {
        return this.mComposingStr;
    }

    public getComposingStrActivePart(): string {
        //assert (mActiveCmpsLen <= mComposingStr.length());
        if (this.mActiveCmpsLen <= this.mComposingStr.length) {
            return this.mComposingStr.substring(0, this.mActiveCmpsLen);
        }
        return '';
    }

    public getActiveCmpsLen(): number {
        return this.mActiveCmpsLen;
    }

    public getComposingStrForDisplay(): string {
        return this.mComposingStrDisplay;
    }

    public getActiveCmpsDisplayLen(): number {
        return this.mActiveCmpsDisplayLen;
    }

    public getFullSent(): string {
        return this.mFullSent;
    }

    public getCurrentFullSent(activeCandPos: number): string {
        try {
            let retStr = this.mFullSent.substring(0, this.mFixedLen);
            retStr += this.mCandidatesList[activeCandPos];
            return retStr;
        } catch (e) {
            return "";
        }
    }

    public resetCandidates() {
        this.mCandidatesList.splice(0);
        this.mTotalChoicesNum = 0;

        this.mPageStart.splice(0);
        this.mPageStart.push(0);
        this.mCnToPage.splice(0);
        this.mCnToPage.push(0);
    }

    public candidatesFromApp(): boolean {
        return ImeState.STATE_APP_COMPLETION == this.mImeState;
        return false;
    }

    public canDoPrediction(): boolean {
        return this.mComposingStr.length == this.mFixedLen;
    }

    public selectionFinished(): boolean {
        return this.mFinishSelection;
    }

    // After the user chooses a candidate, input method will do a re-decoding and give the new candidate list.
    // If candidate id is less than 0, means user is inputting Pinyin, not selecting any choice.
    public  chooseDecodingCandidate(candId: number) {
        if (this.mImeState != ImeState.STATE_PREDICT) {
            this.resetCandidates();
            let totalChoicesNum = 0;
            try {
                if (candId < 0) {
                    if (this.length() == 0) {
                        totalChoicesNum = 0;
                    } else {
                        if (this.mPyBuf == null) {
                            this.mPyBuf = [];
                        }

                        for (let i = 0; i < this.length(); i++) {
                            this.mPyBuf[i] = this.charAt(i);
                        }

                        this.mPyBuf[this.length()] = '';
                        if (this.mPosDelSpl < 0) {
                            totalChoicesNum = PinYinService.pinYinService.imSearch(this.mPyBuf.join(''), this.length());
                        } else {
                            let clear_fixed_this_step = true;
                            if (ImeState.STATE_COMPOSING == this.mImeState) {
                                clear_fixed_this_step = false;
                            }
                            totalChoicesNum = PinYinService.pinYinService.imDelSearch(this.mPosDelSpl,
                            this.mIsPosInSpl, clear_fixed_this_step);
                            this.mPosDelSpl = -1;
                        }
                    }
                } else {
                    totalChoicesNum = PinYinService.pinYinService.imChoose(candId);
                }
            } catch (e) {
            }
            this.updateDecInfoForSearch(totalChoicesNum);
        }
    }

    private updateDecInfoForSearch(totalChoicesNum: number) {
        this.mTotalChoicesNum = totalChoicesNum;
        if (this.mTotalChoicesNum < 0) {
            this.mTotalChoicesNum = 0;
            return;
        }
        try {
            let pyStr: string;

            this.mSplStart = PinYinService.pinYinService.imGetSplStart();
            pyStr = PinYinService.pinYinService.imGetPyStr(false);
            this.mSurfaceDecodedLen = PinYinService.pinYinService.imGetPyStrLen(true);

            if (this.mSurfaceDecodedLen <= pyStr.length) {
                this.mFullSent = PinYinService.pinYinService.imGetChoice(0);
                this.mFixedLen = PinYinService.pinYinService.imGetFixedLen();

                // Update the surface string to the one kept by engine.
                this.mSurface.replace(0, this.mSurface.length(), pyStr);

                if (this.mCursorPos > this.mSurface.length())
                    this.mCursorPos = this.mSurface.length();
                this.mComposingStr = this.mFullSent.substr(0, this.mFixedLen)
                + this.mSurface.substr(this.mSplStart[this.mFixedLen + 1]);

                this.mActiveCmpsLen = this.mComposingStr.length;
                if (this.mSurfaceDecodedLen > 0) {
                    this.mActiveCmpsLen = this.mActiveCmpsLen
                    - (this.mSurface.length() - this.mSurfaceDecodedLen);
                }

                // Prepare the display string.
                if (0 == this.mSurfaceDecodedLen) {
                    this.mComposingStrDisplay = this.mComposingStr;
                    this.mActiveCmpsDisplayLen = this.mComposingStr.length;
                } else {
                    this.mComposingStrDisplay = this.mFullSent.substr(0, this.mFixedLen);
                    for (let pos = this.mFixedLen + 1; pos < this.mSplStart.length - 1; pos++) {
                        this.mComposingStrDisplay += this.mSurface.substr(this.mSplStart[pos], this.mSplStart[pos + 1]);
                        if (this.mSplStart[pos + 1] < this.mSurfaceDecodedLen) {
                            this.mComposingStrDisplay += " ";
                        }
                    }
                    this.mActiveCmpsDisplayLen = this.mComposingStrDisplay.length;
                    if (this.mSurfaceDecodedLen < this.mSurface.length()) {
                        this.mComposingStrDisplay += this.mSurface.substr(this.mSurfaceDecodedLen);
                    }
                }

                if (this.mSplStart.length == this.mFixedLen + 2) {
                    this.mFinishSelection = true;
                } else {
                    this.mFinishSelection = false;
                }
            }
        } catch (e) {
            this.mTotalChoicesNum = 0;
            this.mComposingStr = "";
        }
        // Prepare page 0.
        if (!this.mFinishSelection) {
            this.preparePage(0);
        }
    }

    public choosePredictChoice(choiceId: number) {
        if (ImeState.STATE_PREDICT != this.mImeState || choiceId < 0
        || choiceId >= this.mTotalChoicesNum) {
            return;
        }

        let tmp = this.mCandidatesList[choiceId];

        this.resetCandidates();

        this.mCandidatesList.push(tmp);
        this.mTotalChoicesNum = 1;

        //this.mSurface.replace(0, this.mSurface.length, "");
        this.mCursorPos = 0;
        this.mFullSent = tmp;
        this.mFixedLen = tmp.length;
        this.mComposingStr = this.mFullSent;
        this.mActiveCmpsLen = this.mFixedLen;

        this.mFinishSelection = true;
    }

    public getCandidate(candId: number): string {
        // 只加载得到的项，因此我们使用mCandidatesList.size()，而不是mTotalChoiceNum。
        if (candId < 0 || candId > this.mCandidatesList.length) {
            return null;
        }
        return this.mCandidatesList[candId];
    }

    private getCandiagtesForCache() {
        let fetchStart = this.mCandidatesList.length;
        let fetchSize = this.mTotalChoicesNum - fetchStart;
        if (fetchSize > this.MAX_PAGE_SIZE_DISPLAY) {
            fetchSize = this.MAX_PAGE_SIZE_DISPLAY;
        }
        try {
            let newList: Array<string> = null;
            if (ImeState.STATE_INPUT == this.mImeState ||
            ImeState.STATE_IDLE == this.mImeState ||
            ImeState.STATE_COMPOSING == this.mImeState) {
                newList = PinYinService.pinYinService.imGetChoiceList(fetchStart, fetchSize, this.mFixedLen);
            } else if (ImeState.STATE_PREDICT == this.mImeState) {
                newList = PinYinService.pinYinService.imGetPredictList(fetchStart, fetchSize);
            } else if (ImeState.STATE_APP_COMPLETION == this.mImeState) {
                newList = [];
                if (null != this.mAppCompletions) {
                    for (let pos = fetchStart; pos < fetchSize; pos++) {
                        /*CompletionInfo ci = mAppCompletions[pos];
                        if (null != ci) {
                            CharSequence s = ci.getText();
                            if (null != s) newList.add(s.toString());
                        }*/
                    }
                }
            }
            newList.forEach(value => {
                this.mCandidatesList.push(value);
            })

        } catch (e) {
            //Log.w(TAG, "PinyinDecoderService died", e);
        }
    }

    public pageReady(pageNo: number): boolean {
        // 如果页码小于0，则返回false
        if (pageNo < 0) return false;
        // 页面pageNo的信息未准备好。
        if (this.mPageStart.length <= pageNo + 1) {
            return false;
        }
        return true;
    }

    public preparePage(pageNo: number): boolean {
        // 如果页码小于0，则返回false
        if (pageNo < 0) return false;

        // 确保页面pageNo的起始信息已经准备好。
        if (this.mPageStart.length <= pageNo) {
            return false;
        }

        // 页面的结束信息也准备好了。
        if (this.mPageStart.length > pageNo + 1) {
            return true;
        }

        // 缓存项是否有足够的页码。
        if (this.mCandidatesList.length - this.mPageStart[pageNo] >= this.MAX_PAGE_SIZE_DISPLAY) {
            return true;
        }

        // 试着从引擎中获得更多的物品
        this.getCandiagtesForCache();

        // 试着找出是否有可用的新项目来展示。
        // 如果没有新项，返回false;
        if (this.mPageStart[pageNo] >= this.mCandidatesList.length) {
            return false;
        }

        // 如果有新项，返回true;
        return true;
    }

    // CharSequence
    public preparePredicts(history: string) {
        if (null == history) return;

        this.resetCandidates();
        if (true) {
            if (null != history) {
                try {
                    this.mTotalChoicesNum = PinYinService.pinYinService.imGetPredictsNum(history);
                } catch (e) {
                    return;
                }
            }
        }
        this.preparePage(0);
        this.mFinishSelection = false;
    }

    public getCurrentPageSize(currentPage: number): number {
        if (this.mPageStart.length <= currentPage + 1) return 0;
        return this.mPageStart[currentPage + 1] - this.mPageStart[currentPage];
        return 0;
    }

    public getCurrentPageStart(currentPage: number): number {
        if (this.mPageStart.length < currentPage + 1) return this.mTotalChoicesNum;
        return this.mPageStart[currentPage];
        return 0;
    }

    public pageForwardable(currentPage: number): boolean {
        if (this.mPageStart.length <= currentPage + 1) return false;
        if (this.mPageStart[currentPage + 1] >= this.mTotalChoicesNum) {
            return false;
        }
        return true;
    }

    public pageBackwardable(currentPage: number): boolean {
        if (currentPage > 0) return true;
        return false;
    }

    public charBeforeCursorIsSeparator(): boolean {
        let len = this.mSurface.length();
        if (this.mCursorPos > len) return false;
        if (this.mCursorPos > 0 && this.mSurface.charAt(this.mCursorPos - 1) == '\'') {
            return true;
        }
        return false;
    }

    public getCursorPos(): number {
        return this.mCursorPos;
    }

    public getCursorPosInCmps(): number {
        let cursorPos = this.mCursorPos;

        for (let hzPos = 0; hzPos < this.mFixedLen; hzPos++) {
            if (this.mCursorPos >= this.mSplStart[hzPos + 2]) {
                cursorPos -= this.mSplStart[hzPos + 2] - this.mSplStart[hzPos + 1];
                cursorPos += 1;
            }
        }
        return cursorPos;
    }

    public getCursorPosInCmpsDisplay(): number {
        let cursorPos = this.getCursorPosInCmps();
        // +2的原因: one for mSplStart[0], which is used for other purpose(The length of the segmentation string),
        // and another for the first spelling which does not need a space before it.
        for (let pos = this.mFixedLen + 2; pos < this.mSplStart.length - 1; pos++) {
            if (this.mCursorPos <= this.mSplStart[pos]) {
                break;
            } else {
                cursorPos++;
            }
        }
        return cursorPos;
    }

    public moveCursorToEdge(left: boolean) {
        if (left)
            this.mCursorPos = 0;
        else
            this.mCursorPos = this.mSurface.length();
    }

    // 移动光标。如果offset为0，则函数将游标调整到字符串的边界。
    public moveCursor(offset: number) {
        if (offset > 1 || offset < -1) return;

        if (offset != 0) {
            let hzPos = 0;
            for (hzPos = 0; hzPos <= this.mFixedLen; hzPos++) {
                if (this.mCursorPos == this.mSplStart[hzPos + 1]) {
                    if (offset < 0) {
                        if (hzPos > 0) {
                            offset = this.mSplStart[hzPos]
                            - this.mSplStart[hzPos + 1];
                        }
                    } else {
                        if (hzPos < this.mFixedLen) {
                            offset = this.mSplStart[hzPos + 2]
                            - this.mSplStart[hzPos + 1];
                        }
                    }
                    break;
                }
            }
        }
        this.mCursorPos += offset;
        if (this.mCursorPos < 0) {
            this.mCursorPos = 0;
        } else if (this.mCursorPos > this.mSurface.length()) {
            this.mCursorPos = this.mSurface.length();
        }
    }

    public getSplNum(): number {
        return this.mSplStart[0];
    }

    public getFixedLen(): number {
        return this.mFixedLen;
    }
}