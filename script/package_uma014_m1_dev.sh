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
BUILD_ROOT="${UMA014_M1_BUILD_ROOT:-/private/tmp/uma014-m1-swift-build}"
PACKAGE_ROOT="${UMA014_M1_PACKAGE_ROOT:-/Volumes/HE/DEV/UMA/Packages/$PACKAGE_STEM-$(date -u +%Y%m%d%H%M%S)}"

# Validate before invoking the compiler or creating any output. This packager
# creates a new development artifact; accepted review and installed bytes are
# never an update destination.
fail_package() {
  printf '%s\n' "$1" >&2
  exit 2
}
[[ "$BUNDLE_IDENTIFIER" =~ ^com\.silkrd\.uma\.dev\.[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*$ ]] || \
  fail_package UMA014_DEVELOPMENT_ID_REQUIRED
[[ "$APP_NAME" != */* && "$APP_NAME" != . && "$APP_NAME" != .. && \
   "$APP_NAME" != *$'\n'* && "$APP_NAME" != *$'\r'* ]] || \
  fail_package UMA014_APPLICATION_NAME_INVALID

validate_output_path() {
  local candidate="$1" current="/" component
  [[ "$candidate" == /* && "$candidate" =~ [^/] ]] || fail_package UMA014_OUTPUT_PATH_INVALID
  local remaining="${candidate#/}"
  while [[ -n "$remaining" ]]; do
    component="${remaining%%/*}"
    if [[ "$remaining" == */* ]]; then remaining="${remaining#*/}"; else remaining=""; fi
    [[ "$component" != . && "$component" != .. && "$component" != *.[aA][pP][pP] ]] || \
      fail_package UMA014_OUTPUT_PATH_INVALID
    current="${current%/}/$component"
    [[ ! -L "$current" ]] || fail_package UMA014_OUTPUT_SYMLINK_REJECTED
  done
}
validate_output_path "$BUILD_ROOT"
validate_output_path "$PACKAGE_ROOT"
APP_BUNDLE="$PACKAGE_ROOT/$APP_NAME.app"
[[ ! -e "$APP_BUNDLE" && ! -L "$APP_BUNDLE" ]] || fail_package UMA014_ARTIFACT_ALREADY_EXISTS

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
export DEVELOPER_DIR
SWIFT_BIN="$(/usr/bin/xcrun --find swift)"
SDKROOT="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"
export SDKROOT
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
HELPERS="$CONTENTS/Helpers"
RESOURCES="$CONTENTS/Resources"
INFO_PLIST="$CONTENTS/Info.plist"
EXECUTABLE="CodexUsageMonitor"
STATUS_LINE_RELAY="ClaudeStatusLineRelay"

export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$BUILD_ROOT/clang-module-cache}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-$BUILD_ROOT/swiftpm-module-cache}"
validate_output_path "$CLANG_MODULE_CACHE_PATH"
validate_output_path "$SWIFTPM_MODULECACHE_OVERRIDE"
mkdir -p "$PACKAGE_ROOT"
# Atomic reservation also refuses another invocation's artifact.
mkdir "$APP_BUNDLE" || fail_package UMA014_ARTIFACT_ALREADY_EXISTS
mkdir -p "$BUILD_ROOT" "$MACOS" "$HELPERS" "$RESOURCES" \
  "$CLANG_MODULE_CACHE_PATH" "$SWIFTPM_MODULECACHE_OVERRIDE"
cd "$ROOT_DIR"
"$SWIFT_BIN" build \
  --disable-sandbox \
  --disable-keychain --disable-netrc \
  --scratch-path "$BUILD_ROOT" \
  --configuration debug \
  --product "$EXECUTABLE"
"$SWIFT_BIN" build \
  --disable-sandbox \
  --disable-keychain --disable-netrc \
  --scratch-path "$BUILD_ROOT" \
  --configuration debug \
  --product "$STATUS_LINE_RELAY"

BIN_PATH="$("$SWIFT_BIN" build --disable-sandbox --disable-keychain --disable-netrc --scratch-path "$BUILD_ROOT" --show-bin-path)"
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
