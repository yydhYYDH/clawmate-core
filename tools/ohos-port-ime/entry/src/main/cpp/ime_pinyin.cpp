#include "napi/native_api.h"
#include <js_native_api.h>

#include "../include/pinyinime.h"
#include "../include/sync.h"
#include "../include/userdict.h"
#include "utf16char.h"
#include <string.h>
#include <unistd.h>
#include <hilog/log.h>

#include <codecvt>
#include <iostream>
#include <locale>

using namespace ime_pinyin;

static Sync sync_worker;

#define RET_BUF_LEN 256
static char16 retbuf[RET_BUF_LEN];
static char16 (*predict_buf)[kMaxPredictSize + 1] = NULL;
static size_t predict_len;

std::wstring_convert<std::codecvt_utf8_utf16<char16_t>,char16_t> conversion;

#define LOG_DOMAIN 0x0201
#define LOG_TAG "imePinYin"

// #define IME_DEBUG

#ifdef IME_DEBUG
#define IME_LOG(format, ...) OH_LOG_INFO(LOG_APP, format)
#else
#define IME_LOG(format, ...) void
#endif

static napi_value ImOpenDecoder(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = {nullptr};

    napi_get_cb_info(env, info, &argc, args , nullptr, nullptr);
    
    char* fsd = nullptr;
    size_t fsdLen = 0;
    napi_get_value_string_utf8(env, args[0], nullptr, 0, &fsdLen);
    fsd = new char[fsdLen + 1];
    napi_get_value_string_utf8(env, args[0], fsd, fsdLen + 1, &fsdLen); 
    
    char* fud = nullptr;
    size_t fudLen = 0;
    napi_get_value_string_utf8(env, args[1], nullptr, 0, &fudLen);
    fud = new char[fudLen + 1];
    napi_get_value_string_utf8(env, args[1], fud, fudLen + 1, &fudLen);   
    
    IME_LOG("ImOpenDecoder fsd: %{public}s, fud: %{public}s\n", fsd, fud);
    bool ret = im_open_decoder((const char*)fsd, (const char*)fud);
    napi_value result;
    napi_get_boolean(env, ret, &result);
    return result;
}

static napi_value ImOpenDecoderFd(napi_env env, napi_callback_info info)
{
    size_t argc = 4;
    napi_value args[4] = {nullptr};

    napi_get_cb_info(env, info, &argc, args , nullptr, nullptr);
    
    int fd;
    napi_get_value_int32(env, args[0], &fd);    
    int64_t startOffset;
    napi_get_value_int64(env, args[1], &startOffset);  
    int64_t length;
    napi_get_value_int64(env, args[2], &length);    
    
    char* fud = nullptr;
    size_t fudLen = 0;
    napi_get_value_string_utf8(env, args[3], nullptr, 0, &fudLen);
    fud = new char[fudLen + 1];
    napi_get_value_string_utf8(env, args[3], fud, fudLen + 1, &fudLen);
    
    IME_LOG("ImOpenDecoderFd fd: %{public}d, startOffset: %{public}jd, length: %{public}jd, fud: %{public}s\n", fd, startOffset, length, fud);
    
    int newfd = dup(fd);
    bool ret = im_open_decoder_fd(newfd, startOffset, length, (const char*)fud);
    close(newfd);
    
    napi_value result;
    napi_get_boolean(env, ret, &result);
    return result;
}

static napi_value ImSetMaxLens(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = {nullptr};

    napi_get_cb_info(env, info, &argc, args , nullptr, nullptr);
    
    int max_sps_len;
    napi_get_value_int32(env, args[0], &max_sps_len);    
    int max_hzs_len;
    napi_get_value_int32(env, args[1], &max_hzs_len);   
    
    IME_LOG("ImSetMaxLens max_sps_len: %{public}d, max_hzs_len: %{public}d\n", max_sps_len, max_hzs_len);
    
    im_set_max_lens(static_cast<size_t>(max_sps_len),
                      static_cast<size_t>(max_hzs_len));
    return nullptr;
}

static napi_value ImCloseDecoder(napi_env env, napi_callback_info info)
{
    IME_LOG("ImCloseDecoder");
    im_close_decoder();
    napi_value result;
    napi_get_boolean(env, true, &result);
    return result;
}

static napi_value ImSearch(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = {nullptr};

    napi_get_cb_info(env, info, &argc, args , nullptr, nullptr);
    
    char* pybuf = nullptr;
    size_t tomergeLen = 0;
    napi_get_value_string_utf8(env, args[0], nullptr, 0, &tomergeLen);
    pybuf = new char[tomergeLen + 1];
    napi_get_value_string_utf8(env, args[0], pybuf, tomergeLen + 1, &tomergeLen); 
    
    int pyLen;
    napi_get_value_int32(env, args[1], &pyLen);
    
    IME_LOG("ImSearch pybuf: %{public}s, pyLen: %{public}d", pybuf, pyLen);
    
    int ret = im_search((const char*)pybuf, static_cast<size_t>(pyLen));
    
    napi_value result;
    napi_create_int32(env, ret, &result);
    return result;
}

static napi_value ImDelSearch(napi_env env, napi_callback_info info)
{
    size_t argc = 3;
    napi_value args[3] = {nullptr};
 
    napi_get_cb_info(env, info, &argc, args , nullptr, nullptr);
    int pos;
    napi_get_value_int32(env, args[0], &pos);
    bool is_pos_in_splid;
    napi_get_value_bool(env, args[1], &is_pos_in_splid);    
    bool clear_fixed_this_step;
    napi_get_value_bool(env, args[2], &clear_fixed_this_step); 
    
    IME_LOG("ImDelSearch pos: %{public}d, is_pos_in_splid: %{public}d, clear_fixed_this_step: %{public}d", pos, is_pos_in_splid, clear_fixed_this_step);
    
    int ret = (int)im_delsearch(static_cast<size_t>(pos), is_pos_in_splid, clear_fixed_this_step);
    
    napi_value result;
    napi_create_int32(env, ret, &result);
    return result;
}

static napi_value ImResetSearch(napi_env env, napi_callback_info info)
{
    IME_LOG("ImResetSearch");
    im_reset_search();
    return nullptr;
}

static napi_value ImAddLetter(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    
    napi_get_cb_info(env, info, &argc, args , nullptr, nullptr);
    
    uint32_t ch;
    napi_get_value_uint32(env, args[0], &ch);
    
    IME_LOG("ImAddLetter");
    
    int value = (int)im_add_letter(ch);
    
    napi_value result;
    napi_create_int32(env, value, &result);
    return result;
}

static napi_value ImGetPyStr(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    
    napi_get_cb_info(env, info, &argc, args , nullptr, nullptr);
    
    bool decoded;
    napi_get_value_bool(env, args[0], &decoded);
    
    IME_LOG("ImGetPyStr decoded: %{public}d", decoded);
    
    size_t py_len;
    const char *py = im_get_sps_str(&py_len);  
    if (!decoded)
      py_len = strlen(py);
  
    const unsigned short *spl_start;
    size_t len;
    len = im_get_spl_start_pos(spl_start);
  
    size_t i;
    for (i = 0; i < py_len; i++)
      retbuf[i] = py[i];
    retbuf[i] = (char16)'\0';
    
    napi_value result;
    //napi_create_string_utf8(env, (const char *)retbuf, i, &result);
    std::string tmp = conversion.to_bytes((char16_t *)retbuf);
    napi_create_string_utf8(env, tmp.c_str(), tmp.length(), &result);
    return result;
}

static napi_value ImGetPyStrLen(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    
    napi_get_cb_info(env, info, &argc, args , nullptr, nullptr);
    
    bool decoded;
    napi_get_value_bool(env, args[0], &decoded);   
    
    IME_LOG("ImGetPyStrLen decoded: %{public}d", decoded);
    
    size_t py_len;
    const char *py = im_get_sps_str(&py_len); 
    if (!decoded)
        py_len = strlen(py);
    
    napi_value result;
    napi_create_int32(env, (int)py_len, &result);
    return result;
}

static napi_value ImGetSplStart(napi_env env, napi_callback_info info)
{
    IME_LOG("ImGetSplStart");
    napi_value result;
    
    const unsigned short *spl_start;
    size_t len;
    
    // There will be len + 1 elements in the buffer when len > 0.
    len = im_get_spl_start_pos(spl_start);
    
    napi_create_array(env, &result);
    napi_value lenValue;
    napi_create_int32(env, len, &lenValue);
    napi_set_element(env, result, 0, lenValue);
    
    for (size_t i = 0; i <= len; i++) {
        napi_value num;
        napi_create_int32(env, spl_start[i], &num);
        napi_set_element(env, result, i + 1, num);
    }
    
    return result;
}

static napi_value ImGetChoice(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    
    napi_get_cb_info(env, info, &argc, args , nullptr, nullptr);
    
    int choiceId;
    napi_get_value_int32(env, args[0], &choiceId);
    
    IME_LOG("ImGetChoice choiceId: %{public}d", choiceId);
    
    napi_value result;
    if(im_get_candidate(choiceId, retbuf, RET_BUF_LEN)) {
        std::string tmp = conversion.to_bytes((char16_t *)retbuf);
        napi_create_string_utf8(env, tmp.c_str(), tmp.length(), &result);
    } else {
        napi_create_string_utf8(env, (const char *)retbuf, 0, &result);
    }
    return result;
}

static napi_value ImChoose(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    
    napi_get_cb_info(env, info, &argc, args , nullptr, nullptr);
    
    int choiceId;
    napi_get_value_int32(env, args[0], &choiceId);
    
    IME_LOG("ImChoose choiceId: %{public}d", choiceId);
    
    int value = (int)im_choose(choiceId);
    napi_value result;
    napi_create_int32(env, value, &result);
    return result;
}

static napi_value ImCancelLastChoice(napi_env env, napi_callback_info info)
{
    IME_LOG("ImCancelLastChoice");
    int value = (int)im_cancel_last_choice();
    napi_value result;
    napi_create_int32(env, value, &result);
    return result;
}

static napi_value ImGetFixedLen(napi_env env, napi_callback_info info)
{
    IME_LOG("ImGetFixedLen");
    int value = (int)im_get_fixed_len();
    napi_value result;
    napi_create_int32(env, value, &result);
    return result;
}

static napi_value ImCancelInput(napi_env env, napi_callback_info info)
{
    IME_LOG("ImCancelInput");
    bool value = im_cancel_input();
    napi_value result;
    napi_get_boolean(env, value, &result);
    return result;
}

static napi_value ImFlushCache(napi_env env, napi_callback_info info)
{
    IME_LOG("ImFlushCache");
    im_flush_cache();
    napi_value result;
    napi_get_boolean(env, true, &result);
    return result;
}

static napi_value ImGetPredictsNum(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = {nullptr};
 
    napi_get_cb_info(env, info, &argc, args , nullptr, nullptr);
    
    char* fixed = nullptr;
    size_t fixedLen = 0;
    napi_get_value_string_utf8(env, args[0], nullptr, 0, &fixedLen);
    fixed = new char[fixedLen + 1];
    napi_get_value_string_utf8(env, args[0], fixed, fixedLen + 1, &fixedLen); 
    
    IME_LOG("ImGetPredictsNum fixed: %{public}s", fixed);
    
    char16 fixed_buf[kMaxPredictSize + 1];
    
    if (fixedLen > kMaxPredictSize) {
        fixed += fixedLen - kMaxPredictSize;
        fixedLen = kMaxPredictSize;
    }
    utf16_strncpy(fixed_buf, (char16*)fixed, fixedLen);
    fixed_buf[fixedLen] = (char16)'\0';
    
    predict_len = im_get_predicts(fixed_buf, predict_buf);
    
    napi_value result;
    napi_create_int32(env, (int)predict_len, &result);
    return result;
}

static napi_value ImGetPredictItem(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    
    napi_get_cb_info(env, info, &argc, args , nullptr, nullptr);
    
    int predictNo;
    napi_get_value_int32(env, args[0], &predictNo);  
    
    IME_LOG("ImGetPredictItem predictNo: %{public}d", predictNo);
    
    sync_worker.finish();
    
    napi_value result;
    
    if (predictNo < 0 || (size_t)predictNo >= predict_len) {
        napi_create_string_utf8(env, (const char *)predict_buf[0], 0, &result);
    } else {
        napi_create_string_utf8(env, (const char *)predict_buf[predictNo], utf16_strlen(predict_buf[predictNo]), &result);
    }
    return result;
}

static napi_value SyncUserDict(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = {nullptr};
 
    napi_get_cb_info(env, info, &argc, args , nullptr, nullptr);
    
    char* userDict = nullptr;
    size_t userDictLen = 0;
    napi_get_value_string_utf8(env, args[0], nullptr, 0, &userDictLen);
    userDict = new char[userDictLen + 1];
    napi_get_value_string_utf8(env, args[0], userDict, userDictLen + 1, &userDictLen); 
    
    char* toMerge = nullptr;
    size_t toMergeLen = 0;
    napi_get_value_string_utf8(env, args[1], nullptr, 0, &toMergeLen);
    toMerge = new char[toMergeLen + 1];
    napi_get_value_string_utf8(env, args[1], toMerge, toMergeLen + 1, &toMergeLen);  
    
    IME_LOG("SyncUserDict userDict: %{public}s, toMerge: %{public}s", userDict, toMerge);
    
    napi_value result;
    
    std::string ret= "test";
    napi_create_string_utf8(env, ret.c_str(), ret.length(), &result);
    return result;
}

static napi_value SyncBegin(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = {nullptr};
 
    napi_get_cb_info(env, info, &argc, args , nullptr, nullptr);
    
    char* userDict = nullptr;
    size_t userDictLen = 0;
    napi_get_value_string_utf8(env, args[0], nullptr, 0, &userDictLen);
    userDict = new char[userDictLen + 1];
    napi_get_value_string_utf8(env, args[0], userDict, userDictLen + 1, &userDictLen);
    
    IME_LOG("SyncBegin userDict: %{public}s", userDict);
    
    bool ret = sync_worker.begin((const char *)userDict);
    
    napi_value result;
    napi_get_boolean(env, ret, &result);
    return result;
}

static napi_value SyncFinish(napi_env env, napi_callback_info info)
{
    IME_LOG("SyncFinish");
    sync_worker.finish();
    napi_value result;
    napi_get_boolean(env, true, &result);
    return result;
}

static napi_value SyncGetLemmas(napi_env env, napi_callback_info info)
{
    IME_LOG("SyncGetLemmas");
    int len = sync_worker.get_lemmas(retbuf, RET_BUF_LEN);
    if (len == 0)
        return nullptr;
    napi_value result;
    
    std::string tmp = conversion.to_bytes((char16_t *)retbuf);
    napi_create_string_utf8(env, tmp.c_str(), tmp.length(), &result);
    return result;
}

static napi_value SyncPutLemmas(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = {nullptr};
 
    napi_get_cb_info(env, info, &argc, args , nullptr, nullptr);
    
    char* tomerge = nullptr;
    size_t tomergeLen = 0;
    napi_get_value_string_utf8(env, args[0], nullptr, 0, &tomergeLen);
    tomerge = new char[tomergeLen + 1];
    napi_get_value_string_utf8(env, args[0], tomerge, tomergeLen + 1, &tomergeLen);
    
    IME_LOG("SyncPutLemmas tomerge: %{public}s", tomerge);
    int added = sync_worker.put_lemmas((char16*)tomerge, tomergeLen);
    napi_value result;
    napi_create_int32(env, added, &result);
    return result;
}

static napi_value SyncGetLastCount(napi_env env, napi_callback_info info)
{
    IME_LOG("SyncGetLastCount");
    int capacity = sync_worker.get_last_got_count();
    napi_value result;
    napi_create_int32(env, capacity, &result);
    return result;
}

static napi_value SyncGetTotalCount(napi_env env, napi_callback_info info)
{
    IME_LOG("SyncGetTotalCount");
    int capacity = sync_worker.get_total_count();
    napi_value result;
    napi_create_int32(env, capacity, &result);
    return result;
}

static napi_value SyncClearLastGot(napi_env env, napi_callback_info info)
{
    IME_LOG("SyncClearLastGot");
    sync_worker.clear_last_got();
    napi_value result;
    napi_get_boolean(env, true, &result);
    return result;
}

static napi_value SyncGetCapacity(napi_env env, napi_callback_info info)
{
    IME_LOG("SyncGetCapacity");
    int capacity = sync_worker.get_capacity();
    napi_value result;
    napi_create_int32(env, capacity, &result);
    return result;
}

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        { "nativeImOpenDecoder", nullptr, ImOpenDecoder, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "nativeImOpenDecoderFd", nullptr, ImOpenDecoderFd, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "nativeImSetMaxLens", nullptr, ImSetMaxLens, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "nativeImCloseDecoder", nullptr, ImCloseDecoder, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "nativeImSearch", nullptr, ImSearch, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "nativeImDelSearch", nullptr, ImDelSearch, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "nativeImResetSearch", nullptr, ImResetSearch, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "nativeImAddLetter", nullptr, ImAddLetter, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "nativeImGetPyStr", nullptr, ImGetPyStr, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "nativeImGetPyStrLen", nullptr, ImGetPyStrLen, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "nativeImGetSplStart", nullptr, ImGetSplStart, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "nativeImGetChoice", nullptr, ImGetChoice, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "nativeImChoose", nullptr, ImChoose, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "nativeImCancelLastChoice", nullptr, ImCancelLastChoice, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "nativeImGetFixedLen", nullptr, ImGetFixedLen, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "nativeImCancelInput", nullptr, ImCancelInput, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "nativeImFlushCache", nullptr, ImFlushCache, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "nativeImGetPredictsNum", nullptr, ImGetPredictsNum, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "nativeImGetPredictItem", nullptr, ImGetPredictItem, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "nativeSyncGetLastCount", nullptr, SyncGetLastCount, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "nativeSyncGetTotalCount", nullptr, SyncGetTotalCount, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "nativeSyncClearLastGot", nullptr, SyncClearLastGot, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "nativeSyncGetCapacity", nullptr, SyncGetCapacity, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "nativeSyncUserDict", nullptr, SyncUserDict, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "nativeSyncBegin", nullptr, SyncBegin, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "nativeSyncFinish", nullptr, SyncFinish, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "nativeSyncGetLemmas", nullptr, SyncGetLemmas, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "nativeSyncPutLemmas", nullptr, SyncPutLemmas, nullptr, nullptr, nullptr, napi_default, nullptr }    
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END

static napi_module demoModule = {
    .nm_version =1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "entry",
    .nm_priv = ((void*)0),
    .reserved = { 0 },
};

extern "C" __attribute__((constructor)) void RegisterEntryModule(void)
{
    napi_module_register(&demoModule);
}
