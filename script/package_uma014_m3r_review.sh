#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAMP="$(date -u +%Y%m%d%H%M%S)"

export UMA014_APPLICATION_NAME="UMA 0.14 Surface Review"
export UMA014_BUNDLE_IDENTIFIER="com.silkrd.uma.dev.uma014.surface-rebuild"
export UMA014_PACKAGE_STEM="uma-0.14-surface-rebuild-review"
export UMA014_M1_BUILD_NUMBER="${UMA014_M3R_BUILD_NUMBER:-$STAMP}"
export UMA014_M1_PACKAGE_ROOT="${UMA014_M3R_PACKAGE_ROOT:-/Volumes/HE/DEV/UMA/Packages/uma-0.14-surface-rebuild-review-$STAMP}"
export UMA014_M1_BUILD_ROOT="${UMA014_M3R_BUILD_ROOT:-/private/tmp/uma014-m3r-review-build}"

APP_BUNDLE="$UMA014_M1_PACKAGE_ROOT/$UMA014_APPLICATION_NAME.app"
ARTIFACT_ROOT="${UMA014_M3R_REVIEW_ARTIFACTS_DIR:-$UMA014_M1_PACKAGE_ROOT/Review Artifacts}"
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
"$SWIFT_BIN" build \
  --disable-sandbox \
  --scratch-path "$UMA014_M1_BUILD_ROOT" \
  --configuration debug \
  --product PreviewRendererTool
BIN_PATH="$("$SWIFT_BIN" build --disable-sandbox --scratch-path "$UMA014_M1_BUILD_ROOT" --show-bin-path)"
RENDERER="$BIN_PATH/PreviewRendererTool"

render() {
  local filename="$1"
  local scenario="$2"
  shift 2
  "$RENDERER" \
    "$ARTIFACT_ROOT/$filename" \
    "--m3r-review=$scenario" \
    "$@"
}

# This matrix uses preview-only UsageStore instances, fixed synthetic usage
# records, and in-memory preferences. It never starts a provider connector or
# reads the user's persisted preference domain.
render "01-quick-panel-light.png" quick --english
render "02-quick-panel-dark.png" quick --english --dark
render "03-quick-panel-zero-providers.png" quick-zero --english
render "04-quick-panel-degraded.png" quick-degraded --english
render "05-quick-panel-chinese.png" quick
render "06-main-codex-light.png" main --english
render "07-main-codex-dark.png" main --english --dark
render "08-main-narrow-claude.png" main-narrow --english
render "09-codex-workspace.png" workspace-codex --english
render "10-claude-workspace.png" workspace-claude --english
render "11-global-settings.png" settings --english
render "12-desktop-wizard-regular.png" wizard-regular --english --wallpaper=bright
render "13-desktop-wizard-minimalist.png" wizard-minimalist --english --wallpaper=dark --dark
render "14-threados-placeholder.png" threados --english
render "15-quick-panel-edge-bright-2x.png" quick-edge --english --wallpaper=bright --scale=2
render "16-quick-panel-edge-dark-2x.png" quick-edge --english --wallpaper=dark --dark --scale=2
render "17-quick-panel-one-agent.png" quick-one --english
render "18-quick-panel-reduce-transparency.png" quick --english --reduce-transparency
render "19-quick-panel-increase-contrast.png" quick --english --increase-contrast
render "20-quick-panel-reduce-motion.png" quick --english --reduce-motion
render "21-quick-panel-edge-bright-1x.png" quick-edge --english --wallpaper=bright --scale=1
render "22-quick-panel-edge-dark-1x.png" quick-edge --english --wallpaper=dark --dark --scale=1
render "23-quick-panel-alpha-mask-2x.png" quick --english --scale=2 --alpha-mask
render "24-quick-panel-alpha-mask-1x.png" quick --english --scale=1 --alpha-mask
render "25-desktop-wizard-context-menu.png" wizard-context-menu --english --wallpaper=bright

MANIFEST="$ARTIFACT_ROOT/REVIEW-MANIFEST.json"
/usr/bin/plutil -create xml1 "$MANIFEST"
/usr/bin/plutil -insert schemaVersion -integer 1 "$MANIFEST"
/usr/bin/plutil -insert reviewAppClassification -string RUNTIME_ENABLED_NO_SYNTHETIC_PROVIDER_DATA "$MANIFEST"
/usr/bin/plutil -insert pngArtifactClassification -string SYNTHETIC_PREVIEW_ONLY "$MANIFEST"
/usr/bin/plutil -insert providerReadsDuringArtifactGeneration -integer 0 "$MANIFEST"
/usr/bin/plutil -insert renderedScales -string "1x,2x" "$MANIFEST"
/usr/bin/plutil -insert accessibilityVariants -string "reduce-transparency,increase-contrast,reduce-motion" "$MANIFEST"
/usr/bin/plutil -insert liveEvidencePolicy -string "INSPECT_LIVE_APP;DO_NOT_PERSIST_PRIVATE_QUOTA_VALUES" "$MANIFEST"
/usr/bin/plutil -convert json "$MANIFEST"

(
  cd "$ARTIFACT_ROOT"
  /usr/bin/shasum -a 256 ./*.png ./REVIEW-MANIFEST.json > SHA256SUMS
)

printf '%s\n' "REVIEW_APP=$APP_BUNDLE"
printf '%s\n' "REVIEW_ARTIFACTS=$ARTIFACT_ROOT"
printf '%s\n' "REVIEW_FIXTURES=SYNTHETIC_PREVIEW_ONLY"
