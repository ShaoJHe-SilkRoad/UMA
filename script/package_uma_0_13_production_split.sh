#!/usr/bin/env bash
# Commit-exact Developer ID build for the Safari-free UMA app and immutable Safari Host.
set -euo pipefail
umask 077
readonly ROOT="$(cd "$(dirname "$0")/.." && pwd)"
readonly DELIVERY_ROOT="/Volumes/HE/DEV/UMA/Packages"
readonly VERSION="0.13.0" TEAM="C6TUZVJ6SJ"
readonly APP_ID="com.silkrd.uma" HOST_ID="com.silkrd.uma.safarihost"
readonly EXTENSION_ID="com.silkrd.uma.ClaudeBrowserCompanion"
readonly APP_GROUP="group.com.silkrd.uma.bridge"
readonly REQUIRED_IDENTITY="Developer ID Application: SHAOTING HE (C6TUZVJ6SJ)"
readonly DEVELOPER_DIR_REQUIRED="/Applications/Xcode-beta.app/Contents/Developer"
readonly SDK_REQUIRED="$DEVELOPER_DIR_REQUIRED/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk"
commit= build= output= identity= mutable_profile= host_profile= extension_profile=
while [[ $# -gt 0 ]]; do case "$1" in
  --commit) commit="${2:-}"; shift 2;; --build) build="${2:-}"; shift 2;;
  --output) output="${2:-}"; shift 2;; --signing-identity) identity="${2:-}"; shift 2;;
  --mutable-profile) mutable_profile="${2:-}"; shift 2;;
  --host-profile) host_profile="${2:-}"; shift 2;;
  --extension-profile) extension_profile="${2:-}"; shift 2;; *) exit 2;; esac
done
[[ "$commit" =~ ^[0-9a-f]{40}$ && "$build" =~ ^[0-9]{12}$ && "$identity" == "$REQUIRED_IDENTITY" ]] || exit 2
readonly expected="$DELIVERY_ROOT/uma-0.13-production-${commit:0:12}-$build"
[[ "$output" == "$expected" && ! -e "$output" && ! -L "$output" ]] || exit 2
[[ "$(git -C "$ROOT" rev-parse HEAD)" == "$commit" && -z "$(git -C "$ROOT" status --porcelain)" ]] || { echo SOURCE_NOT_COMMIT_EXACT >&2; exit 1; }
/usr/bin/security find-identity -v -p codesigning | /usr/bin/grep -Fq "\"$REQUIRED_IDENTITY\"" || { echo DEVELOPER_ID_IDENTITY_UNAVAILABLE >&2; exit 1; }
[[ -d "$DEVELOPER_DIR_REQUIRED" && -d "$SDK_REQUIRED" ]] || { echo COHERENT_XCODE_TOOLCHAIN_UNAVAILABLE >&2; exit 1; }
for p in "$mutable_profile" "$host_profile" "$extension_profile"; do [[ -f "$p" && ! -L "$p" ]] || { echo PRODUCTION_PROFILE_MISSING >&2; exit 1; }; done
scratch="$(mktemp -d /private/tmp/uma-production-package.XXXXXX)"; trap 'rm -rf -- "$scratch"' EXIT HUP INT TERM
src="$scratch/source"; mkdir "$src" "$scratch/home" "$scratch/tmp" "$scratch/cache/clang" "$scratch/cache/swiftpm" "$scratch/config" "$scratch/security"; git -C "$ROOT" archive "$commit" | tar -x -C "$src"
handler="$src/BrowserExtension/Safari/Native/SafariWebExtensionHandler.swift"
/usr/bin/grep -Fq 'productionSafariHost' "$handler" && /usr/bin/grep -Fq 'safariHostProductionAppGroupIdentifier' "$handler" || { echo PRODUCTION_HANDLER_QUALIFICATION_ABSENT >&2; exit 1; }
plist() { /usr/libexec/PlistBuddy -c "Print :$2" "$1"; }
profile_check() {
  local p="$1" id="$2" d="$3" expiration
  security cms -D -i "$p" > "$d"; expiration="$(plutil -extract ExpirationDate raw "$d")"
  [[ "$(plist "$d" TeamIdentifier:0)" == "$TEAM" && "$(plist "$d" Entitlements:com.apple.application-identifier)" == "$TEAM.$id" \
    && "$(plist "$d" Entitlements:com.apple.developer.team-identifier)" == "$TEAM" \
    && "$(plist "$d" Entitlements:com.apple.security.application-groups:0)" == "$APP_GROUP" \
    && "$(plist "$d" ProvisionsAllDevices)" == true && "$expiration" > "$(date -u +%Y-%m-%dT%H:%M:%SZ)" ]] || return 1
  ! /usr/libexec/PlistBuddy -c 'Print :ProvisionedDevices' "$d" >/dev/null 2>&1
  ! /usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.security.get-task-allow' "$d" >/dev/null 2>&1
}
profile_check "$mutable_profile" "$APP_ID" "$scratch/mutable-profile.plist" || { echo PRODUCTION_PROFILE_MISMATCH >&2; exit 1; }
profile_check "$host_profile" "$HOST_ID" "$scratch/host-profile.plist" || { echo PRODUCTION_PROFILE_MISMATCH >&2; exit 1; }
profile_check "$extension_profile" "$EXTENSION_ID" "$scratch/extension-profile.plist" || { echo PRODUCTION_PROFILE_MISMATCH >&2; exit 1; }
tree="$(git -C "$ROOT" rev-parse "$commit^{tree}")"; generation="$(uuidgen | tr '[:upper:]' '[:lower:]')"
export DEVELOPER_DIR="$DEVELOPER_DIR_REQUIRED" SDKROOT="$SDK_REQUIRED" HOME="$scratch/home" TMPDIR="$scratch/tmp" CLANG_MODULE_CACHE_PATH="$scratch/cache/clang" SWIFTPM_MODULECACHE_OVERRIDE="$scratch/cache/swiftpm"
swift="$scratch/swift"; pushd "$src" >/dev/null
swift_options=(--disable-sandbox --disable-keychain --disable-netrc --manifest-cache local --cache-path "$scratch/cache/swiftpm" --config-path "$scratch/config" --security-path "$scratch/security" --sdk "$SDK_REQUIRED" -Xswiftc -sdk -Xswiftc "$SDK_REQUIRED" --scratch-path "$swift")
for product in CodexUsageMonitor ClaudeStatusLineRelay UMASafariBridgeHost; do /usr/bin/xcrun swift build "${swift_options[@]}" -c release --product "$product"; done
bin="$(/usr/bin/xcrun swift build "${swift_options[@]}" -c release --show-bin-path)"; popd >/dev/null
app="$scratch/UMA_0.13.0.app"; host="$scratch/UMA Safari Bridge.app"; appex="$host/Contents/PlugIns/ClaudeBrowserCompanion.appex"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Helpers" "$app/Contents/Resources" "$host/Contents/MacOS" "$appex/Contents/MacOS" "$appex/Contents/Resources/Shared" "$appex/Contents/Resources/Safari"
install -m 755 "$bin/CodexUsageMonitor" "$app/Contents/MacOS/CodexUsageMonitor"; install -m 755 "$bin/ClaudeStatusLineRelay" "$app/Contents/Helpers/ClaudeStatusLineRelay"
install -m 755 "$bin/UMASafariBridgeHost" "$host/Contents/MacOS/UMASafariBridgeHost"; install -m 644 "$src/Assets/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
cp "$src/ProductionSigning/MutableApp/Info.plist" "$app/Contents/Info.plist"; cp "$src/ProductionSigning/SafariHost/App/Info.plist" "$host/Contents/Info.plist"; cp "$src/ProductionSigning/SafariHost/Extension/Info.plist" "$appex/Contents/Info.plist"
cp "$mutable_profile" "$app/Contents/embedded.provisionprofile"; cp "$host_profile" "$host/Contents/embedded.provisionprofile"; cp "$extension_profile" "$appex/Contents/embedded.provisionprofile"
/usr/bin/xcrun swiftc -sdk "$SDK_REQUIRED" -target arm64-apple-macosx14.0 -application-extension -Xlinker -application_extension -O -parse-as-library -module-name ClaudeBrowserCompanion -I "$bin" "$handler" "$bin/ClaudeBrowserBridgeProtocol.o" "$bin/ClaudeBrowserNativeHostCore.o" -framework Foundation -framework SafariServices -Xlinker -e -Xlinker _NSExtensionMain -o "$appex/Contents/MacOS/ClaudeBrowserCompanion"
for f in background-core.js claude-usage-extractor.js content-script.js provider-ownership-v2.js owned-provider-tab-v2-reducer.js; do install -m 644 "$src/BrowserExtension/Shared/$f" "$appex/Contents/Resources/Shared/$f"; done
cp "$src/BrowserExtension/Safari/manifest.json" "$appex/Contents/Resources/manifest.json"; /usr/bin/ruby -rjson -e 'p=ARGV[0]; j=JSON.parse(File.binread(p)); j["version"]="0.13.0"; File.binwrite(p,JSON.pretty_generate(j)+"\n")' "$appex/Contents/Resources/manifest.json"
/usr/bin/ruby -rjson -e 'j=JSON.parse(File.binread(ARGV[0])); s=Array(j["content_scripts"]); ok=Array(j["permissions"]).sort == ["https://claude.ai/new*","nativeMessaging"].sort && s.length == 1 && Array(s[0]["matches"]) == ["https://claude.ai/new*"] && s[0]["all_frames"] == false; abort "PRODUCTION_MANIFEST_PERMISSION_MISMATCH" unless ok' "$appex/Contents/Resources/manifest.json"
cat > "$appex/Contents/Resources/Safari/background-loader.js" <<EOF
globalThis.UMA_BROWSER_CONFIG = Object.freeze({
  browserFamily: "safari", nativeApplication: "$HOST_ID",
  supportsAutomaticRefresh: true, supportsManualAction: false,
  exactHostPermission: "https://claude.ai/new*",
  wakeMessageName: "umaClaudeWakeBridge",
  automaticRefreshMessageName: "umaClaudeAutomaticRefresh",
  closeOwnedTabMessageName: "umaClaudeCloseOwnedUsageTab",
  companionVersion: "$VERSION", companionBuild: "$build",
  protocolSchemaVersion: 2,
  containingApplicationIdentifier: "$HOST_ID",
  extensionBundleIdentifier: "$EXTENSION_ID",
  teamIdentifier: "$TEAM", runtimeGenerationID: "$generation"
});
EOF
for expected in 'supportsAutomaticRefresh: true' 'supportsManualAction: false' 'wakeMessageName: "umaClaudeWakeBridge"' 'automaticRefreshMessageName: "umaClaudeAutomaticRefresh"' 'closeOwnedTabMessageName: "umaClaudeCloseOwnedUsageTab"'; do /usr/bin/grep -Fq "$expected" "$appex/Contents/Resources/Safari/background-loader.js"; done
setv(){ plutil -replace "$2" -string "$3" "$1" 2>/dev/null || plutil -insert "$2" -string "$3" "$1"; }
setv "$app/Contents/Info.plist" CFBundleVersion "$build"; setv "$app/Contents/Info.plist" UMARuntimeGenerationID "$generation"; setv "$app/Contents/Info.plist" UMASafariHostRuntimeGenerationID "$generation"
for p in "$host/Contents/Info.plist" "$appex/Contents/Info.plist"; do setv "$p" CFBundleVersion "$build"; setv "$p" UMARuntimeChannel production-safari-host; setv "$p" UMAContainingApplicationIdentifier "$HOST_ID"; setv "$p" UMAExtensionBundleIdentifier "$EXTENSION_ID"; setv "$p" UMATeamIdentifier "$TEAM"; setv "$p" UMARuntimeGenerationID "$generation"; setv "$p" UMAAppVersion "$VERSION"; setv "$p" UMAAppBuild "$build"; setv "$p" UMAExtensionVersion "$VERSION"; setv "$p" UMAExtensionBuild "$build"; setv "$p" UMAAppGroupIdentifier "$APP_GROUP"; done
[[ ! -e "$app/Contents/PlugIns" && -z "$(find "$app" -name '*.appex' -print -quit)" ]] || { echo MUTABLE_APP_CONTAINS_SAFARI_CODE >&2; exit 1; }
xattr -cr "$app" "$host"
sign(){ codesign --force --options runtime --timestamp --sign "$REQUIRED_IDENTITY" "$@"; }
sign --identifier "$APP_ID.ClaudeStatusLineRelay" "$app/Contents/Helpers/ClaudeStatusLineRelay"; sign --identifier "$APP_ID" --entitlements "$src/ProductionSigning/MutableApp/UMA.entitlements" "$app"
sign --identifier "$EXTENSION_ID" --entitlements "$src/ProductionSigning/SafariHost/Extension/ClaudeBrowserCompanion.entitlements" "$appex"; sign --identifier "$HOST_ID" --entitlements "$src/ProductionSigning/SafariHost/App/UMA-Safari-Bridge.entitlements" "$host"
codesign --verify --deep --strict --verbose=4 "$app"; codesign --verify --deep --strict --verbose=4 "$host"
verify_signed_component() {
  local p="$1" id="$2" entitlements="$3" signing
  signing="$(codesign -d --verbose=4 "$p" 2>&1)"
  [[ "$(printf '%s\n' "$signing" | awk -F= '/^Identifier=/{print $2; exit}')" == "$id" \
    && "$(printf '%s\n' "$signing" | awk -F= '/^TeamIdentifier=/{print $2; exit}')" == "$TEAM" ]] \
    || { echo PRODUCTION_SIGNED_IDENTITY_MISMATCH >&2; exit 1; }
  printf '%s\n' "$signing" | grep -Fq 'Authority=Developer ID Application:'
  printf '%s\n' "$signing" | grep -Fq 'Timestamp='
  codesign -d --entitlements :- "$p" > "$entitlements" 2>/dev/null
  [[ "$(plutil -extract com.apple.application-identifier raw "$entitlements")" == "$TEAM.$id" \
    && "$(plutil -extract com.apple.developer.team-identifier raw "$entitlements")" == "$TEAM" \
    && "$(plutil -extract com.apple.security.application-groups.0 raw "$entitlements")" == "$APP_GROUP" ]] \
    || { echo PRODUCTION_EFFECTIVE_ENTITLEMENTS_MISMATCH >&2; exit 1; }
  ! plutil -extract com.apple.security.get-task-allow raw "$entitlements" >/dev/null 2>&1 \
    || { echo PRODUCTION_GET_TASK_ALLOW_FORBIDDEN >&2; exit 1; }
}
verify_signed_component "$app" "$APP_ID" "$scratch/app-effective-entitlements.plist"
verify_signed_component "$host" "$HOST_ID" "$scratch/host-effective-entitlements.plist"
verify_signed_component "$appex" "$EXTENSION_ID" "$scratch/appex-effective-entitlements.plist"
bundle_hash(){ (cd "$1"; find . -mindepth 1 -print0 | LC_ALL=C sort -z | while IFS= read -r -d '' e; do [[ ! -L "$e" ]] || exit 1; [[ -d "$e" ]] && printf 'D\0%s\0%s\0' "$e" "$(stat -f %Lp "$e")" || printf 'F\0%s\0%s\0%s\0' "$e" "$(stat -f %Lp "$e")" "$(shasum -a 256 "$e"|awk '{print $1}')"; done) | shasum -a 256 | awk '{print $1}'; }
stage="$scratch/release"; mkdir "$stage"; ditto "$app" "$stage/UMA_0.13.0.app"; ditto "$host" "$stage/UMA Safari Bridge.app"; mkdir "$scratch/notary"; ditto "$app" "$scratch/notary/UMA_0.13.0.app"; ditto "$host" "$scratch/notary/UMA Safari Bridge.app"; ditto -c -k --keepParent "$scratch/notary" "$stage/UMA-0.13.0-split-notary.zip"
receipt="$stage/UMA-0.13.0-pre-notary-provenance.plist"; plutil -create xml1 "$receipt"
cdhash(){ codesign -dvvv "$1" 2>&1 | awk -F= '/^CDHash=/{print $2; exit}'; }
add(){ plutil -insert "$1" -string "$2" "$receipt"; }; plutil -insert schemaVersion -integer 1 "$receipt"; add classification PRODUCTION_SPLIT_PRE_NOTARY; add sourceCommit "$commit"; add sourceTree "$tree"; add version "$VERSION"; add build "$build"; add teamIdentifier "$TEAM"; add appBundleIdentifier "$APP_ID"; add hostBundleIdentifier "$HOST_ID"; add extensionBundleIdentifier "$EXTENSION_ID"; add appGroupIdentifier "$APP_GROUP"; add runtimeGenerationID "$generation"; add appBundleSHA256 "$(bundle_hash "$app")"; add hostBundleSHA256 "$(bundle_hash "$host")"; add extensionBundleSHA256 "$(bundle_hash "$appex")"; add appExecutableSHA256 "$(shasum -a 256 "$app/Contents/MacOS/CodexUsageMonitor"|awk '{print $1}')"; add hostExecutableSHA256 "$(shasum -a 256 "$host/Contents/MacOS/UMASafariBridgeHost"|awk '{print $1}')"; add extensionExecutableSHA256 "$(shasum -a 256 "$appex/Contents/MacOS/ClaudeBrowserCompanion"|awk '{print $1}')"; add appCDHash "$(cdhash "$app")"; add hostCDHash "$(cdhash "$host")"; add extensionCDHash "$(cdhash "$appex")"; add mutableProfileSHA256 "$(shasum -a 256 "$mutable_profile"|awk '{print $1}')"; add hostProfileSHA256 "$(shasum -a 256 "$host_profile"|awk '{print $1}')"; add extensionProfileSHA256 "$(shasum -a 256 "$extension_profile"|awk '{print $1}')"; add notaryArchiveSHA256 "$(shasum -a 256 "$stage/UMA-0.13.0-split-notary.zip"|awk '{print $1}')"
mkdir -p "$(dirname "$output")"; mv "$stage" "$output"; trap - EXIT HUP INT TERM; rm -rf -- "$scratch"; printf 'PRODUCTION_SPLIT_READY_FOR_NOTARIZATION path=%s\n' "$output"
