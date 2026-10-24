#!/bin/bash
set -euo pipefail
cd "${APPLEBLOX_NATIVE_ROOT:-$(dirname "$0")}"
source toolchain.sh
APP="$PWD/dist/AppleBlox Native.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
if [[ "${APPLEBLOX_UNIVERSAL:-0}" == 1 ]]; then
    # Separate builds work with both SwiftPM's native and Swift Build engines.
    for ARCH in arm64 x86_64; do
        xcrun swift build -c release --arch "$ARCH" --disable-sandbox
        BIN_DIR="$(xcrun swift build -c release --arch "$ARCH" --show-bin-path --disable-sandbox)"
        cp "$BIN_DIR/AppleBloxNative" ".build/AppleBloxNative-$ARCH"
    done
    lipo -create .build/AppleBloxNative-arm64 .build/AppleBloxNative-x86_64 -output "$APP/Contents/MacOS/AppleBloxNative"
else
    xcrun swift build -c release --disable-sandbox
    BIN_DIR="$(xcrun swift build -c release --show-bin-path --disable-sandbox)"
    cp "$BIN_DIR/AppleBloxNative" "$APP/Contents/MacOS/AppleBloxNative"
fi
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp ../LICENSE "$APP/Contents/Resources/LICENSE"
xcrun swiftc Sources/AppleBloxNative/ForkLogoGeometry.swift Scripts/RenderBranding.swift -o .build/render-branding
.build/render-branding "$PWD/.build/branding"
iconutil -c icns .build/branding/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon-BlueLeaf-Charcoal.icns"
cp Resources/Branding/AppleBloxFork.svg "$APP/Contents/Resources/AppleBloxFork.svg"
codesign --force --sign - "$APP"
printf 'Built %s\n' "$APP"
