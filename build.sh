#!/bin/bash
set -euo pipefail

APP_NAME="NetSpeedMonitorSwift"
APP_BUNDLE_ID="art.anjing.NetSpeedMonitorSwift"
APP_VERSION="1.0"
APP_BUILD="1"
MIN_MACOS_VERSION="26.0"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
EXECUTABLE="$MACOS_DIR/$APP_NAME"
MODULE_CACHE_DIR="$BUILD_DIR/ModuleCache"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
TARGET_ARCH="arm64"

rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"
mkdir -p "$MODULE_CACHE_DIR"

xcrun swiftc \
    -emit-executable \
    -o "$EXECUTABLE" \
    -sdk "$SDK_PATH" \
    -module-cache-path "$MODULE_CACHE_DIR" \
    -target "$TARGET_ARCH-apple-macosx$MIN_MACOS_VERSION" \
    -framework AppKit \
    -framework SwiftUI \
    src/Logger.swift \
    src/NetSpeedMonitorApp.swift \
    src/MenuBarState.swift \
    src/MenuContentView.swift \
    src/MenuBarIconGenerator.swift \
    src/NetworkInterfaceResolver.swift \
    src/NetworkStatsMonitor.swift

cat > "$CONTENTS_DIR/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$APP_BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$APP_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$APP_BUILD</string>
    <key>LSMinimumSystemVersion</key>
    <string>$MIN_MACOS_VERSION</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF

if command -v codesign >/dev/null 2>&1; then
    codesign --force --deep --sign - "$APP_BUNDLE"
fi

printf 'Built: %s\n' "$APP_BUNDLE"
printf 'Run with: open %q\n' "$APP_BUNDLE"
