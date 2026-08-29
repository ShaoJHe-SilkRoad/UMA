#!/usr/bin/env bash
# Builds only the mutable UMA Test app. It never contains or registers Safari code.
set -euo pipefail
umask 077
readonly REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
readonly DELIVERY_ROOT="/Volumes/HE/DEV/UMA/Packages"
readonly APP_ID="com.silkrd.uma.test"
readonly APP_GROUP="group.com.silkrd.uma.test.bridge"
readonly HOST_ID="com.silkrd.uma.test.safarihost"
readonly EXTENSION_ID="$HOST_ID.ClaudeBrowserCompanion"
readonly TEAM_ID="C6TUZVJ6SJ"
readonly SIGNING_IDENTITY="Apple Development: SHAOTING HE (5BN4FAQSUF)"
readonly MUTABLE_PROFILE_NAME="UMA Mutable App Test Development"
readonly HOST_EXECUTABLE="UMASafariBridgeHost"
readonly EXTENSION_EXECUTABLE="ClaudeBrowserCompanion"
readonly APP_ENTITLEMENTS="$REPO_ROOT/AppleDevelopmentSigning/MutableApp/UMAApp.entitlements"
readonly MUTABLE_PROJECT="$REPO_ROOT/AppleDevelopmentSigning/UMAMutableAppSigning.xcodeproj"
readonly DEVELOPER_DIR_REQUIRED="/Applications/Xcode-beta.app/Contents/Developer"
readonly TRUST_PREFLIGHT="$REPO_ROOT/script/verify_uma_apple_development_trust_context.sh"

commit=""; build=""; phase=""; output=""; mode=""; identity=""; host=""; host_receipt=""
while [[ $# -gt 0 ]]; do case "$1" in
    --commit) commit="${2:-}"; shift 2;; --build) build="${2:-}"; shift 2;;
    --phase) phase="${2:-}"; shift 2;; --output) output="${2:-}"; shift 2;;
    --signing-identity) identity="${2:-}"; shift 2;; --packaging-mode) mode="${2:-}"; shift 2;;
    --immutable-safari-host) host="${2:-}"; shift 2;;
    --immutable-host-receipt) host_receipt="${2:-}"; shift 2;;
    --keychain-profile) [[ -z "${2:-}" ]] || exit 2; shift 2;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; exit 2;;
esac; done
[[ "$commit" =~ ^[0-9a-f]{40}$ && "$build" =~ ^[0-9]{12}$ \
    && "$phase" == apple-development-test && "$mode" == UMA_APP_ONLY \
    && "$identity" == "$SIGNING_IDENTITY" ]] || exit 2
readonly expected="$DELIVERY_ROOT/uma-0.13-apple-dev-test-${commit:0:12}-$build/UMA_0.13.0-Test.zip"
[[ "$output" == "$expected" && ! -e "$output" && ! -L "$output" ]] || exit 2
[[ "${DEVELOPER_DIR:-}" == "$DEVELOPER_DIR_REQUIRED" ]] || exit 2
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
verify_host_lock() {
    [[ "$host" == '/Users/juliushe/Applications/UMA Safari Bridge Test.app' \
        && -d "$host" && ! -L "$host" && -f "$host_receipt" && ! -L "$host_receipt" \
        && -z "$(/usr/bin/find "$host" -type l -print -quit)" ]] || return 1
    local appex="$host/Contents/PlugIns/$EXTENSION_EXECUTABLE.appex"
    [[ -d "$appex" && "$(plist "$host_receipt" schemaVersion)" == 2 \
        && "$(plist "$host_receipt" classification)" == IMMUTABLE_SAFARI_HOST_TEST \
        && "$(plist "$host_receipt" hostBundleIdentifier)" == "$HOST_ID" \
        && "$(plist "$host_receipt" extensionBundleIdentifier)" == "$EXTENSION_ID" \
        && "$(plist "$host_receipt" appGroupIdentifier)" == "$APP_GROUP" \
        && "$(plist "$host_receipt" teamIdentifier)" == "$TEAM_ID" \
        && "$(bundle_tree_sha256 "$host")" == "$(plist "$host_receipt" hostBundleSHA256)" \
        && "$(bundle_tree_sha256 "$appex")" == "$(plist "$host_receipt" extensionBundleSHA256)" \
        && "$(/usr/bin/shasum -a 256 "$host/Contents/Info.plist" | /usr/bin/awk '{print $1}')" == "$(plist "$host_receipt" hostInfoPlistSHA256)" \
        && "$(/usr/bin/shasum -a 256 "$appex/Contents/Info.plist" | /usr/bin/awk '{print $1}')" == "$(plist "$host_receipt" extensionInfoPlistSHA256)" \
        && "$(bundle_tree_sha256 "$host/Contents/_CodeSignature")" == "$(plist "$host_receipt" hostCodeSignatureSHA256)" \
        && "$(bundle_tree_sha256 "$appex/Contents/_CodeSignature")" == "$(plist "$host_receipt" extensionCodeSignatureSHA256)" \
        && "$(/usr/bin/shasum -a 256 "$host/Contents/embedded.provisionprofile" | /usr/bin/awk '{print $1}')" == "$(plist "$host_receipt" hostProfileSHA256)" \
        && "$(/usr/bin/shasum -a 256 "$appex/Contents/embedded.provisionprofile" | /usr/bin/awk '{print $1}')" == "$(plist "$host_receipt" extensionProfileSHA256)" \
        && "$(/usr/bin/shasum -a 256 "$host/Contents/MacOS/$HOST_EXECUTABLE" | /usr/bin/awk '{print $1}')" == "$(plist "$host_receipt" hostExecutableSHA256)" \
        && "$(/usr/bin/shasum -a 256 "$appex/Contents/MacOS/$EXTENSION_EXECUTABLE" | /usr/bin/awk '{print $1}')" == "$(plist "$host_receipt" extensionExecutableSHA256)" ]] || return 1
    /usr/bin/codesign --verify --deep --strict --verbose=2 "$host"
    local host_signing appex_signing
    host_signing="$(/usr/bin/codesign -d --verbose=4 "$host" 2>&1)"
    appex_signing="$(/usr/bin/codesign -d --verbose=4 "$appex" 2>&1)"
    [[ "$(printf '%s\n' "$host_signing" | /usr/bin/awk -F= '/^Identifier=/{print $2; exit}')" == "$HOST_ID" \
        && "$(printf '%s\n' "$host_signing" | /usr/bin/awk -F= '/^TeamIdentifier=/{print $2; exit}')" == "$TEAM_ID" \
        && "$(printf '%s\n' "$host_signing" | /usr/bin/awk -F= '/^CDHash=/{print $2; exit}')" == "$(plist "$host_receipt" hostCDHash)" \
        && "$(printf '%s\n' "$appex_signing" | /usr/bin/awk -F= '/^Identifier=/{print $2; exit}')" == "$EXTENSION_ID" \
        && "$(printf '%s\n' "$appex_signing" | /usr/bin/awk -F= '/^TeamIdentifier=/{print $2; exit}')" == "$TEAM_ID" \
        && "$(printf '%s\n' "$appex_signing" | /usr/bin/awk -F= '/^CDHash=/{print $2; exit}')" == "$(plist "$host_receipt" extensionCDHash)" ]]
}
verify_host_lock || { printf '%s\n' UNINTENDED_SAFARI_HOST_MUTATION >&2; exit 1; }
readonly pre_host_digest="$(bundle_tree_sha256 "$host")"

scratch="$(/usr/bin/mktemp -d /private/tmp/uma-app-only-package.XXXXXX)"; trap '/bin/rm -rf -- "$scratch"' EXIT HUP INT TERM
readonly swift_home="$scratch/home"
readonly swift_tmp="$scratch/tmp"
readonly clang_cache="$scratch/cache/clang"
readonly swiftpm_cache="$scratch/cache/swiftpm"
/bin/mkdir -p "$swift_home" "$swift_tmp" "$clang_cache" "$swiftpm_cache"
readonly derived="$scratch/DerivedData"
/usr/bin/xcodebuild -project "$MUTABLE_PROJECT" -scheme UMAMutableTestApp -configuration Release \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath "$derived" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO build >/dev/null
readonly mutable_shell="$derived/Build/Products/Release/UMA_0.13.0-Test.app"
[[ -f "$mutable_shell/Contents/embedded.provisionprofile" ]] || {
    printf '%s\n' 'Mutable App Group provisioning profile is missing.' >&2; exit 1;
}
/usr/bin/security cms -D -i "$mutable_shell/Contents/embedded.provisionprofile" > "$scratch/mutable-profile.plist"
mutable_profile_expiration="$(/usr/bin/plutil -extract ExpirationDate raw "$scratch/mutable-profile.plist" 2>/dev/null || true)"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :Name' "$scratch/mutable-profile.plist")" == "$MUTABLE_PROFILE_NAME" \
    && "$(/usr/libexec/PlistBuddy -c 'Print :TeamIdentifier:0' "$scratch/mutable-profile.plist")" == "$TEAM_ID" \
    && "$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.security.application-groups:0' "$scratch/mutable-profile.plist")" == "$APP_GROUP" \
    && "$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.application-identifier' "$scratch/mutable-profile.plist")" == "$TEAM_ID.$APP_ID" \
    && "$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.developer.team-identifier' "$scratch/mutable-profile.plist")" == "$TEAM_ID" \
    && "$mutable_profile_expiration" > "$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)" ]] || exit 1
! /usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.security.get-task-allow' "$scratch/mutable-profile.plist" >/dev/null 2>&1 || exit 1
pushd "$REPO_ROOT" >/dev/null
/usr/bin/env HOME="$swift_home" TMPDIR="$swift_tmp" CLANG_MODULE_CACHE_PATH="$clang_cache" \
    SWIFTPM_MODULECACHE_OVERRIDE="$swiftpm_cache" /usr/bin/xcrun swift build \
    --disable-sandbox --disable-keychain --disable-netrc --manifest-cache local \
    --scratch-path "$scratch/swift" -c release --product CodexUsageMonitor
/usr/bin/env HOME="$swift_home" TMPDIR="$swift_tmp" CLANG_MODULE_CACHE_PATH="$clang_cache" \
    SWIFTPM_MODULECACHE_OVERRIDE="$swiftpm_cache" /usr/bin/xcrun swift build \
    --disable-sandbox --disable-keychain --disable-netrc --manifest-cache local \
    --scratch-path "$scratch/swift" -c release --product ClaudeStatusLineRelay
readonly bin="$(/usr/bin/env HOME="$swift_home" TMPDIR="$swift_tmp" CLANG_MODULE_CACHE_PATH="$clang_cache" \
    SWIFTPM_MODULECACHE_OVERRIDE="$swiftpm_cache" /usr/bin/xcrun swift build \
    --disable-sandbox --disable-keychain --disable-netrc --manifest-cache local \
    --scratch-path "$scratch/swift" -c release --show-bin-path)"
popd >/dev/null

readonly app="$scratch/UMA_0.13.0-Test.app"; readonly contents="$app/Contents"
/bin/mkdir -p "$contents/MacOS" "$contents/Helpers" "$contents/Resources"
/usr/bin/install -m 755 "$bin/CodexUsageMonitor" "$contents/MacOS/CodexUsageMonitor"
/usr/bin/install -m 755 "$bin/ClaudeStatusLineRelay" "$contents/Helpers/ClaudeStatusLineRelay"
/usr/bin/install -m 644 "$REPO_ROOT/Assets/AppIcon.icns" "$contents/Resources/AppIcon.icns"
/usr/bin/install -m 644 "$mutable_shell/Contents/embedded.provisionprofile" "$contents/embedded.provisionprofile"
cat > "$contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>
<key>CFBundleDisplayName</key><string>UMA</string><key>CFBundleExecutable</key><string>CodexUsageMonitor</string>
<key>CFBundleIconFile</key><string>AppIcon</string><key>CFBundleIdentifier</key><string>$APP_ID</string>
<key>CFBundlePackageType</key><string>APPL</string><key>CFBundleShortVersionString</key><string>0.13.0</string>
<key>CFBundleVersion</key><string>$build</string><key>LSMinimumSystemVersion</key><string>14.0</string><key>LSUIElement</key><true/>
<key>UMAAppPackageGenerationID</key><string>$(/usr/bin/uuidgen | /usr/bin/tr '[:upper:]' '[:lower:]')</string>
<key>UMAPackagingMode</key><string>UMA_APP_ONLY</string><key>UMASafariHostBundleIdentifier</key><string>$HOST_ID</string>
<key>UMASafariHostExtensionBundleIdentifier</key><string>$EXTENSION_ID</string>
<key>UMASafariHostRuntimeGenerationID</key><string>$(plist "$host_receipt" runtimeGenerationID)</string>
<key>UMASafariHostExtensionVersion</key><string>$(plist "$host_receipt" extensionVersion)</string>
<key>UMASafariHostExtensionBuild</key><string>$(plist "$host_receipt" extensionBuild)</string>
<key>UMAAppGroupIdentifier</key><string>$APP_GROUP</string><key>UMATeamIdentifier</key><string>$TEAM_ID</string>
</dict></plist>
EOF
[[ ! -e "$contents/PlugIns" && -z "$(/usr/bin/find "$app" -name '*.appex' -print -quit)" ]] || exit 1
readonly final_app_entitlements="$scratch/mutable-app-final.entitlements.plist"
/bin/cp "$APP_ENTITLEMENTS" "$final_app_entitlements"
/usr/libexec/PlistBuddy -c \
    "Add :com.apple.application-identifier string $TEAM_ID.$APP_ID" \
    "$final_app_entitlements"
/usr/libexec/PlistBuddy -c \
    "Add :com.apple.developer.team-identifier string $TEAM_ID" \
    "$final_app_entitlements"
/usr/bin/codesign --force --sign "$SIGNING_IDENTITY" --timestamp=none --identifier "$APP_ID.ClaudeStatusLineRelay" "$contents/Helpers/ClaudeStatusLineRelay"
/usr/bin/codesign --force --sign "$SIGNING_IDENTITY" --timestamp=none --identifier "$APP_ID" --entitlements "$final_app_entitlements" "$app"
/usr/bin/codesign --verify --deep --strict --verbose=4 "$app"
"$TRUST_PREFLIGHT" --mode verification --artifact "$app" \
    --profile "$contents/embedded.provisionprofile"
app_entitlements="$scratch/mutable-app.entitlements.plist"
/usr/bin/codesign -d --entitlements :- "$app" > "$app_entitlements" 2>/dev/null
app_signing="$(/usr/bin/codesign -d --verbose=4 "$app" 2>&1)"
[[ "$(printf '%s\n' "$app_signing" | /usr/bin/awk -F= '/^Identifier=/{print $2; exit}')" == "$APP_ID" \
    && "$(printf '%s\n' "$app_signing" | /usr/bin/awk -F= '/^TeamIdentifier=/{print $2; exit}')" == "$TEAM_ID" \
    && "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.application-groups:0' "$app_entitlements")" == "$APP_GROUP" \
    && "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.application-identifier' "$app_entitlements")" == "$TEAM_ID.$APP_ID" \
    && "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.developer.team-identifier' "$app_entitlements")" == "$TEAM_ID" ]]
! /usr/libexec/PlistBuddy -c 'Print :com.apple.security.get-task-allow' "$app_entitlements" >/dev/null 2>&1
verify_host_lock && [[ "$(bundle_tree_sha256 "$host")" == "$pre_host_digest" ]] || { printf '%s\n' UNINTENDED_SAFARI_HOST_MUTATION >&2; exit 1; }
/bin/mkdir "$(dirname "$output")"; /usr/bin/ditto -c -k --keepParent "$app" "$output"
readonly receipt="$(dirname "$output")/UMA_0.13.0-Test.receipt.plist"
/usr/bin/plutil -create xml1 "$receipt"; /usr/bin/plutil -insert schemaVersion -integer 5 "$receipt"
/usr/bin/plutil -insert packagingMode -string UMA_APP_ONLY "$receipt"; /usr/bin/plutil -insert appBuild -string "$build" "$receipt"
/usr/bin/plutil -insert appBundleIdentifier -string "$APP_ID" "$receipt"; /usr/bin/plutil -insert teamIdentifier -string "$TEAM_ID" "$receipt"
/usr/bin/plutil -insert appGroupIdentifier -string "$APP_GROUP" "$receipt"; /usr/bin/plutil -insert mutableProfileName -string "$MUTABLE_PROFILE_NAME" "$receipt"
/usr/bin/plutil -insert appExecutableSHA256 -string "$(/usr/bin/shasum -a 256 "$contents/MacOS/CodexUsageMonitor" | /usr/bin/awk '{print $1}')" "$receipt"
/usr/bin/plutil -insert appCDHash -string "$(printf '%s\n' "$app_signing" | /usr/bin/awk -F= '/^CDHash=/{print $2; exit}')" "$receipt"
/usr/bin/plutil -insert appBundleSHA256 -string "$(bundle_tree_sha256 "$app")" "$receipt"
/usr/bin/plutil -insert appInfoPlistSHA256 -string "$(/usr/bin/shasum -a 256 "$contents/Info.plist" | /usr/bin/awk '{print $1}')" "$receipt"
/usr/bin/plutil -insert appCodeSignatureSHA256 -string "$(bundle_tree_sha256 "$contents/_CodeSignature")" "$receipt"
/usr/bin/plutil -insert appProfileSHA256 -string "$(/usr/bin/shasum -a 256 "$contents/embedded.provisionprofile" | /usr/bin/awk '{print $1}')" "$receipt"
/usr/bin/plutil -insert immutableSafariHostBundleSHA256 -string "$pre_host_digest" "$receipt"
/usr/bin/plutil -insert immutableSafariHostExecutableSHA256 -string "$(plist "$host_receipt" hostExecutableSHA256)" "$receipt"
/usr/bin/plutil -insert immutableSafariHostCDHash -string "$(plist "$host_receipt" hostCDHash)" "$receipt"
/usr/bin/plutil -insert immutableSafariCompanionBundleSHA256 -string "$(plist "$host_receipt" extensionBundleSHA256)" "$receipt"
/usr/bin/plutil -insert immutableSafariCompanionExecutableSHA256 -string "$(plist "$host_receipt" extensionExecutableSHA256)" "$receipt"
/usr/bin/plutil -insert immutableSafariCompanionCDHash -string "$(plist "$host_receipt" extensionCDHash)" "$receipt"
/usr/bin/plutil -insert immutableSafariHostGenerationID -string "$(plist "$host_receipt" runtimeGenerationID)" "$receipt"
/usr/bin/plutil -insert archiveSHA256 -string "$(/usr/bin/shasum -a 256 "$output" | /usr/bin/awk '{print $1}')" "$receipt"
/bin/chmod 600 "$output" "$receipt"
printf 'UMA_APP_ONLY_PACKAGE output=%s receipt=%s safari_artifacts=0\n' "$output" "$receipt"
