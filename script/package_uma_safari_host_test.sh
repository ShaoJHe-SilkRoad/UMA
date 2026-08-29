#!/usr/bin/env bash
# Builds the independently versioned immutable Safari Host test product.
set -euo pipefail
umask 077

readonly REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
readonly DELIVERY_ROOT="/Volumes/HE/DEV/UMA/Packages"
readonly DEVELOPER_DIR_REQUIRED="/Applications/Xcode-beta.app/Contents/Developer"
readonly SIGNING_IDENTITY="Apple Development: SHAOTING HE (5BN4FAQSUF)"
readonly TEAM_ID="C6TUZVJ6SJ"
readonly HOST_ID="com.silkrd.uma.test.safarihost"
readonly EXTENSION_ID="com.silkrd.uma.test.safarihost.ClaudeBrowserCompanion"
readonly APP_GROUP="group.com.silkrd.uma.test.bridge"
readonly HOST_PRODUCT="UMASafariBridgeHost"
readonly EXTENSION_PRODUCT="ClaudeBrowserCompanion"
readonly HOST_PROFILE_NAME="UMA Safari Host Test Development v2"
readonly EXTENSION_PROFILE_NAME="UMA Claude Companion Test Development v2"
readonly PROJECT="$REPO_ROOT/AppleDevelopmentSigning/UMASafariHostSigning.xcodeproj"
readonly HOST_ENTITLEMENTS="$REPO_ROOT/AppleDevelopmentSigning/SafariHost/App/UMASafariHost.entitlements"
readonly EXTENSION_ENTITLEMENTS="$REPO_ROOT/AppleDevelopmentSigning/SafariHost/Extension/ClaudeBrowserCompanion.entitlements"
readonly TRUST_PREFLIGHT="$REPO_ROOT/script/verify_uma_apple_development_trust_context.sh"

commit=""; build=""; output=""; packaging_mode=""; signing_identity=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --commit) commit="${2:-}"; shift 2 ;;
        --build) build="${2:-}"; shift 2 ;;
        --output) output="${2:-}"; shift 2 ;;
        --packaging-mode) packaging_mode="${2:-}"; shift 2 ;;
        --signing-identity) signing_identity="${2:-}"; shift 2 ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; exit 2 ;;
    esac
done
[[ "$commit" =~ ^[0-9a-f]{40}$ && "$build" =~ ^[0-9]{12}$ \
    && "$packaging_mode" == SAFARI_HOST_MIGRATION \
    && "$signing_identity" == "$SIGNING_IDENTITY" ]] || exit 2
readonly expected_output="$DELIVERY_ROOT/uma-safari-host-test-${commit:0:12}-$build/UMA Safari Bridge Test.zip"
[[ "$output" == "$expected_output" && ! -e "$output" && ! -L "$output" ]] || {
    printf 'Refusing output outside %s\n' "$expected_output" >&2; exit 2;
}
[[ "${DEVELOPER_DIR:-}" == "$DEVELOPER_DIR_REQUIRED" ]] || {
    printf 'Required DEVELOPER_DIR=%s\n' "$DEVELOPER_DIR_REQUIRED" >&2; exit 2;
}
[[ -x "$TRUST_PREFLIGHT" ]] || exit 1
"$TRUST_PREFLIGHT" --mode signing

bundle_tree_sha256() {
    local bundle="$1"
    (cd "$bundle"; /usr/bin/find . -mindepth 1 -print0 | LC_ALL=C /usr/bin/sort -z |
        while IFS= read -r -d '' entry; do
            if [[ -d "$entry" ]]; then printf 'D\0%s\0%s\0' "$entry" "$(/usr/bin/stat -f %Lp "$entry")"
            elif [[ -f "$entry" ]]; then printf 'F\0%s\0%s\0%s\0' "$entry" "$(/usr/bin/stat -f %Lp "$entry")" "$(/usr/bin/shasum -a 256 "$entry" | /usr/bin/awk '{print $1}')"
            else printf 'UNSUPPORTED\0%s\0' "$entry"; fi
        done) | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}'
}

verify_profile_contract() {
    local profile="$1" expected_identifier="$2" expected_name="$3" decoded="$4" expiration
    /usr/bin/security cms -D -i "$profile" > "$decoded"
    expiration="$(/usr/bin/plutil -extract ExpirationDate raw "$decoded" 2>/dev/null || true)"
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.security.application-groups:0' "$decoded")" == "$APP_GROUP" \
        && "$(/usr/libexec/PlistBuddy -c 'Print :Name' "$decoded")" == "$expected_name" \
        && "$(/usr/libexec/PlistBuddy -c 'Print :TeamIdentifier:0' "$decoded")" == "$TEAM_ID" \
        && "$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.application-identifier' "$decoded")" == "$TEAM_ID.$expected_identifier" \
        && "$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.developer.team-identifier' "$decoded")" == "$TEAM_ID" \
        && "$expiration" > "$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)" ]] || {
        printf 'Provisioning profile contract mismatch for %s\n' "$expected_identifier" >&2
        exit 1
    }
    ! /usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.security.get-task-allow' "$decoded" >/dev/null 2>&1 || {
        printf 'Provisioning profile unexpectedly permits debugging for %s\n' "$expected_identifier" >&2
        exit 1
    }
}

scratch="$(/usr/bin/mktemp -d /private/tmp/uma-safari-host-package.XXXXXX)"
cleanup() { /bin/rm -rf -- "$scratch"; }
trap cleanup EXIT HUP INT TERM
readonly derived="$scratch/DerivedData"
readonly swift_scratch="$scratch/swift"

/usr/bin/xcodebuild -project "$PROJECT" -scheme UMASafariBridgeHost -configuration Release \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath "$derived" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO build >/dev/null
readonly shell_app="$derived/Build/Products/Release/UMA Safari Bridge Test.app"
readonly shell_appex="$shell_app/Contents/PlugIns/$EXTENSION_PRODUCT.appex"
[[ -d "$shell_app" && -d "$shell_appex" \
    && -f "$shell_app/Contents/embedded.provisionprofile" \
    && -f "$shell_appex/Contents/embedded.provisionprofile" ]] || {
    printf '%s\n' 'Safari Host App Group provisioning profiles are missing.' >&2; exit 1;
}
verify_profile_contract "$shell_app/Contents/embedded.provisionprofile" "$HOST_ID" \
    "$HOST_PROFILE_NAME" "$scratch/host-profile.plist"
verify_profile_contract "$shell_appex/Contents/embedded.provisionprofile" "$EXTENSION_ID" \
    "$EXTENSION_PROFILE_NAME" "$scratch/extension-profile.plist"

readonly swift_home="$scratch/home"
readonly swift_tmp="$scratch/tmp"
readonly clang_cache="$scratch/cache/clang"
readonly swiftpm_cache="$scratch/cache/swiftpm"
/bin/mkdir -p "$swift_home" "$swift_tmp" "$clang_cache" "$swiftpm_cache"
pushd "$REPO_ROOT" >/dev/null
/usr/bin/env HOME="$swift_home" TMPDIR="$swift_tmp" CLANG_MODULE_CACHE_PATH="$clang_cache" \
    SWIFTPM_MODULECACHE_OVERRIDE="$swiftpm_cache" /usr/bin/xcrun swift build \
    --disable-sandbox --disable-keychain --disable-netrc \
    --manifest-cache local --scratch-path "$swift_scratch" -c release --product "$HOST_PRODUCT"
readonly bin_path="$(/usr/bin/env HOME="$swift_home" TMPDIR="$swift_tmp" CLANG_MODULE_CACHE_PATH="$clang_cache" \
    SWIFTPM_MODULECACHE_OVERRIDE="$swiftpm_cache" /usr/bin/xcrun swift build \
    --disable-sandbox --disable-keychain --disable-netrc \
    --manifest-cache local --scratch-path "$swift_scratch" -c release --show-bin-path)"
popd >/dev/null
readonly host_binary="$bin_path/$HOST_PRODUCT"
[[ -x "$host_binary" ]] || { printf '%s\n' 'Host executable missing.' >&2; exit 1; }

readonly extension_binary="$scratch/$EXTENSION_PRODUCT"
"$DEVELOPER_DIR_REQUIRED/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc" \
    -sdk "$DEVELOPER_DIR_REQUIRED/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk" \
    -target arm64-apple-macosx14.0 -application-extension -Xlinker -application_extension \
    -O -parse-as-library \
    -module-name "$EXTENSION_PRODUCT" -I "$bin_path" \
    "$REPO_ROOT/BrowserExtension/Safari/Native/SafariWebExtensionHandler.swift" \
    "$bin_path/ClaudeBrowserBridgeProtocol.o" "$bin_path/ClaudeBrowserNativeHostCore.o" \
    -framework Foundation -framework SafariServices -Xlinker -e -Xlinker _NSExtensionMain \
    -o "$extension_binary"
readonly generation="$(/usr/bin/uuidgen | /usr/bin/tr '[:upper:]' '[:lower:]')"
readonly final_host_entitlements="$scratch/host-final.entitlements.plist"
readonly final_extension_entitlements="$scratch/extension-final.entitlements.plist"
readonly stage="$scratch/UMA Safari Bridge Test.app"
/usr/bin/ditto "$shell_app" "$stage"
readonly contents="$stage/Contents"
readonly appex="$contents/PlugIns/$EXTENSION_PRODUCT.appex"
readonly appex_contents="$appex/Contents"
/bin/rm -f -- "$contents/MacOS/UMA Safari Bridge Test"
/usr/bin/install -m 755 "$host_binary" "$contents/MacOS/$HOST_PRODUCT"
/usr/bin/install -m 755 "$extension_binary" "$appex_contents/MacOS/$EXTENSION_PRODUCT"
/bin/mkdir -p "$appex_contents/Resources/Shared" "$appex_contents/Resources/Safari"
for file in background-core.js claude-usage-extractor.js content-script.js provider-ownership-v2.js owned-provider-tab-v2-reducer.js; do
    /usr/bin/install -m 644 "$REPO_ROOT/BrowserExtension/Shared/$file" "$appex_contents/Resources/Shared/$file"
done
/usr/bin/install -m 644 "$REPO_ROOT/BrowserExtension/Safari/manifest.json" "$appex_contents/Resources/manifest.json"
readonly extension_version="$(/usr/bin/ruby -rjson -e 'print JSON.parse(File.binread(ARGV[0])).fetch("version")' "$appex_contents/Resources/manifest.json")"
readonly host_version="$extension_version"
cat > "$appex_contents/Resources/Safari/background-loader.js" <<EOF
globalThis.UMA_BROWSER_CONFIG = Object.freeze({
  browserFamily: "safari", nativeApplication: "$HOST_ID",
  supportsAutomaticRefresh: true, supportsManualAction: false,
  exactHostPermission: "https://claude.ai/new*",
  wakeMessageName: "umaClaudeWakeBridge",
  automaticRefreshMessageName: "umaClaudeAutomaticRefresh",
  closeOwnedTabMessageName: "umaClaudeCloseOwnedUsageTab",
  companionVersion: "$extension_version", companionBuild: "$build",
  protocolSchemaVersion: 2,
  containingApplicationIdentifier: "$HOST_ID",
  extensionBundleIdentifier: "$EXTENSION_ID",
  teamIdentifier: "$TEAM_ID", runtimeGenerationID: "$generation"
});
EOF
/bin/chmod 644 "$appex_contents/Resources/Safari/background-loader.js"

set_plist() { /usr/bin/plutil -replace "$2" -string "$3" "$1" 2>/dev/null || /usr/bin/plutil -insert "$2" -string "$3" "$1"; }
for plist in "$contents/Info.plist" "$appex_contents/Info.plist"; do
    set_plist "$plist" UMARuntimeChannel test-safari-host
    set_plist "$plist" UMAContainingApplicationIdentifier "$HOST_ID"
    set_plist "$plist" UMAExtensionBundleIdentifier "$EXTENSION_ID"
    set_plist "$plist" UMATeamIdentifier "$TEAM_ID"
    set_plist "$plist" UMARuntimeGenerationID "$generation"
    set_plist "$plist" UMAAppVersion "$host_version"
    set_plist "$plist" UMAAppBuild "$build"
    set_plist "$plist" UMAExtensionVersion "$extension_version"
    set_plist "$plist" UMAExtensionBuild "$build"
    set_plist "$plist" UMAAppGroupIdentifier "$APP_GROUP"
done
set_plist "$contents/Info.plist" CFBundleVersion "$build"
set_plist "$contents/Info.plist" CFBundleShortVersionString "$host_version"
set_plist "$contents/Info.plist" CFBundleExecutable "$HOST_PRODUCT"
set_plist "$appex_contents/Info.plist" CFBundleVersion "$build"
set_plist "$appex_contents/Info.plist" CFBundleShortVersionString "$extension_version"

# Preserve the exact restricted-capability contract in the final signatures.
# The package replaces Xcode's shell executables, so the final child-first
# signing pass must explicitly retain the profile-bound application and team
# identifiers in addition to the source-owned App Group entitlements.
/bin/cp "$HOST_ENTITLEMENTS" "$final_host_entitlements"
/bin/cp "$EXTENSION_ENTITLEMENTS" "$final_extension_entitlements"
for signing_contract in \
    "$final_host_entitlements:$TEAM_ID.$HOST_ID" \
    "$final_extension_entitlements:$TEAM_ID.$EXTENSION_ID"; do
    entitlements_path="${signing_contract%%:*}"
    application_identifier="${signing_contract#*:}"
    /usr/libexec/PlistBuddy -c \
        "Add :com.apple.application-identifier string $application_identifier" \
        "$entitlements_path"
    /usr/libexec/PlistBuddy -c \
        "Add :com.apple.developer.team-identifier string $TEAM_ID" \
        "$entitlements_path"
done

# Xcode supplies the restricted-capability profiles. Final signing is child-first.
/usr/bin/codesign --force --sign "$SIGNING_IDENTITY" --timestamp=none \
    --identifier "$EXTENSION_ID" --entitlements "$final_extension_entitlements" "$appex"
/usr/bin/codesign --force --sign "$SIGNING_IDENTITY" --timestamp=none \
    --identifier "$HOST_ID" --entitlements "$final_host_entitlements" "$stage"
/usr/bin/codesign --verify --deep --strict --verbose=4 "$stage"
"$TRUST_PREFLIGHT" --mode verification --artifact "$stage" \
    --profile "$contents/embedded.provisionprofile"
"$TRUST_PREFLIGHT" --mode verification --artifact "$appex" \
    --profile "$appex_contents/embedded.provisionprofile"

for target in "$stage" "$appex"; do
    entitlements="$scratch/$(basename "$target").entitlements.plist"
    /usr/bin/codesign -d --entitlements :- "$target" > "$entitlements" 2>/dev/null
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.application-groups:0' "$entitlements")" == "$APP_GROUP" ]]
    ! /usr/libexec/PlistBuddy -c 'Print :com.apple.security.get-task-allow' "$entitlements" >/dev/null 2>&1
done
host_signing_identity="$(/usr/bin/codesign -d --verbose=4 "$stage" 2>&1)"
extension_signing_identity="$(/usr/bin/codesign -d --verbose=4 "$appex" 2>&1)"
[[ "$(printf '%s\n' "$host_signing_identity" | /usr/bin/awk -F= '/^Identifier=/{print $2; exit}')" == "$HOST_ID" \
    && "$(printf '%s\n' "$host_signing_identity" | /usr/bin/awk -F= '/^TeamIdentifier=/{print $2; exit}')" == "$TEAM_ID" \
    && "$(printf '%s\n' "$extension_signing_identity" | /usr/bin/awk -F= '/^Identifier=/{print $2; exit}')" == "$EXTENSION_ID" \
    && "$(printf '%s\n' "$extension_signing_identity" | /usr/bin/awk -F= '/^TeamIdentifier=/{print $2; exit}')" == "$TEAM_ID" ]] || {
    printf '%s\n' 'Signed Host/Companion identity mismatch.' >&2; exit 1;
}
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$contents/Info.plist")" == "$HOST_ID" \
    && "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$appex_contents/Info.plist")" == "$EXTENSION_ID" \
    && "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$contents/Info.plist")" == "$HOST_PRODUCT" ]]
manifest_permissions="$(/usr/bin/ruby -rjson -e 'puts JSON.parse(File.binread(ARGV[0])).fetch("permissions").sort' "$appex_contents/Resources/manifest.json")"
[[ "$manifest_permissions" == $'https://claude.ai/new*\nnativeMessaging' ]] || {
    printf '%s\n' 'Safari Host extension permissions are not the approved exact set.' >&2; exit 1;
}

readonly output_parent="$(dirname "$output")"
/bin/mkdir "$output_parent"
/usr/bin/ditto -c -k --keepParent "$stage" "$output"
readonly receipt="$output_parent/UMA-Safari-Host-Test.receipt.plist"
host_signing="$scratch/host.signing"; appex_signing="$scratch/appex.signing"
/usr/bin/codesign -d --verbose=4 "$stage" 2> "$host_signing"
/usr/bin/codesign -d --verbose=4 "$appex" 2> "$appex_signing"
/usr/bin/plutil -create xml1 "$receipt"
/usr/bin/plutil -insert schemaVersion -integer 2 "$receipt"
/usr/bin/plutil -insert classification -string IMMUTABLE_SAFARI_HOST_TEST "$receipt"
/usr/bin/plutil -insert canonicalHostPath -string '/Users/juliushe/Applications/UMA Safari Bridge Test.app' "$receipt"
/usr/bin/plutil -insert hostBundleIdentifier -string "$HOST_ID" "$receipt"
/usr/bin/plutil -insert extensionBundleIdentifier -string "$EXTENSION_ID" "$receipt"
/usr/bin/plutil -insert appGroupIdentifier -string "$APP_GROUP" "$receipt"
/usr/bin/plutil -insert teamIdentifier -string "$TEAM_ID" "$receipt"
/usr/bin/plutil -insert runtimeGenerationID -string "$generation" "$receipt"
/usr/bin/plutil -insert protocolSchemaVersion -integer 2 "$receipt"
/usr/bin/plutil -insert hostVersion -string "$host_version" "$receipt"
/usr/bin/plutil -insert hostBuild -string "$build" "$receipt"
/usr/bin/plutil -insert extensionVersion -string "$extension_version" "$receipt"
/usr/bin/plutil -insert extensionBuild -string "$build" "$receipt"
/usr/bin/plutil -insert hostExecutableSHA256 -string "$(/usr/bin/shasum -a 256 "$contents/MacOS/$HOST_PRODUCT" | /usr/bin/awk '{print $1}')" "$receipt"
/usr/bin/plutil -insert hostCDHash -string "$(/usr/bin/awk -F= '/^CDHash=/{print $2; exit}' "$host_signing")" "$receipt"
/usr/bin/plutil -insert hostBundleSHA256 -string "$(bundle_tree_sha256 "$stage")" "$receipt"
/usr/bin/plutil -insert extensionExecutableSHA256 -string "$(/usr/bin/shasum -a 256 "$appex_contents/MacOS/$EXTENSION_PRODUCT" | /usr/bin/awk '{print $1}')" "$receipt"
/usr/bin/plutil -insert extensionCDHash -string "$(/usr/bin/awk -F= '/^CDHash=/{print $2; exit}' "$appex_signing")" "$receipt"
/usr/bin/plutil -insert extensionBundleSHA256 -string "$(bundle_tree_sha256 "$appex")" "$receipt"
/usr/bin/plutil -insert hostProfileSHA256 -string "$(/usr/bin/shasum -a 256 "$contents/embedded.provisionprofile" | /usr/bin/awk '{print $1}')" "$receipt"
/usr/bin/plutil -insert extensionProfileSHA256 -string "$(/usr/bin/shasum -a 256 "$appex_contents/embedded.provisionprofile" | /usr/bin/awk '{print $1}')" "$receipt"
/usr/bin/plutil -insert hostProfileName -string "$HOST_PROFILE_NAME" "$receipt"
/usr/bin/plutil -insert extensionProfileName -string "$EXTENSION_PROFILE_NAME" "$receipt"
/usr/bin/plutil -insert hostInfoPlistSHA256 -string "$(/usr/bin/shasum -a 256 "$contents/Info.plist" | /usr/bin/awk '{print $1}')" "$receipt"
/usr/bin/plutil -insert extensionInfoPlistSHA256 -string "$(/usr/bin/shasum -a 256 "$appex_contents/Info.plist" | /usr/bin/awk '{print $1}')" "$receipt"
/usr/bin/plutil -insert hostCodeSignatureSHA256 -string "$(bundle_tree_sha256 "$contents/_CodeSignature")" "$receipt"
/usr/bin/plutil -insert extensionCodeSignatureSHA256 -string "$(bundle_tree_sha256 "$appex_contents/_CodeSignature")" "$receipt"
/usr/bin/plutil -insert archiveSHA256 -string "$(/usr/bin/shasum -a 256 "$output" | /usr/bin/awk '{print $1}')" "$receipt"
/bin/chmod 600 "$output" "$receipt"
printf 'SAFARI_HOST_MIGRATION_PACKAGE output=%s receipt=%s generation=%s\n' "$output" "$receipt" "$generation"
