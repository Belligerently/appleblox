#!/bin/bash
if [[ -z "${DEVELOPER_DIR:-}" && "$(xcode-select -p)" == /Library/Developer/CommandLineTools && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$PWD/.build/clang-cache}"
