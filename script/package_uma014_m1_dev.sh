#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_READER="$ROOT_DIR/script/read_uma_product_version.sh"
MARKETING_VERSION="$($VERSION_READER Development.MarketingVersion)"
DEFAULT_BUILD_NUMBER="$($VERSION_READER Development.DefaultBuildNumber)"
APP_NAME="${UMA014_APPLICATION_NAME:-$($VERSION_READER Development.ApplicationName)}"
BUNDLE_IDENTIFIER="${UMA014_BUNDLE_IDENTIFIER:-$($VERSION_READER Development.BundleIdentifier)}"
PACKAGE_STEM="${UMA014_PACKAGE_STEM:-$($VERSION_READER Development.PackageStem)}"
BUILD_NUMBER="${UMA014_M1_BUILD_NUMBER:-$DEFAULT_BUILD_NUMBER}"
[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || {
  printf '%s\n' "UMA014_BUILD_NUMBER_INVALID" >&2
  exit 2
}
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
export DEVELOPER_DIR
SWIFT_BIN="$(/usr/bin/xcrun --find swift)"
SDKROOT="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"
export SDKROOT
BUILD_ROOT="${UMA014_M1_BUILD_ROOT:-/private/tmp/uma014-m1-swift-build}"
PACKAGE_ROOT="${UMA014_M1_PACKAGE_ROOT:-/Volumes/HE/DEV/UMA/Packages/$PACKAGE_STEM-$(date -u +%Y%m%d%H%M%S)}"
APP_BUNDLE="$PACKAGE_ROOT/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
HELPERS="$CONTENTS/Helpers"
RESOURCES="$CONTENTS/Resources"
INFO_PLIST="$CONTENTS/Info.plist"
EXECUTABLE="CodexUsageMonitor"
STATUS_LINE_RELAY="ClaudeStatusLineRelay"

export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$BUILD_ROOT/clang-module-cache}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-$BUILD_ROOT/swiftpm-module-cache}"
mkdir -p "$BUILD_ROOT" "$MACOS" "$HELPERS" "$RESOURCES" \
  "$CLANG_MODULE_CACHE_PATH" "$SWIFTPM_MODULECACHE_OVERRIDE"
cd "$ROOT_DIR"
"$SWIFT_BIN" build \
  --disable-sandbox \
  --scratch-path "$BUILD_ROOT" \
  --configuration debug \
  --product "$EXECUTABLE"
"$SWIFT_BIN" build \
  --disable-sandbox \
  --scratch-path "$BUILD_ROOT" \
  --configuration debug \
  --product "$STATUS_LINE_RELAY"

BIN_PATH="$("$SWIFT_BIN" build --disable-sandbox --scratch-path "$BUILD_ROOT" --show-bin-path)"
/usr/bin/install -m 755 "$BIN_PATH/$EXECUTABLE" "$MACOS/$EXECUTABLE"
/usr/bin/install -m 755 \
  "$BIN_PATH/$STATUS_LINE_RELAY" \
  "$HELPERS/$STATUS_LINE_RELAY"
if [[ -f "$ROOT_DIR/Assets/AppIcon.icns" ]]; then
  /usr/bin/install -m 644 "$ROOT_DIR/Assets/AppIcon.icns" "$RESOURCES/AppIcon.icns"
fi

/usr/bin/plutil -create xml1 "$INFO_PLIST"
/usr/bin/plutil -insert CFBundleExecutable -string "$EXECUTABLE" "$INFO_PLIST"
/usr/bin/plutil -insert CFBundleIdentifier -string "$BUNDLE_IDENTIFIER" "$INFO_PLIST"
/usr/bin/plutil -insert CFBundleName -string "$APP_NAME" "$INFO_PLIST"
/usr/bin/plutil -insert CFBundleDisplayName -string "$APP_NAME" "$INFO_PLIST"
/usr/bin/plutil -insert CFBundlePackageType -string "APPL" "$INFO_PLIST"
/usr/bin/plutil -insert CFBundleShortVersionString -string "$MARKETING_VERSION" "$INFO_PLIST"
/usr/bin/plutil -insert CFBundleVersion -string "$BUILD_NUMBER" "$INFO_PLIST"
/usr/bin/plutil -insert LSMinimumSystemVersion -string "14.0" "$INFO_PLIST"
/usr/bin/plutil -insert NSPrincipalClass -string "NSApplication" "$INFO_PLIST"
if [[ -f "$RESOURCES/AppIcon.icns" ]]; then
  /usr/bin/plutil -insert CFBundleIconFile -string "AppIcon" "$INFO_PLIST"
fi

/usr/bin/plutil -lint "$INFO_PLIST"
printf '%s\n' "$APP_BUNDLE"
