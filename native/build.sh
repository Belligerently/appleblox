#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
source toolchain.sh
xcrun swift build -c release --disable-sandbox
BIN_DIR="$(xcrun swift build -c release --show-bin-path --disable-sandbox)"
APP="$PWD/dist/AppleBlox Native.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/AppleBloxNative" "$APP/Contents/MacOS/AppleBloxNative"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp ../LICENSE "$APP/Contents/Resources/LICENSE"
cp ../frontend/src/assets/play.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
printf 'Built %s\n' "$APP"
