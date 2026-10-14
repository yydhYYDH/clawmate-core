import resourceManager from '@ohos.resourceManager';

export enum MessageType {
  CLOSE,
  INIT,
  KEY,
  RESET,
  CHOOSE,
  RESULT,
  UPDATE
}

export class PinyinMessage {
  public type: MessageType;

  constructor(_type: MessageType) {
    this.type = _type;
  }
}

export class PinyinInitMessage extends PinyinMessage {
  public descriptor: resourceManager.RawFileDescriptor;
  public filePath: string;

  constructor(_descriptor: resourceManager.RawFileDescriptor, _filePath: string) {
    super(MessageType.INIT);
    this.descriptor = _descriptor;
    this.filePath = _filePath;
  }
}

export class PinyinChooseMessage extends PinyinMessage {
  public candId: number;

  constructor(_candId: number) {
    super(MessageType.CHOOSE);
    this.candId = _candId;
  }
}

export class PinyinResultMessage extends PinyinMessage {
  public resultStr: string;

  constructor(_resultStr: string) {
    super(MessageType.RESULT);
    this.resultStr = _resultStr;
  }
}

export class PinyinKeyMessage extends PinyinMessage {
  public keyChar: string;
  public keyCode: number;

  constructor(_keyChar: string, _keyCode: number) {
    super(MessageType.KEY);
    this.keyChar = _keyChar;
    this.keyCode = _keyCode;
  }
}

export class PinyinUpdateMessage extends PinyinMessage {
  public pinyin: string;
  public candidates: string[];

  constructor(_pinyin: string, _candidates: string[]) {
    super(MessageType.UPDATE);
    this.pinyin = _pinyin;
    this.candidates = _candidates;
  }
}