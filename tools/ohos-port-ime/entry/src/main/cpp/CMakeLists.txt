# the minimum version of CMake.
cmake_minimum_required(VERSION 3.4.1)
project(MyApplication)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

include_directories(${NATIVERENDER_ROOT_PATH}
                    ${NATIVERENDER_ROOT_PATH}/include)

add_library(ime_pinyin SHARED
            ime_pinyin.cpp
            share/dictbuilder.cpp
            share/dictlist.cpp
            share/dicttrie.cpp
            share/lpicache.cpp
            share/matrixsearch.cpp
            share/mystdlib.cpp
            share/ngram.cpp
            share/pinyinime.cpp
            share/searchutility.cpp
            share/spellingtable.cpp
            share/spellingtrie.cpp
            share/splparser.cpp
            share/userdict.cpp
            share/utf16char.cpp
            share/utf16reader.cpp
            share/sync.cpp
            )
target_link_libraries(ime_pinyin PUBLIC libace_napi.z.so libhilog_ndk.z.so)