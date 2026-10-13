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

# --- Developer ID signing & notarization (only when credentials exist) ---
# If a "Developer ID Application" certificate is in the keychain we sign with it
# and notarize; otherwise we fall back to an ad-hoc signature.
IDENTITY="${DEVELOPMENT_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
    IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | \
        awk -F'"' '/Developer ID Application/ {print $2; exit}')"
fi

if [ -n "$IDENTITY" ]; then
    echo "==> Signing with: $IDENTITY"
    rm -rf "$APP_DIR/Contents/_CodeSignature"
    codesign --force --deep --timestamp --options runtime --sign "$IDENTITY" "$APP_DIR"
    codesign --verify --deep --strict "$APP_DIR"
else
    echo "==> Signing ad-hoc (no Developer ID certificate found)"
    codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || \
        echo "warning: ad-hoc codesign failed (app will still run)"
fi

# Notarization accepts either an App Store Connect API key or Apple ID +
# app-specific password. Both are read from the environment.
NOTARY_KEY_ID="${NOTARY_KEY_ID:-}"
NOTARY_ISSUER_ID="${NOTARY_ISSUER_ID:-}"
NOTARY_KEY_PATH="${NOTARY_KEY_PATH:-}"
NOTARY_APPLE_ID="${NOTARY_APPLE_ID:-}"
NOTARY_APPLE_PASSWORD="${NOTARY_APPLE_PASSWORD:-}"
NOTARY_TEAM_ID="${NOTARY_TEAM_ID:-}"

DO_NOTARIZE=0
NOTARY_ARGS=()
if [ -n "$NOTARY_KEY_ID" ] && [ -n "$NOTARY_ISSUER_ID" ] && [ -n "$NOTARY_KEY_PATH" ]; then
    NOTARY_ARGS=("--key-id" "$NOTARY_KEY_ID" "--issuer-id" "$NOTARY_ISSUER_ID" "--key" "$NOTARY_KEY_PATH")
    DO_NOTARIZE=1
elif [ -n "$NOTARY_APPLE_ID" ] && [ -n "$NOTARY_APPLE_PASSWORD" ] && [ -n "$NOTARY_TEAM_ID" ]; then
    NOTARY_ARGS=("--apple-id" "$NOTARY_APPLE_ID" "--password" "$NOTARY_APPLE_PASSWORD" "--team-id" "$NOTARY_TEAM_ID")
    DO_NOTARIZE=1
fi

if [ "$DO_NOTARIZE" = "1" ]; then
    if [ -z "$IDENTITY" ]; then
        echo "error: notary credentials provided but no Developer ID certificate found." >&2
        echo "       Import your Developer ID Application certificate into the keychain first." >&2
    else
        echo "==> Notarizing…"
        ZIP_TMP="$(mktemp -d)"
        ditto -c -k --keepParent "$APP_DIR" "$ZIP_TMP/PingViewScan-notary.zip"
        if /usr/bin/xcrun notarytool submit "$ZIP_TMP/PingViewScan-notary.zip" \
                "${NOTARY_ARGS[@]}" --wait --output-format json; then
            echo "==> Stapling…"
            /usr/bin/xcrun stapler staple "$APP_DIR"
        else
            echo "error: notarization failed" >&2
        fi
        rm -rf "$ZIP_TMP"
    fi
elif [ -n "$IDENTITY" ]; then
    echo "warning: signed but NOT notarized — set NOTARY_KEY_ID/NOTARY_ISSUER_ID/NOTARY_KEY_PATH"
    echo "         (or NOTARY_APPLE_ID/NOTARY_APPLE_PASSWORD/NOTARY_TEAM_ID) to notarize."
fi

echo "==> Done: $APP_DIR"
echo "    Open with: open \"$APP_DIR\""
