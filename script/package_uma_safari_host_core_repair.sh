#!/usr/bin/env bash
# Rebuilds only the immutable Host executable while preserving every byte of
# the accepted signed Companion and its runtime generation.
set -euo pipefail
umask 077

readonly REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
readonly DELIVERY_ROOT="/Volumes/HE/DEV/UMA/Packages"
readonly DEVELOPER_DIR_REQUIRED="/Applications/Xcode-beta.app/Contents/Developer"
readonly SIGNING_IDENTITY="Apple Development: SHAOTING HE (5BN4FAQSUF)"
readonly TEAM_ID="C6TUZVJ6SJ"
readonly HOST_ID="com.silkrd.uma.test.safarihost"
readonly EXTENSION_ID="$HOST_ID.ClaudeBrowserCompanion"
readonly APP_GROUP="group.com.silkrd.uma.test.bridge"
readonly HOST_PRODUCT="UMASafariBridgeHost"
readonly TRUST_PREFLIGHT="$REPO_ROOT/script/verify_uma_apple_development_trust_context.sh"
readonly HOST_ENTITLEMENTS="$REPO_ROOT/AppleDevelopmentSigning/SafariHost/App/UMASafariHost.entitlements"

commit=""; build=""; output=""; mode=""; signing_identity=""
frozen_host=""; frozen_receipt=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --commit) commit="${2:-}"; shift 2 ;;
        --build) build="${2:-}"; shift 2 ;;
        --output) output="${2:-}"; shift 2 ;;
        --packaging-mode) mode="${2:-}"; shift 2 ;;
        --signing-identity) signing_identity="${2:-}"; shift 2 ;;
        --frozen-host) frozen_host="${2:-}"; shift 2 ;;
        --frozen-host-receipt) frozen_receipt="${2:-}"; shift 2 ;;
        *) exit 2 ;;
    esac
done
readonly expected_output="$DELIVERY_ROOT/uma-safari-host-core-repair-${commit:0:12}-$build/UMA Safari Bridge Test.zip"
[[ "$commit" =~ ^[0-9a-f]{40}$ && "$build" =~ ^[0-9]{12}$ \
    && "$mode" == SAFARI_HOST_CORE_REPAIR \
    && "$signing_identity" == "$SIGNING_IDENTITY" \
    && "$output" == "$expected_output" && ! -e "$output" && ! -L "$output" \
    && "$frozen_host" == '/Users/juliushe/Applications/UMA Safari Bridge Test.app' \
    && -d "$frozen_host" && ! -L "$frozen_host" \
    && -f "$frozen_receipt" && ! -L "$frozen_receipt" \
    && "${DEVELOPER_DIR:-}" == "$DEVELOPER_DIR_REQUIRED" ]] || exit 2
[[ -x "$TRUST_PREFLIGHT" ]] || exit 1
"$TRUST_PREFLIGHT" --mode signing

bundle_tree_sha256() {
    (cd "$1"; /usr/bin/find . -mindepth 1 -print0 | LC_ALL=C /usr/bin/sort -z |
      while IFS= read -r -d '' entry; do
        if [[ -d "$entry" ]]; then printf 'D\0%s\0%s\0' "$entry" "$(/usr/bin/stat -f %Lp "$entry")"
        elif [[ -f "$entry" ]]; then printf 'F\0%s\0%s\0%s\0' "$entry" "$(/usr/bin/stat -f %Lp "$entry")" "$(/usr/bin/shasum -a 256 "$entry" | /usr/bin/awk '{print $1}')"
        else printf 'UNSUPPORTED\0%s\0' "$entry"; fi
      done) | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}'
}
plist() { /usr/libexec/PlistBuddy -c "Print :$2" "$1"; }
cdhash() { /usr/bin/codesign -d --verbose=4 "$1" 2>&1 | /usr/bin/awk -F= '/^CDHash=/{print $2; exit}'; }
set_plist() { /usr/bin/plutil -replace "$2" -string "$3" "$1" 2>/dev/null || /usr/bin/plutil -insert "$2" -string "$3" "$1"; }

readonly frozen_appex="$frozen_host/Contents/PlugIns/ClaudeBrowserCompanion.appex"
[[ -d "$frozen_appex" && ! -L "$frozen_appex" \
    && -z "$(/usr/bin/find "$frozen_host" -type l -print -quit)" \
    && "$(plist "$frozen_receipt" schemaVersion)" == 2 \
    && "$(plist "$frozen_receipt" classification)" == IMMUTABLE_SAFARI_HOST_TEST \
    && "$(plist "$frozen_receipt" hostBundleIdentifier)" == "$HOST_ID" \
    && "$(plist "$frozen_receipt" extensionBundleIdentifier)" == "$EXTENSION_ID" \
    && "$(plist "$frozen_receipt" appGroupIdentifier)" == "$APP_GROUP" \
    && "$(plist "$frozen_receipt" teamIdentifier)" == "$TEAM_ID" \
    && "$(bundle_tree_sha256 "$frozen_host")" == "$(plist "$frozen_receipt" hostBundleSHA256)" \
    && "$(bundle_tree_sha256 "$frozen_appex")" == "$(plist "$frozen_receipt" extensionBundleSHA256)" \
    && "$(cdhash "$frozen_appex")" == "$(plist "$frozen_receipt" extensionCDHash)" ]] || {
    printf '%s\n' UNINTENDED_SAFARI_HOST_MUTATION >&2; exit 1;
}
"$TRUST_PREFLIGHT" --mode verification --artifact "$frozen_host" \
    --profile "$frozen_host/Contents/embedded.provisionprofile"
"$TRUST_PREFLIGHT" --mode verification --artifact "$frozen_appex" \
    --profile "$frozen_appex/Contents/embedded.provisionprofile"

scratch="$(/usr/bin/mktemp -d /private/tmp/uma-safari-host-core-repair.XXXXXX)"
cleanup() { /bin/rm -rf -- "$scratch"; }
trap cleanup EXIT HUP INT TERM
readonly swift_home="$scratch/home"
readonly swift_tmp="$scratch/tmp"
readonly clang_cache="$scratch/cache/clang"
readonly swiftpm_cache="$scratch/cache/swiftpm"
readonly swift_scratch="$scratch/swift"
/bin/mkdir -p "$swift_home" "$swift_tmp" "$clang_cache" "$swiftpm_cache"
pushd "$REPO_ROOT" >/dev/null
/usr/bin/env HOME="$swift_home" TMPDIR="$swift_tmp" CLANG_MODULE_CACHE_PATH="$clang_cache" \
    SWIFTPM_MODULECACHE_OVERRIDE="$swiftpm_cache" /usr/bin/xcrun swift build \
    --disable-sandbox --disable-keychain --disable-netrc --manifest-cache local \
    --scratch-path "$swift_scratch" -c release --product "$HOST_PRODUCT"
readonly bin_path="$(/usr/bin/env HOME="$swift_home" TMPDIR="$swift_tmp" CLANG_MODULE_CACHE_PATH="$clang_cache" \
    SWIFTPM_MODULECACHE_OVERRIDE="$swiftpm_cache" /usr/bin/xcrun swift build \
    --disable-sandbox --disable-keychain --disable-netrc --manifest-cache local \
    --scratch-path "$swift_scratch" -c release --show-bin-path)"
popd >/dev/null
readonly host_binary="$bin_path/$HOST_PRODUCT"
[[ -x "$host_binary" ]] || exit 1

readonly stage="$scratch/UMA Safari Bridge Test.app"
/usr/bin/ditto "$frozen_host" "$stage"
readonly stage_appex="$stage/Contents/PlugIns/ClaudeBrowserCompanion.appex"
readonly frozen_extension_digest="$(bundle_tree_sha256 "$frozen_appex")"
readonly frozen_extension_inode_identity="$(/usr/bin/stat -f '%d:%i' "$frozen_appex")"
/usr/bin/install -m 755 "$host_binary" "$stage/Contents/MacOS/$HOST_PRODUCT"
readonly final_entitlements="$scratch/host-final.entitlements.plist"
/bin/cp "$HOST_ENTITLEMENTS" "$final_entitlements"
/usr/libexec/PlistBuddy -c "Add :com.apple.application-identifier string $TEAM_ID.$HOST_ID" "$final_entitlements"
/usr/libexec/PlistBuddy -c "Add :com.apple.developer.team-identifier string $TEAM_ID" "$final_entitlements"
/usr/bin/codesign --force --sign "$SIGNING_IDENTITY" --timestamp=none \
    --identifier "$HOST_ID" --entitlements "$final_entitlements" "$stage"
/usr/bin/codesign --verify --deep --strict --verbose=4 "$stage"
"$TRUST_PREFLIGHT" --mode verification --artifact "$stage" \
    --profile "$stage/Contents/embedded.provisionprofile"
"$TRUST_PREFLIGHT" --mode verification --artifact "$stage_appex" \
    --profile "$stage_appex/Contents/embedded.provisionprofile"
[[ "$(bundle_tree_sha256 "$stage_appex")" == "$frozen_extension_digest" \
    && "$(cdhash "$stage_appex")" == "$(plist "$frozen_receipt" extensionCDHash)" \
    && "$(/usr/bin/shasum -a 256 "$stage_appex/Contents/MacOS/ClaudeBrowserCompanion" | /usr/bin/awk '{print $1}')" == "$(plist "$frozen_receipt" extensionExecutableSHA256)" ]] || {
    printf '%s\n' UNINTENDED_COMPANION_MUTATION >&2; exit 1;
}

readonly output_parent="$(dirname "$output")"
/bin/mkdir "$output_parent"
/usr/bin/ditto -c -k --keepParent "$stage" "$output"
readonly receipt="$output_parent/UMA-Safari-Host-Test.receipt.plist"
/bin/cp "$frozen_receipt" "$receipt"
set_plist "$receipt" packagingMode SAFARI_HOST_CORE_REPAIR
set_plist "$receipt" coreRepairBuild "$build"
set_plist "$receipt" sourceCommit "$commit"
set_plist "$receipt" hostExecutableSHA256 "$(/usr/bin/shasum -a 256 "$stage/Contents/MacOS/$HOST_PRODUCT" | /usr/bin/awk '{print $1}')"
set_plist "$receipt" hostCDHash "$(cdhash "$stage")"
set_plist "$receipt" hostBundleSHA256 "$(bundle_tree_sha256 "$stage")"
set_plist "$receipt" hostCodeSignatureSHA256 "$(bundle_tree_sha256 "$stage/Contents/_CodeSignature")"
set_plist "$receipt" archiveSHA256 "$(/usr/bin/shasum -a 256 "$output" | /usr/bin/awk '{print $1}')"
set_plist "$receipt" preservedExtensionSourceInode "$frozen_extension_inode_identity"
/bin/chmod 600 "$output" "$receipt"
printf 'SAFARI_HOST_CORE_REPAIR_PACKAGE output=%s receipt=%s companion_mutation=0 generation=%s\n' \
    "$output" "$receipt" "$(plist "$receipt" runtimeGenerationID)"
