#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAMP="$(date -u +%Y%m%d%H%M%S)"

export UMA014_APPLICATION_NAME="UMA 0.14 M4R Review"
export UMA014_BUNDLE_IDENTIFIER="com.silkrd.uma.dev.uma014.m4r-review"
export UMA014_PACKAGE_STEM="uma-0.14-m4r-review"
export UMA014_M1_BUILD_NUMBER="${UMA014_M4R_BUILD_NUMBER:-$STAMP}"
export UMA014_M1_PACKAGE_ROOT="${UMA014_M4R_PACKAGE_ROOT:-/Volumes/HE/DEV/UMA/Packages/uma-0.14-m4r-review-$STAMP}"
export UMA014_M1_BUILD_ROOT="${UMA014_M4R_BUILD_ROOT:-/private/tmp/uma014-m4r-review-build}"

APP_BUNDLE="$UMA014_M1_PACKAGE_ROOT/$UMA014_APPLICATION_NAME.app"
ARTIFACT_ROOT="${UMA014_M4R_REVIEW_ARTIFACTS_DIR:-$UMA014_M1_PACKAGE_ROOT/Review Artifacts}"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
export DEVELOPER_DIR
SWIFT_BIN="$(/usr/bin/xcrun --find swift)"
SDKROOT="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"
export SDKROOT
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$UMA014_M1_BUILD_ROOT/clang-module-cache}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-$UMA014_M1_BUILD_ROOT/swiftpm-module-cache}"

"$ROOT_DIR/script/package_uma014_m1_dev.sh"

mkdir -p "$ARTIFACT_ROOT" "$CLANG_MODULE_CACHE_PATH" "$SWIFTPM_MODULECACHE_OVERRIDE"
cd "$ROOT_DIR"
"$SWIFT_BIN" build --disable-sandbox --scratch-path "$UMA014_M1_BUILD_ROOT" --configuration debug --product PreviewRendererTool
BIN_PATH="$("$SWIFT_BIN" build --disable-sandbox --scratch-path "$UMA014_M1_BUILD_ROOT" --show-bin-path)"
RENDERER="$BIN_PATH/PreviewRendererTool"

render() {
  local filename="$1"
  local scenario="$2"
  shift 2
  "$RENDERER" "$ARTIFACT_ROOT/$filename" "--m3r-review=$scenario" "$@"
}

# Preview-only, fixed product-state fixtures. Provider and browser access remain zero.
render "01-quick-panel-light.png" quick --english
render "02-quick-panel-dark.png" quick --english --dark
render "03-quick-panel-white-background.png" quick --english --wallpaper=bright
render "04-quick-panel-black-background.png" quick --english --wallpaper=dark --dark
render "05-quick-panel-saturated-background.png" quick --english --wallpaper=colorful
render "06-quick-panel-reduce-transparency.png" quick --english --reduce-transparency
render "07-quick-panel-increase-contrast.png" quick --english --increase-contrast
render "08-quick-panel-alpha-mask-1x.png" quick --english --scale=1 --alpha-mask
render "09-quick-panel-alpha-mask-2x.png" quick --english --scale=2 --alpha-mask
render "10-codex-workspace-light.png" workspace-codex --english
render "11-codex-workspace-dark.png" workspace-codex --english --dark
render "12-claude-workspace-light.png" workspace-claude --english
render "13-claude-workspace-dark.png" workspace-claude --english --dark
render "14-settings-general.png" settings --english
render "15-settings-appearance.png" settings-appearance --english
render "16-settings-desktop-wizard.png" settings-wizard --english
render "17-settings-privacy.png" settings-privacy --english
render "18-settings-general-chinese.png" settings
render "19-wizard-regular-light.png" wizard-regular --english --wallpaper=bright
render "20-wizard-regular-dark.png" wizard-regular --english --wallpaper=dark --dark
render "21-wizard-minimalist-exact.png" wizard-minimalist --english --wallpaper=bright
render "22-wizard-minimalist-estimated.png" wizard-minimalist --english --wallpaper=dark --dark
render "23-main-narrow-chinese.png" main-narrow

MANIFEST="$ARTIFACT_ROOT/REVIEW-MANIFEST.json"
/usr/bin/plutil -create xml1 "$MANIFEST"
/usr/bin/plutil -insert schemaVersion -integer 1 "$MANIFEST"
/usr/bin/plutil -insert reviewAppClassification -string RUNTIME_ENABLED_NO_SYNTHETIC_PROVIDER_DATA "$MANIFEST"
/usr/bin/plutil -insert pngArtifactClassification -string SYNTHETIC_PREVIEW_ONLY "$MANIFEST"
/usr/bin/plutil -insert providerReadsDuringArtifactGeneration -integer 0 "$MANIFEST"
/usr/bin/plutil -insert contourVariants -string "light,dark,white,black,saturated,reduce-transparency,increase-contrast,alpha-1x,alpha-2x" "$MANIFEST"
/usr/bin/plutil -insert liveEvidencePolicy -string "INSPECT_LIVE_APP;DO_NOT_PERSIST_PRIVATE_QUOTA_VALUES" "$MANIFEST"
/usr/bin/plutil -convert json "$MANIFEST"

(
  cd "$ARTIFACT_ROOT"
  /usr/bin/shasum -a 256 ./*.png ./REVIEW-MANIFEST.json > SHA256SUMS
)

printf '%s\n' "REVIEW_APP=$APP_BUNDLE"
printf '%s\n' "REVIEW_ARTIFACTS=$ARTIFACT_ROOT"
printf '%s\n' "REVIEW_FIXTURES=SYNTHETIC_PREVIEW_ONLY"
