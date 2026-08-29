#!/usr/bin/env bash
# Installs only repaired Host-core bytes. It preserves the canonical Host,
# Contents, PlugIns, and signed Companion directory identities and performs no
# LaunchServices/PlugInKit/Safari mutation.
set -eEuo pipefail
umask 077

readonly REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
readonly HOST_PATH="$HOME/Applications/UMA Safari Bridge Test.app"
readonly HOST_ID="com.silkrd.uma.test.safarihost"
readonly EXTENSION_ID="$HOST_ID.ClaudeBrowserCompanion"
readonly APP_GROUP="group.com.silkrd.uma.test.bridge"
readonly TEAM_ID="C6TUZVJ6SJ"
readonly TRUST_PREFLIGHT="$REPO_ROOT/script/verify_uma_apple_development_trust_context.sh"
readonly ATOMIC_SWAP_SOURCE="$REPO_ROOT/AppleDevelopmentSigning/TestChannelAtomicSwap.swift"
readonly RELAUNCH_SOURCE="$REPO_ROOT/AppleDevelopmentSigning/TestChannelRelaunch.swift"

artifact=""; receipt=""; mode=""; expected_build=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --artifact) artifact="${2:-}"; shift 2 ;;
        --receipt) receipt="${2:-}"; shift 2 ;;
        --packaging-mode) mode="${2:-}"; shift 2 ;;
        --expected-core-repair-build) expected_build="${2:-}"; shift 2 ;;
        *) exit 2 ;;
    esac
done
[[ "$mode" == SAFARI_HOST_CORE_REPAIR && "$expected_build" =~ ^[0-9]{12}$ \
    && -f "$artifact" && ! -L "$artifact" && -f "$receipt" && ! -L "$receipt" \
    && -d "$HOST_PATH" && ! -L "$HOST_PATH" ]] || exit 2

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
registered_extension_paths() {
    /usr/bin/pluginkit -m -A -D -vv -i "$EXTENSION_ID" 2>/dev/null |
        /usr/bin/sed -nE \
            's#^[[:space:]]*Path = (/.*\.appex)[[:space:]]*$#\1#p; s#^.* (/.*\.appex)[[:space:]]*$#\1#p' |
        /usr/bin/sort -u
}

scratch="$(/usr/bin/mktemp -d /private/tmp/uma-safari-host-core-install.XXXXXX)"
staged=""
swap_completed=0
qualified=0
swap_binary="$scratch/TestChannelAtomicSwap"
relaunch_binary="$scratch/TestChannelRelaunch"
old_host_build=""
old_runtime_generation=""
cleanup() {
    local status=$?
    trap - EXIT HUP INT TERM
    if [[ "$swap_completed" == 1 && "$qualified" == 0 \
        && -x "$swap_binary" && -d "$staged" ]]; then
        "$swap_binary" --preserve-nested-extension "$staged" "$HOST_PATH" || status=1
        if [[ -x "$relaunch_binary" && -n "$old_host_build" \
            && -n "$old_runtime_generation" ]]; then
            "$relaunch_binary" "$HOST_PATH" "$HOST_ID" \
                "$old_host_build" UMARuntimeGenerationID \
                "$old_runtime_generation" || status=1
        fi
    fi
    [[ -z "$staged" ]] || /bin/rm -rf -- "$staged"
    /bin/rm -rf -- "$scratch"
    exit "$status"
}
trap cleanup EXIT HUP INT TERM
/usr/bin/ditto -x -k "$artifact" "$scratch"
readonly staged_source="$scratch/UMA Safari Bridge Test.app"
readonly staged_appex="$staged_source/Contents/PlugIns/ClaudeBrowserCompanion.appex"
readonly current_appex="$HOST_PATH/Contents/PlugIns/ClaudeBrowserCompanion.appex"
readonly staged_appex_executable="$staged_appex/Contents/MacOS/ClaudeBrowserCompanion"
readonly current_appex_executable="$current_appex/Contents/MacOS/ClaudeBrowserCompanion"
[[ -d "$staged_source" && ! -L "$staged_source" && -d "$staged_appex" && ! -L "$staged_appex" \
    && -d "$current_appex" && ! -L "$current_appex" \
    && "$(plist "$receipt" packagingMode)" == SAFARI_HOST_CORE_REPAIR \
    && "$(plist "$receipt" coreRepairBuild)" == "$expected_build" \
    && "$(plist "$receipt" hostBundleIdentifier)" == "$HOST_ID" \
    && "$(plist "$receipt" extensionBundleIdentifier)" == "$EXTENSION_ID" \
    && "$(plist "$receipt" appGroupIdentifier)" == "$APP_GROUP" \
    && "$(plist "$receipt" teamIdentifier)" == "$TEAM_ID" \
    && "$(/usr/bin/shasum -a 256 "$artifact" | /usr/bin/awk '{print $1}')" == "$(plist "$receipt" archiveSHA256)" \
    && "$(bundle_tree_sha256 "$staged_source")" == "$(plist "$receipt" hostBundleSHA256)" \
    && "$(bundle_tree_sha256 "$staged_appex")" == "$(plist "$receipt" extensionBundleSHA256)" \
    && "$(bundle_tree_sha256 "$current_appex")" == "$(plist "$receipt" extensionBundleSHA256)" \
    && "$(/usr/bin/shasum -a 256 "$staged_appex_executable" | /usr/bin/awk '{print $1}')" == "$(plist "$receipt" extensionExecutableSHA256)" \
    && "$(/usr/bin/shasum -a 256 "$current_appex_executable" | /usr/bin/awk '{print $1}')" == "$(plist "$receipt" extensionExecutableSHA256)" \
    && "$(cdhash "$staged_appex")" == "$(plist "$receipt" extensionCDHash)" \
    && "$(cdhash "$current_appex")" == "$(plist "$receipt" extensionCDHash)" \
    && "$(plist "$HOST_PATH/Contents/Info.plist" UMARuntimeGenerationID)" == "$(plist "$receipt" runtimeGenerationID)" \
    && "$(plist "$staged_source/Contents/Info.plist" UMARuntimeGenerationID)" == "$(plist "$receipt" runtimeGenerationID)" ]] || {
    printf '%s\n' UNINTENDED_COMPANION_MUTATION >&2; exit 1;
}
"$TRUST_PREFLIGHT" --mode verification --artifact "$staged_source" \
    --profile "$staged_source/Contents/embedded.provisionprofile"
"$TRUST_PREFLIGHT" --mode verification --artifact "$staged_appex" \
    --profile "$staged_appex/Contents/embedded.provisionprofile"

readonly app_inode="$(/usr/bin/stat -f %i "$HOST_PATH")"
readonly contents_inode="$(/usr/bin/stat -f %i "$HOST_PATH/Contents")"
readonly plugins_inode="$(/usr/bin/stat -f %i "$HOST_PATH/Contents/PlugIns")"
readonly appex_inode="$(/usr/bin/stat -f %i "$current_appex")"
readonly pre_registration="$(registered_extension_paths)"
[[ "$pre_registration" == "$current_appex" ]] || {
    printf '%s\n' SAFARI_HOST_CORE_REPAIR_REGISTRATION_AMBIGUOUS >&2; exit 1;
}
old_host_build="$(plist "$HOST_PATH/Contents/Info.plist" CFBundleVersion)"
old_runtime_generation="$(plist "$HOST_PATH/Contents/Info.plist" UMARuntimeGenerationID)"
staged="$(/usr/bin/mktemp -d "$HOME/Applications/.UMA-Safari-Host-Core.install.XXXXXX")"
/usr/bin/ditto "$staged_source" "$staged"
/usr/bin/xcrun swiftc "$ATOMIC_SWAP_SOURCE" -o "$swap_binary"
/usr/bin/xcrun swiftc -parse-as-library "$RELAUNCH_SOURCE" -framework AppKit -o "$relaunch_binary"
"$swap_binary" --preserve-nested-extension "$staged" "$HOST_PATH"
swap_completed=1
[[ "$(/usr/bin/stat -f %i "$HOST_PATH")" == "$app_inode" \
    && "$(/usr/bin/stat -f %i "$HOST_PATH/Contents")" == "$contents_inode" \
    && "$(/usr/bin/stat -f %i "$HOST_PATH/Contents/PlugIns")" == "$plugins_inode" \
    && "$(/usr/bin/stat -f %i "$current_appex")" == "$appex_inode" ]] || {
    printf '%s\n' SAFARI_HOST_CORE_REPAIR_IDENTITY_LOST >&2; exit 1;
}
"$TRUST_PREFLIGHT" --mode verification --artifact "$HOST_PATH" \
    --profile "$HOST_PATH/Contents/embedded.provisionprofile"
"$TRUST_PREFLIGHT" --mode verification --artifact "$current_appex" \
    --profile "$current_appex/Contents/embedded.provisionprofile"
/usr/bin/codesign --verify --deep --strict --verbose=4 "$HOST_PATH"
[[ "$(bundle_tree_sha256 "$HOST_PATH")" == "$(plist "$receipt" hostBundleSHA256)" \
    && "$(bundle_tree_sha256 "$current_appex")" == "$(plist "$receipt" extensionBundleSHA256)" \
    && "$(/usr/bin/shasum -a 256 "$current_appex_executable" | /usr/bin/awk '{print $1}')" == "$(plist "$receipt" extensionExecutableSHA256)" \
    && "$(cdhash "$HOST_PATH")" == "$(plist "$receipt" hostCDHash)" \
    && "$(cdhash "$current_appex")" == "$(plist "$receipt" extensionCDHash)" ]] || exit 1
"$relaunch_binary" "$HOST_PATH" "$HOST_ID" \
    "$(plist "$receipt" hostBuild)" UMARuntimeGenerationID \
    "$(plist "$receipt" runtimeGenerationID)"
readonly post_registration="$(registered_extension_paths)"
[[ "$post_registration" == "$pre_registration" \
    && "$post_registration" == "$current_appex" ]] || {
    printf '%s\n' SAFARI_HOST_CORE_REPAIR_REGISTRATION_CHANGED >&2; exit 1;
}
qualified=1
printf 'SAFARI_HOST_CORE_REPAIR_INSTALLED path=%s companion_mutation=0 registration_mutations=0\n' "$HOST_PATH"
