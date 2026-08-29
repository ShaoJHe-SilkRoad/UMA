#!/usr/bin/env bash
# Resolves and verifies Xcode-managed Apple Development signing for UMA's exact
# containing-app and Safari extension identifiers. This harness never ships.
set -euo pipefail
umask 077

readonly EXPECTED_DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer"
readonly EXPECTED_IDENTITY="Apple Development: SHAOTING HE (5BN4FAQSUF)"
readonly EXPECTED_TEAM="C6TUZVJ6SJ"
readonly APP_ID="com.silkrd.uma.test"
readonly EXTENSION_ID="$APP_ID.ClaudeBrowserCompanion"
readonly REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
readonly PROJECT="$REPO_ROOT/AppleDevelopmentSigning/UMAAppleDevelopmentSigning.xcodeproj"
readonly TRUST_PREFLIGHT="$REPO_ROOT/script/verify_uma_apple_development_trust_context.sh"
readonly LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"

usage() {
    printf '%s\n' "Usage: $0 --work-root </private/tmp/uma-apple-development-signing-*>" >&2
}

work_root=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --work-root) work_root="${2:-}"; shift 2 ;;
        *) usage; exit 2 ;;
    esac
done

[[ "$work_root" == /private/tmp/uma-apple-development-signing-* ]] || {
    printf 'Refusing non-task-owned work root: %s\n' "$work_root" >&2
    exit 2
}
[[ ! -e "$work_root" && ! -L "$work_root" ]] || {
    printf 'Refusing to reuse work root: %s\n' "$work_root" >&2
    exit 2
}
[[ "${DEVELOPER_DIR:-}" == "$EXPECTED_DEVELOPER_DIR" ]] || {
    printf 'Required task-scoped DEVELOPER_DIR is %s\n' "$EXPECTED_DEVELOPER_DIR" >&2
    exit 2
}
[[ -d "$PROJECT" && ! -L "$PROJECT" ]] || {
    printf 'Apple Development signing harness is missing: %s\n' "$PROJECT" >&2
    exit 1
}
[[ -x "$TRUST_PREFLIGHT" ]] || exit 1
"$TRUST_PREFLIGHT" --mode signing

identity_count="$(
    /usr/bin/security find-identity -v -p codesigning 2>/dev/null \
        | /usr/bin/grep -F -c "\"$EXPECTED_IDENTITY\"" || true
)"
[[ "$identity_count" == 1 ]] || {
    printf 'Expected exactly one usable signing identity: %s\n' "$EXPECTED_IDENTITY" >&2
    exit 1
}

mkdir "$work_root"
readonly derived_data="$work_root/DerivedData"
readonly app="$derived_data/Build/Products/Release/UMAProvisioningHost.app"
readonly appex="$app/Contents/PlugIns/ClaudeBrowserCompanion.appex"

cleanup() {
    if [[ -d "$app" ]]; then
        "$LSREGISTER" -u "$app" >/dev/null 2>&1 || true
    fi
    rm -rf -- "$work_root"
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM

/usr/bin/xcodebuild \
    -project "$PROJECT" \
    -scheme UMAProvisioningHost \
    -configuration Release \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$derived_data" \
    -allowProvisioningUpdates \
    CODE_SIGN_STYLE=Automatic \
    DEVELOPMENT_TEAM="$EXPECTED_TEAM" \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    build >/dev/null

[[ -d "$app" && -d "$appex" ]] || {
    printf '%s\n' "Xcode did not produce both automatic-signing harness bundles." >&2
    exit 1
}
/usr/bin/codesign --verify --deep --strict --verbose=4 "$app"

verify_signer() {
    local target="$1"
    local identifier="$2"
    local report="$work_root/$(basename "$target").signing"
    /usr/bin/codesign -d --verbose=4 "$target" 2> "$report"
    /usr/bin/grep -Fx -q "Identifier=$identifier" "$report"
    /usr/bin/grep -Fx -q "Authority=$EXPECTED_IDENTITY" "$report"
    /usr/bin/grep -Fx -q "TeamIdentifier=$EXPECTED_TEAM" "$report"
    ! /usr/bin/grep -Fx -q 'Signature=adhoc' "$report"
}

verify_signer "$app" "$APP_ID"
verify_signer "$appex" "$EXTENSION_ID"

readonly app_entitlements="$work_root/app-entitlements.plist"
readonly appex_entitlements="$work_root/appex-entitlements.plist"
/usr/bin/codesign -d --entitlements :- "$app" > "$app_entitlements" 2>/dev/null
/usr/bin/codesign -d --entitlements :- "$appex" > "$appex_entitlements" 2>/dev/null
if /usr/libexec/PlistBuddy -c 'Print :com.apple.security.get-task-allow' \
    "$app_entitlements" >/dev/null 2>&1 \
    || /usr/libexec/PlistBuddy -c 'Print :com.apple.security.get-task-allow' \
        "$appex_entitlements" >/dev/null 2>&1; then
    printf '%s\n' "Apple Development harness unexpectedly received get-task-allow." >&2
    exit 1
fi
/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' \
    "$appex_entitlements" | /usr/bin/grep -Fx -q true
/usr/libexec/PlistBuddy -c \
    'Print :com.apple.security.temporary-exception.files.home-relative-path.read-write:0' \
    "$appex_entitlements" | /usr/bin/grep -Fx -q \
        '/Library/Application Support/CodexUsageMonitor/TestChannel/ClaudeBrowserCompanion/'

if [[ -f "$app/Contents/embedded.provisionprofile" \
    || -f "$appex/Contents/embedded.provisionprofile" ]]; then
    printf '%s\n' \
        "Embedded provisioning profiles are unsupported by this bounded no-profile mode." >&2
    exit 1
fi
readonly profile_mode="macos-xcode-managed-no-embedded-profile-required"

printf 'APPLE_DEVELOPMENT_PROVISIONING_READY identity=%s team=%s app_id=%s extension_id=%s profile_mode=%s get_task_allow=false\n' \
    "$EXPECTED_IDENTITY" "$EXPECTED_TEAM" "$APP_ID" "$EXTENSION_ID" "$profile_mode"
