#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
export DEVELOPER_DIR
SWIFT_BIN="$(/usr/bin/xcrun --find swift)"
SDKROOT="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"
export SDKROOT
BUILD_ROOT="${UMA014_M1_BUILD_ROOT:-/private/tmp/uma014-m1-swift-build}"
PACKAGE_ROOT="${UMA014_M1_PACKAGE_ROOT:-/Volumes/HE/DEV/UMA/Packages/uma-0.14-m1-dev-$(date -u +%Y%m%d%H%M%S)}"
APP_BUNDLE="$PACKAGE_ROOT/UMA 0.14 Dev.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
INFO_PLIST="$CONTENTS/Info.plist"
EXECUTABLE="CodexUsageMonitor"

export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$BUILD_ROOT/clang-module-cache}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-$BUILD_ROOT/swiftpm-module-cache}"
mkdir -p "$BUILD_ROOT" "$MACOS" "$RESOURCES" \
  "$CLANG_MODULE_CACHE_PATH" "$SWIFTPM_MODULECACHE_OVERRIDE"
cd "$ROOT_DIR"
"$SWIFT_BIN" build \
  --disable-sandbox \
  --scratch-path "$BUILD_ROOT" \
  --configuration debug \
  --product "$EXECUTABLE"

BIN_PATH="$("$SWIFT_BIN" build --disable-sandbox --scratch-path "$BUILD_ROOT" --show-bin-path)"
/usr/bin/install -m 755 "$BIN_PATH/$EXECUTABLE" "$MACOS/$EXECUTABLE"
if [[ -f "$ROOT_DIR/Assets/AppIcon.icns" ]]; then
  /usr/bin/install -m 644 "$ROOT_DIR/Assets/AppIcon.icns" "$RESOURCES/AppIcon.icns"
fi

/usr/bin/plutil -create xml1 "$INFO_PLIST"
/usr/bin/plutil -insert CFBundleExecutable -string "$EXECUTABLE" "$INFO_PLIST"
/usr/bin/plutil -insert CFBundleIdentifier -string "com.silkrd.uma.dev.uma014" "$INFO_PLIST"
/usr/bin/plutil -insert CFBundleName -string "UMA 0.14 Dev" "$INFO_PLIST"
/usr/bin/plutil -insert CFBundleDisplayName -string "UMA 0.14 Dev" "$INFO_PLIST"
/usr/bin/plutil -insert CFBundlePackageType -string "APPL" "$INFO_PLIST"
/usr/bin/plutil -insert CFBundleShortVersionString -string "0.14.0" "$INFO_PLIST"
/usr/bin/plutil -insert CFBundleVersion -string "${UMA014_M1_BUILD_NUMBER:-1}" "$INFO_PLIST"
/usr/bin/plutil -insert LSMinimumSystemVersion -string "14.0" "$INFO_PLIST"
/usr/bin/plutil -insert NSPrincipalClass -string "NSApplication" "$INFO_PLIST"
if [[ -f "$RESOURCES/AppIcon.icns" ]]; then
  /usr/bin/plutil -insert CFBundleIconFile -string "AppIcon" "$INFO_PLIST"
fi

/usr/bin/plutil -lint "$INFO_PLIST"
printf '%s\n' "$APP_BUNDLE"
