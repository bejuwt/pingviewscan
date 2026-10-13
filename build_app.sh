#!/bin/bash
#
# Builds PingViewScan and assembles a double-clickable .app bundle.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

# SwiftUI's macros (@State, @Binding, ...) ship with the full Xcode toolchain,
# not the standalone Command Line Tools. Prefer Xcode when it is installed.
if [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

CONFIG="${1:-release}"
APP_NAME="PingViewScan"
APP_DIR="$ROOT/$APP_NAME.app"

echo "==> Building ($CONFIG)..."
swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)/$APP_NAME"
if [ ! -f "$BIN_PATH" ]; then
    echo "Build failed: binary not found at $BIN_PATH" >&2
    exit 1
fi

echo "==> Building app icon..."
if [ ! -f "$ROOT/Resources/AppIcon.icns" ]; then
    ICON_TMP="$(mktemp -d)"
    swiftc -O "$ROOT/Tools/make_icon.swift" -o "$ICON_TMP/make_icon"
    "$ICON_TMP/make_icon" "$ICON_TMP/icon_1024.png" 1024
    mkdir -p "$ICON_TMP/AppIcon.iconset"
    for s in 16 32 128 256 512; do
        sips -z $s $s "$ICON_TMP/icon_1024.png" --out "$ICON_TMP/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
        sips -z $((s*2)) $((s*2)) "$ICON_TMP/icon_1024.png" --out "$ICON_TMP/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICON_TMP/AppIcon.iconset" -o "$ROOT/Resources/AppIcon.icns"
    rm -rf "$ICON_TMP"
fi

echo "==> Assembling $APP_NAME.app..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"

# Ad-hoc code signature so Gatekeeper / TCC is happy with a fresh build.
codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || \
    echo "warning: ad-hoc codesign failed (app will still run)"

echo "==> Done: $APP_DIR"
echo "    Open with: open \"$APP_DIR\""
