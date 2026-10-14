export const nativeImOpenDecoder: (fn_sys_dict: string, fn_usr_dict: string) => boolean;

export const nativeImOpenDecoderFd: (fd: number, startOffset: number, length: number, fn_usr_dict: string) => boolean;

export const nativeImSetMaxLens: (maxSpsLen: number, maxHzsLen: number) => void;

export const nativeImCloseDecoder: () => boolean;

export const nativeImSearch: (pyBuf: string, pyLen: number) => number;

export const nativeImDelSearch: (pos: number, is_pos_in_splid: boolean,
clear_fixed_this_step: boolean) => number;

export const nativeImResetSearch: () => void;

export const nativeImAddLetter: (ch: number) => number;

export const nativeImGetPyStr: (decoded: boolean) => string;

export const nativeImGetPyStrLen: (decoded: boolean) => number;

export const nativeImGetSplStart: () => number[];

export const nativeImGetChoice: (choiceId: number) => string;

export const nativeImChoose: (choiceId: number) => number;

export const nativeImCancelLastChoice: () => number;

export const nativeImGetFixedLen: () => number;

export const nativeImCancelInput: () => boolean;

export const nativeImFlushCache: () => boolean;

export const nativeImGetPredictsNum: (fixedStr: string) => number;

export const nativeImGetPredictItem: (predictNo: number) => string;

export const nativeSyncUserDict: (user_dict: string, tomerge: string) => string;

export const nativeSyncBegin: (user_dict: string) => boolean;

export const nativeSyncFinish: () => boolean;

export const nativeSyncGetLemmas: () => string;

export const nativeSyncPutLemmas: (tomerge: string) => number;

export const nativeSyncGetLastCount: () => number;

export const nativeSyncGetTotalCount: () => number;

export const nativeSyncClearLastGot: () => boolean;

export const nativeSyncGetCapacity: () => number;
