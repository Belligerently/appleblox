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
xcrun swiftc Sources/AppleBloxNative/ForkLogoGeometry.swift Scripts/RenderBranding.swift -o .build/render-branding
.build/render-branding "$PWD/.build/branding"
iconutil -c icns .build/branding/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon-BlueLeaf-Dark.icns"
cp Resources/Branding/AppleBloxFork.svg "$APP/Contents/Resources/AppleBloxFork.svg"
codesign --force --sign - "$APP"
printf 'Built %s\n' "$APP"
