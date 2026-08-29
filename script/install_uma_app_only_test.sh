#!/usr/bin/env bash
# Installs only the mutable UMA app and never touches Safari registration.
set -euo pipefail
umask 077
readonly CANONICAL="$HOME/Applications/UMA_0.13.0-Test.app"
readonly REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
readonly ATOMIC_SWAP_SOURCE="$REPO_ROOT/AppleDevelopmentSigning/TestChannelAtomicSwap.swift"
readonly RELAUNCH_SOURCE="$REPO_ROOT/AppleDevelopmentSigning/TestChannelRelaunch.swift"
readonly TRUST_PREFLIGHT="$REPO_ROOT/script/verify_uma_apple_development_trust_context.sh"
readonly HOST_ID="com.silkrd.uma.test.safarihost"
readonly EXTENSION_ID="$HOST_ID.ClaudeBrowserCompanion"
readonly APP_ID="com.silkrd.uma.test"
readonly APP_GROUP="group.com.silkrd.uma.test.bridge"
readonly TEAM_ID="C6TUZVJ6SJ"
readonly MUTABLE_PROFILE_NAME="UMA Mutable App Test Development"
artifact=""; receipt=""; mode=""; expected_build=""; host=""; host_receipt=""
while [[ $# -gt 0 ]]; do case "$1" in
    --artifact) artifact="${2:-}"; shift 2;; --receipt) receipt="${2:-}"; shift 2;;
    --packaging-mode) mode="${2:-}"; shift 2;;
    --expected-app-build) expected_build="${2:-}"; shift 2;;
    --immutable-safari-host) host="${2:-}"; shift 2;;
    --immutable-host-receipt) host_receipt="${2:-}"; shift 2;;
    --expected-version|--expected-extension-version|--expected-extension-build) shift 2;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; exit 2;;
esac; done
[[ "$mode" == UMA_APP_ONLY && -f "$artifact" && ! -L "$artifact" \
    && -f "$receipt" && ! -L "$receipt" && "$expected_build" =~ ^[0-9]{12}$ ]] || exit 2
bundle_tree_sha256() {
    (cd "$1"; /usr/bin/find . -mindepth 1 -print0 | LC_ALL=C /usr/bin/sort -z |
      while IFS= read -r -d '' entry; do
        if [[ -d "$entry" ]]; then printf 'D\0%s\0%s\0' "$entry" "$(/usr/bin/stat -f %Lp "$entry")"
        elif [[ -f "$entry" ]]; then printf 'F\0%s\0%s\0%s\0' "$entry" "$(/usr/bin/stat -f %Lp "$entry")" "$(/usr/bin/shasum -a 256 "$entry" | /usr/bin/awk '{print $1}')"
        else printf 'UNSUPPORTED\0%s\0' "$entry"; fi
      done) | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}'
}
plist() { /usr/libexec/PlistBuddy -c "Print :$2" "$1"; }
verify_mutable_runtime_metadata() {
    local candidate="$1" info="$1/Contents/Info.plist"
    [[ -d "$candidate" && ! -L "$candidate" \
        && "$(plist "$info" UMASafariHostBundleIdentifier)" == "$HOST_ID" \
        && "$(plist "$info" UMASafariHostExtensionBundleIdentifier)" == "$EXTENSION_ID" \
        && "$(plist "$info" UMASafariHostRuntimeGenerationID)" == "$expected_generation" \
        && "$(plist "$info" UMASafariHostExtensionVersion)" == "$expected_extension_version" \
        && "$(plist "$info" UMASafariHostExtensionBuild)" == "$expected_extension_build" \
        && "$(plist "$info" UMAAppGroupIdentifier)" == "$APP_GROUP" \
        && "$(plist "$info" UMATeamIdentifier)" == "$TEAM_ID" ]]
}
verify_host_lock() {
    [[ "$host" == '/Users/juliushe/Applications/UMA Safari Bridge Test.app' \
        && -d "$host" && ! -L "$host" && -f "$host_receipt" && ! -L "$host_receipt" \
        && -z "$(/usr/bin/find "$host" -type l -print -quit)" ]] || return 1
    local appex="$host/Contents/PlugIns/ClaudeBrowserCompanion.appex"
    [[ -d "$appex" && "$(plist "$host_receipt" schemaVersion)" == 2 \
        && "$(plist "$host_receipt" classification)" == IMMUTABLE_SAFARI_HOST_TEST \
        && "$(plist "$host_receipt" hostBundleIdentifier)" == "$HOST_ID" \
        && "$(plist "$host_receipt" extensionBundleIdentifier)" == "$EXTENSION_ID" \
        && "$(plist "$host_receipt" appGroupIdentifier)" == "$APP_GROUP" \
        && "$(plist "$host_receipt" teamIdentifier)" == "$TEAM_ID" \
        && "$(bundle_tree_sha256 "$host")" == "$(plist "$host_receipt" hostBundleSHA256)" \
        && "$(bundle_tree_sha256 "$appex")" == "$(plist "$host_receipt" extensionBundleSHA256)" \
        && "$(/usr/bin/shasum -a 256 "$host/Contents/MacOS/UMASafariBridgeHost" | /usr/bin/awk '{print $1}')" == "$(plist "$host_receipt" hostExecutableSHA256)" \
        && "$(/usr/bin/shasum -a 256 "$appex/Contents/MacOS/ClaudeBrowserCompanion" | /usr/bin/awk '{print $1}')" == "$(plist "$host_receipt" extensionExecutableSHA256)" \
        && "$(/usr/bin/shasum -a 256 "$host/Contents/Info.plist" | /usr/bin/awk '{print $1}')" == "$(plist "$host_receipt" hostInfoPlistSHA256)" \
        && "$(/usr/bin/shasum -a 256 "$appex/Contents/Info.plist" | /usr/bin/awk '{print $1}')" == "$(plist "$host_receipt" extensionInfoPlistSHA256)" \
        && "$(bundle_tree_sha256 "$host/Contents/_CodeSignature")" == "$(plist "$host_receipt" hostCodeSignatureSHA256)" \
        && "$(bundle_tree_sha256 "$appex/Contents/_CodeSignature")" == "$(plist "$host_receipt" extensionCodeSignatureSHA256)" \
        && "$(/usr/bin/shasum -a 256 "$host/Contents/embedded.provisionprofile" | /usr/bin/awk '{print $1}')" == "$(plist "$host_receipt" hostProfileSHA256)" \
        && "$(/usr/bin/shasum -a 256 "$appex/Contents/embedded.provisionprofile" | /usr/bin/awk '{print $1}')" == "$(plist "$host_receipt" extensionProfileSHA256)" ]] || return 1
    /usr/bin/codesign --verify --deep --strict --verbose=2 "$host" || return 1
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
readonly expected_generation="$(plist "$host_receipt" runtimeGenerationID)"
readonly expected_extension_version="$(plist "$host_receipt" extensionVersion)"
readonly expected_extension_build="$(plist "$host_receipt" extensionBuild)"
[[ "$expected_generation" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$ \
    && -n "$expected_extension_version" \
    && "$expected_extension_build" =~ ^[0-9]+$ ]] || exit 1
[[ "$(plist "$receipt" schemaVersion)" == 5 \
    && "$(plist "$receipt" packagingMode)" == UMA_APP_ONLY \
    && "$(plist "$receipt" appBuild)" == "$expected_build" \
    && "$(plist "$receipt" appBundleIdentifier)" == "$APP_ID" \
    && "$(plist "$receipt" teamIdentifier)" == "$TEAM_ID" \
    && "$(plist "$receipt" appGroupIdentifier)" == "$APP_GROUP" \
    && "$(plist "$receipt" mutableProfileName)" == "$MUTABLE_PROFILE_NAME" \
    && "$(plist "$receipt" immutableSafariHostBundleSHA256)" == "$pre_host_digest" \
    && "$(plist "$receipt" immutableSafariHostExecutableSHA256)" == "$(plist "$host_receipt" hostExecutableSHA256)" \
    && "$(plist "$receipt" immutableSafariHostCDHash)" == "$(plist "$host_receipt" hostCDHash)" \
    && "$(plist "$receipt" immutableSafariCompanionBundleSHA256)" == "$(plist "$host_receipt" extensionBundleSHA256)" \
    && "$(plist "$receipt" immutableSafariCompanionExecutableSHA256)" == "$(plist "$host_receipt" extensionExecutableSHA256)" \
    && "$(plist "$receipt" immutableSafariCompanionCDHash)" == "$(plist "$host_receipt" extensionCDHash)" \
    && "$(/usr/bin/shasum -a 256 "$artifact" | /usr/bin/awk '{print $1}')" == "$(plist "$receipt" archiveSHA256)" ]] || exit 1
scratch="$(/usr/bin/mktemp -d /private/tmp/uma-app-only-install.XXXXXX)"; trap '/bin/rm -rf -- "$scratch"' EXIT HUP INT TERM
/usr/bin/ditto -x -k "$artifact" "$scratch"
readonly app="$scratch/UMA_0.13.0-Test.app"
[[ -d "$app" && ! -L "$app" && ! -e "$app/Contents/PlugIns" \
    && -z "$(/usr/bin/find "$app" -name '*.appex' -print -quit)" \
    && "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" == "$APP_ID" \
    && "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")" == "$expected_build" \
    && "$(/usr/libexec/PlistBuddy -c 'Print :UMAPackagingMode' "$app/Contents/Info.plist")" == UMA_APP_ONLY ]] || exit 1
verify_mutable_runtime_metadata "$app" || exit 1
[[ -x "$TRUST_PREFLIGHT" ]] || exit 1
"$TRUST_PREFLIGHT" --mode verification --artifact "$app" \
    --profile "$app/Contents/embedded.provisionprofile"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$app"
[[ "$(bundle_tree_sha256 "$app")" == "$(plist "$receipt" appBundleSHA256)" \
    && "$(/usr/bin/shasum -a 256 "$app/Contents/MacOS/CodexUsageMonitor" | /usr/bin/awk '{print $1}')" == "$(plist "$receipt" appExecutableSHA256)" \
    && "$(/usr/bin/shasum -a 256 "$app/Contents/Info.plist" | /usr/bin/awk '{print $1}')" == "$(plist "$receipt" appInfoPlistSHA256)" \
    && "$(bundle_tree_sha256 "$app/Contents/_CodeSignature")" == "$(plist "$receipt" appCodeSignatureSHA256)" \
    && "$(/usr/bin/shasum -a 256 "$app/Contents/embedded.provisionprofile" | /usr/bin/awk '{print $1}')" == "$(plist "$receipt" appProfileSHA256)" ]] || exit 1
[[ "$(plist "$receipt" immutableSafariHostGenerationID)" == "$expected_generation" ]] || exit 1
app_signing="$(/usr/bin/codesign -d --verbose=4 "$app" 2>&1)"
[[ "$(printf '%s\n' "$app_signing" | /usr/bin/awk -F= '/^Identifier=/{print $2; exit}')" == "$APP_ID" \
    && "$(printf '%s\n' "$app_signing" | /usr/bin/awk -F= '/^TeamIdentifier=/{print $2; exit}')" == "$TEAM_ID" \
    && "$(printf '%s\n' "$app_signing" | /usr/bin/awk -F= '/^CDHash=/{print $2; exit}')" == "$(plist "$receipt" appCDHash)" ]] || exit 1
/usr/bin/codesign -d --entitlements :- "$app" > "$scratch/mutable-entitlements.plist" 2>/dev/null
[[ "$(plist "$scratch/mutable-entitlements.plist" com.apple.application-identifier)" == "$TEAM_ID.$APP_ID" \
    && "$(plist "$scratch/mutable-entitlements.plist" com.apple.developer.team-identifier)" == "$TEAM_ID" \
    && "$(plist "$scratch/mutable-entitlements.plist" com.apple.security.application-groups:0)" == "$APP_GROUP" ]] || exit 1
! /usr/libexec/PlistBuddy -c 'Print :com.apple.security.get-task-allow' "$scratch/mutable-entitlements.plist" >/dev/null 2>&1 || exit 1
/usr/bin/security cms -D -i "$app/Contents/embedded.provisionprofile" > "$scratch/mutable-profile.plist"
mutable_profile_expiration="$(/usr/bin/plutil -extract ExpirationDate raw "$scratch/mutable-profile.plist" 2>/dev/null || true)"
[[ "$(plist "$scratch/mutable-profile.plist" Name)" == "$MUTABLE_PROFILE_NAME" \
    && "$(plist "$scratch/mutable-profile.plist" TeamIdentifier:0)" == "$TEAM_ID" \
    && "$(plist "$scratch/mutable-profile.plist" Entitlements:com.apple.application-identifier)" == "$TEAM_ID.$APP_ID" \
    && "$(plist "$scratch/mutable-profile.plist" Entitlements:com.apple.developer.team-identifier)" == "$TEAM_ID" \
    && "$(plist "$scratch/mutable-profile.plist" Entitlements:com.apple.security.application-groups:0)" == "$APP_GROUP" \
    && "$mutable_profile_expiration" > "$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)" ]] || exit 1
! /usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.security.get-task-allow' "$scratch/mutable-profile.plist" >/dev/null 2>&1 || exit 1
/bin/mkdir -p "$HOME/Applications"
staged="$(/usr/bin/mktemp -d "$HOME/Applications/.UMA_0.13.0-Test.install.XXXXXX")"
/usr/bin/ditto "$app" "$staged"; /usr/bin/codesign --verify --deep --strict --verbose=2 "$staged"
readonly swap_binary="$scratch/TestChannelAtomicSwap"
readonly relaunch_binary="$scratch/TestChannelRelaunch"
/usr/bin/xcrun swiftc "$ATOMIC_SWAP_SOURCE" -o "$swap_binary"
/usr/bin/xcrun swiftc -parse-as-library "$RELAUNCH_SOURCE" \
    -framework AppKit -o "$relaunch_binary"
"$swap_binary" "$staged" "$CANONICAL"
[[ ! -e "$staged" ]] || /bin/rm -rf -- "$staged"
"$TRUST_PREFLIGHT" --mode verification --artifact "$CANONICAL" \
    --profile "$CANONICAL/Contents/embedded.provisionprofile"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$CANONICAL"
verify_mutable_runtime_metadata "$CANONICAL" || exit 1
[[ "$(bundle_tree_sha256 "$CANONICAL")" == "$(plist "$receipt" appBundleSHA256)" \
    && "$(/usr/bin/shasum -a 256 "$CANONICAL/Contents/MacOS/CodexUsageMonitor" | /usr/bin/awk '{print $1}')" == "$(plist "$receipt" appExecutableSHA256)" \
    && "$(/usr/bin/shasum -a 256 "$CANONICAL/Contents/Info.plist" | /usr/bin/awk '{print $1}')" == "$(plist "$receipt" appInfoPlistSHA256)" \
    && "$(bundle_tree_sha256 "$CANONICAL/Contents/_CodeSignature")" == "$(plist "$receipt" appCodeSignatureSHA256)" \
    && "$(/usr/bin/shasum -a 256 "$CANONICAL/Contents/embedded.provisionprofile" | /usr/bin/awk '{print $1}')" == "$(plist "$receipt" appProfileSHA256)" ]] || exit 1
canonical_signing="$(/usr/bin/codesign -d --verbose=4 "$CANONICAL" 2>&1)"
[[ "$(printf '%s\n' "$canonical_signing" | /usr/bin/awk -F= '/^Identifier=/{print $2; exit}')" == "$APP_ID" \
    && "$(printf '%s\n' "$canonical_signing" | /usr/bin/awk -F= '/^TeamIdentifier=/{print $2; exit}')" == "$TEAM_ID" \
    && "$(printf '%s\n' "$canonical_signing" | /usr/bin/awk -F= '/^CDHash=/{print $2; exit}')" == "$(plist "$receipt" appCDHash)" ]] || exit 1
/usr/bin/codesign -d --entitlements :- "$CANONICAL" > "$scratch/canonical-entitlements.plist" 2>/dev/null
[[ "$(plist "$scratch/canonical-entitlements.plist" com.apple.application-identifier)" == "$TEAM_ID.$APP_ID" \
    && "$(plist "$scratch/canonical-entitlements.plist" com.apple.developer.team-identifier)" == "$TEAM_ID" \
    && "$(plist "$scratch/canonical-entitlements.plist" com.apple.security.application-groups:0)" == "$APP_GROUP" ]] || exit 1
! /usr/libexec/PlistBuddy -c 'Print :com.apple.security.get-task-allow' "$scratch/canonical-entitlements.plist" >/dev/null 2>&1 || exit 1
verify_host_lock && [[ "$(bundle_tree_sha256 "$host")" == "$pre_host_digest" ]] || {
    printf '%s\n' UNINTENDED_SAFARI_HOST_MUTATION >&2; exit 1;
}
"$relaunch_binary" "$CANONICAL" "$APP_ID" "$expected_build" "$expected_generation"
printf 'UMA_APP_ONLY_INSTALLED path=%s build=%s safari_registration_mutations=0\n' "$CANONICAL" "$expected_build"
