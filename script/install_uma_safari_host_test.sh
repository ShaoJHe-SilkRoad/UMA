#!/usr/bin/env bash
# Performs the one deliberate immutable Safari Host migration and registration.
set -euo pipefail
umask 077
readonly HOST_PATH="$HOME/Applications/UMA Safari Bridge Test.app"
readonly OLD_COMBINED_APP="$HOME/Applications/UMA_0.13.0-Test.app"
readonly REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
readonly ATOMIC_SWAP_SOURCE="$REPO_ROOT/AppleDevelopmentSigning/TestChannelAtomicSwap.swift"
readonly TRUST_PREFLIGHT="$REPO_ROOT/script/verify_uma_apple_development_trust_context.sh"
readonly HOST_ID="com.silkrd.uma.test.safarihost"
readonly EXTENSION_ID="$HOST_ID.ClaudeBrowserCompanion"
readonly APP_GROUP="group.com.silkrd.uma.test.bridge"
readonly TEAM_ID="C6TUZVJ6SJ"
readonly HOST_PROFILE_NAME="UMA Safari Host Test Development v2"
readonly EXTENSION_PROFILE_NAME="UMA Claude Companion Test Development v2"
readonly OWNED_TAB_RECEIPT="$HOME/Library/Group Containers/$APP_GROUP/ClaudeSafariHost/OwnedTab/owned-tab-receipt.plist"
readonly LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"
artifact=""; receipt=""; mode=""; audit_owned_tab_receipt=""
while [[ $# -gt 0 ]]; do case "$1" in
    --artifact) artifact="${2:-}"; shift 2;; --receipt) receipt="${2:-}"; shift 2;;
    --packaging-mode) mode="${2:-}"; shift 2;;
    --audit-owned-tab-receipt) audit_owned_tab_receipt="${2:-}"; shift 2;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; exit 2;;
esac; done

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
        /usr/bin/sed -nE 's#^[[:space:]]*Path = (/.*\.appex)[[:space:]]*$#\1#p' |
        /usr/bin/sort -u
}
single_canonical_registration() {
    local paths count
    paths="$(registered_extension_paths)"
    count="$(printf '%s\n' "$paths" | /usr/bin/awk 'NF { count += 1 } END { print count + 0 }')"
    [[ "$count" == 1 \
        && "$paths" == "$HOST_PATH/Contents/PlugIns/ClaudeBrowserCompanion.appex" ]]
}

owned_tab_receipt_status() {
    local path="$1" directory metadata directory_metadata
    directory="$(dirname "$path")"
    if [[ ! -e "$path" && ! -L "$path" ]]; then
        if [[ -e "$directory" || -L "$directory" ]]; then
            [[ -d "$directory" && ! -L "$directory" ]] || { printf '%s\n' UNSAFE; return; }
            directory_metadata="$(/usr/bin/stat -f '%u %Lp' "$directory" 2>/dev/null)" || {
                printf '%s\n' UNSAFE; return;
            }
            [[ "$directory_metadata" == "$(/usr/bin/id -u) 700" ]] || {
                printf '%s\n' UNSAFE; return;
            }
        fi
        printf '%s\n' CLEAR
        return
    fi
    [[ -f "$path" && ! -L "$path" && -d "$directory" && ! -L "$directory" ]] || {
        printf '%s\n' UNSAFE; return;
    }
    metadata="$(/usr/bin/stat -f '%u %Lp %z %l' "$path" 2>/dev/null)" || {
        printf '%s\n' UNSAFE; return;
    }
    directory_metadata="$(/usr/bin/stat -f '%u %Lp' "$directory" 2>/dev/null)" || {
        printf '%s\n' UNSAFE; return;
    }
    set -- $metadata
    [[ "$1" == "$(/usr/bin/id -u)" && "$2" == 600 \
        && "$3" -gt 0 && "$3" -le 2048 && "$4" == 1 \
        && "$directory_metadata" == "$(/usr/bin/id -u) 700" ]] || {
        printf '%s\n' UNSAFE; return;
    }
    printf '%s\n' ACTIVE
}

if [[ -n "$audit_owned_tab_receipt" ]]; then
    [[ -z "$artifact" && -z "$receipt" && -z "$mode" ]] || exit 2
    owned_tab_receipt_status "$audit_owned_tab_receipt"
    exit 0
fi

[[ "$mode" == SAFARI_HOST_MIGRATION && -f "$artifact" && ! -L "$artifact" \
    && -f "$receipt" && ! -L "$receipt" ]] || exit 2
case "$(owned_tab_receipt_status "$OWNED_TAB_RECEIPT")" in
    CLEAR) ;;
    ACTIVE) printf '%s\n' SAFARI_HOST_MIGRATION_BLOCKED_ACTIVE_OWNED_TAB_RECEIPT >&2; exit 1;;
    *) printf '%s\n' SAFARI_HOST_MIGRATION_BLOCKED_UNSAFE_OWNED_TAB_RECEIPT >&2; exit 1;;
esac

scratch="$(/usr/bin/mktemp -d /private/tmp/uma-safari-host-install.XXXXXX)"; trap '/bin/rm -rf -- "$scratch"' EXIT HUP INT TERM
/usr/bin/ditto -x -k "$artifact" "$scratch"
readonly host="$scratch/UMA Safari Bridge Test.app"
readonly appex="$host/Contents/PlugIns/ClaudeBrowserCompanion.appex"
[[ -d "$host" && ! -L "$host" && -d "$appex" && ! -L "$appex" \
    && -z "$(/usr/bin/find "$host" -type l -print -quit)" \
    && "$(plist "$receipt" schemaVersion)" == 2 \
    && "$(plist "$receipt" classification)" == IMMUTABLE_SAFARI_HOST_TEST \
    && "$(plist "$receipt" hostBundleIdentifier)" == "$HOST_ID" \
    && "$(plist "$receipt" extensionBundleIdentifier)" == "$EXTENSION_ID" \
    && "$(plist "$receipt" appGroupIdentifier)" == "$APP_GROUP" \
    && "$(plist "$receipt" teamIdentifier)" == "$TEAM_ID" \
    && "$(/usr/bin/shasum -a 256 "$artifact" | /usr/bin/awk '{print $1}')" == "$(plist "$receipt" archiveSHA256)" \
    && "$(bundle_tree_sha256 "$host")" == "$(plist "$receipt" hostBundleSHA256)" \
    && "$(bundle_tree_sha256 "$appex")" == "$(plist "$receipt" extensionBundleSHA256)" \
    && "$(/usr/bin/shasum -a 256 "$host/Contents/Info.plist" | /usr/bin/awk '{print $1}')" == "$(plist "$receipt" hostInfoPlistSHA256)" \
    && "$(/usr/bin/shasum -a 256 "$appex/Contents/Info.plist" | /usr/bin/awk '{print $1}')" == "$(plist "$receipt" extensionInfoPlistSHA256)" \
    && "$(bundle_tree_sha256 "$host/Contents/_CodeSignature")" == "$(plist "$receipt" hostCodeSignatureSHA256)" \
    && "$(bundle_tree_sha256 "$appex/Contents/_CodeSignature")" == "$(plist "$receipt" extensionCodeSignatureSHA256)" \
    && "$(/usr/bin/shasum -a 256 "$host/Contents/MacOS/UMASafariBridgeHost" | /usr/bin/awk '{print $1}')" == "$(plist "$receipt" hostExecutableSHA256)" \
    && "$(/usr/bin/shasum -a 256 "$appex/Contents/MacOS/ClaudeBrowserCompanion" | /usr/bin/awk '{print $1}')" == "$(plist "$receipt" extensionExecutableSHA256)" \
    && "$(/usr/bin/shasum -a 256 "$host/Contents/embedded.provisionprofile" | /usr/bin/awk '{print $1}')" == "$(plist "$receipt" hostProfileSHA256)" \
    && "$(/usr/bin/shasum -a 256 "$appex/Contents/embedded.provisionprofile" | /usr/bin/awk '{print $1}')" == "$(plist "$receipt" extensionProfileSHA256)" \
    && "$(plist "$receipt" hostProfileName)" == "$HOST_PROFILE_NAME" \
    && "$(plist "$receipt" extensionProfileName)" == "$EXTENSION_PROFILE_NAME" ]] || {
    printf '%s\n' UNINTENDED_SAFARI_HOST_MUTATION >&2; exit 1;
}
[[ -x "$TRUST_PREFLIGHT" ]] || exit 1
"$TRUST_PREFLIGHT" --mode verification --artifact "$host" \
    --profile "$host/Contents/embedded.provisionprofile"
"$TRUST_PREFLIGHT" --mode verification --artifact "$appex" \
    --profile "$appex/Contents/embedded.provisionprofile"
/usr/bin/codesign --verify --deep --strict --verbose=4 "$host"
[[ "$(cdhash "$host")" == "$(plist "$receipt" hostCDHash)" \
    && "$(cdhash "$appex")" == "$(plist "$receipt" extensionCDHash)" ]] || {
    printf '%s\n' UNINTENDED_SAFARI_HOST_MUTATION >&2; exit 1;
}

verify_profile_contract() {
    local profile="$1" expected_identifier="$2" expected_name="$3" decoded="$4" expiration
    /usr/bin/security cms -D -i "$profile" > "$decoded"
    expiration="$(/usr/bin/plutil -extract ExpirationDate raw "$decoded" 2>/dev/null || true)"
    [[ "$(plist "$decoded" Name)" == "$expected_name" \
        && "$(plist "$decoded" TeamIdentifier:0)" == "$TEAM_ID" \
        && "$(plist "$decoded" Entitlements:com.apple.application-identifier)" == "$TEAM_ID.$expected_identifier" \
        && "$(plist "$decoded" Entitlements:com.apple.developer.team-identifier)" == "$TEAM_ID" \
        && "$(plist "$decoded" Entitlements:com.apple.security.application-groups:0)" == "$APP_GROUP" \
        && "$expiration" > "$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)" ]] || return 1
    ! /usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.security.get-task-allow' "$decoded" >/dev/null 2>&1
}
verify_effective_entitlements() {
    local target="$1" expected_identifier="$2" require_sandbox="$3" decoded="$4" signing
    /usr/bin/codesign -d --entitlements :- "$target" > "$decoded" 2>/dev/null
    signing="$(/usr/bin/codesign -d --verbose=4 "$target" 2>&1)"
    [[ "$(printf '%s\n' "$signing" | /usr/bin/awk -F= '/^Identifier=/{print $2; exit}')" == "$expected_identifier" \
        && "$(printf '%s\n' "$signing" | /usr/bin/awk -F= '/^TeamIdentifier=/{print $2; exit}')" == "$TEAM_ID" \
        && "$(plist "$decoded" com.apple.application-identifier)" == "$TEAM_ID.$expected_identifier" \
        && "$(plist "$decoded" com.apple.developer.team-identifier)" == "$TEAM_ID" \
        && "$(plist "$decoded" com.apple.security.application-groups:0)" == "$APP_GROUP" ]] || return 1
    ! /usr/libexec/PlistBuddy -c 'Print :com.apple.security.get-task-allow' "$decoded" >/dev/null 2>&1 || return 1
    if [[ "$require_sandbox" == true ]]; then
        [[ "$(plist "$decoded" com.apple.security.app-sandbox)" == true ]]
    fi
}
verify_profile_contract "$host/Contents/embedded.provisionprofile" "$HOST_ID" \
    "$HOST_PROFILE_NAME" "$scratch/host-profile.plist"
verify_profile_contract "$appex/Contents/embedded.provisionprofile" "$EXTENSION_ID" \
    "$EXTENSION_PROFILE_NAME" "$scratch/extension-profile.plist"
verify_effective_entitlements "$host" "$HOST_ID" false "$scratch/host-entitlements.plist"
verify_effective_entitlements "$appex" "$EXTENSION_ID" true "$scratch/extension-entitlements.plist"

# Preserve the rejected combined Test package as immutable evidence before
# unregistering only its task-owned Test extension identity.
if [[ -d "$OLD_COMBINED_APP/Contents/PlugIns/ClaudeBrowserCompanion.appex" ]]; then
    old_id="$(plist "$OLD_COMBINED_APP/Contents/Info.plist" CFBundleIdentifier)"
    [[ "$old_id" == com.silkrd.uma.test ]] || { printf '%s\n' 'Refusing unrelated combined app.' >&2; exit 1; }
    archive_dir="/Volumes/HE/DEV/UMA/Packages/retired-combined-test-$(/bin/date -u +%Y%m%dT%H%M%SZ)"
    /bin/mkdir "$archive_dir"
    /usr/bin/ditto -c -k --keepParent "$OLD_COMBINED_APP" "$archive_dir/UMA_0.13.0-Test-combined.zip"
    /usr/bin/shasum -a 256 "$archive_dir/UMA_0.13.0-Test-combined.zip" > "$archive_dir/SHA256.txt"
    /usr/bin/pluginkit -r "$OLD_COMBINED_APP/Contents/PlugIns/ClaudeBrowserCompanion.appex" >/dev/null 2>&1 || true
fi

/bin/mkdir -p "$HOME/Applications"
staged="$(/usr/bin/mktemp -d "$HOME/Applications/.UMA-Safari-Bridge-Test.install.XXXXXX")"
/usr/bin/ditto "$host" "$staged"
/usr/bin/codesign --verify --deep --strict --verbose=4 "$staged"
swap_binary="$scratch/TestChannelAtomicSwap"
/usr/bin/xcrun swiftc "$ATOMIC_SWAP_SOURCE" -o "$swap_binary"
host_was_present=false
if [[ -e "$HOST_PATH" || -L "$HOST_PATH" ]]; then
    [[ -d "$HOST_PATH" && ! -L "$HOST_PATH" \
        && "$(plist "$HOST_PATH/Contents/Info.plist" CFBundleIdentifier)" == "$HOST_ID" \
        && -d "$HOST_PATH/Contents/PlugIns/ClaudeBrowserCompanion.appex" \
        && ! -L "$HOST_PATH/Contents/PlugIns/ClaudeBrowserCompanion.appex" \
        && "$(plist "$HOST_PATH/Contents/PlugIns/ClaudeBrowserCompanion.appex/Contents/Info.plist" CFBundleIdentifier)" == "$EXTENSION_ID" \
        && -z "$(/usr/bin/find "$HOST_PATH" -type l -print -quit)" ]] || exit 1
    /usr/bin/codesign --verify --deep --strict --verbose=4 "$HOST_PATH"
    current_generation="$(plist "$HOST_PATH/Contents/Info.plist" UMARuntimeGenerationID)"
    next_generation="$(plist "$receipt" runtimeGenerationID)"
    [[ "$current_generation" != "$next_generation" ]] || {
        printf '%s\n' SAFARI_HOST_MIGRATION_REQUIRES_NEW_GENERATION >&2; exit 1;
    }
    host_was_present=true
fi
swapped=false
installed_new=false
rollback_required=true
rollback_failed=false
rollback() {
    # EXIT traps run with `set -e` still active. A successful migration sets
    # rollback_required=false; returning a failure from this no-op branch would
    # overwrite the installer's successful terminal status after every verified
    # migration.
    if [[ "$rollback_required" != true ]]; then return 0; fi
    if [[ "$swapped" == true && -d "$HOST_PATH" && -d "$staged" ]]; then
        /usr/bin/pluginkit -r "$HOST_PATH/Contents/PlugIns/ClaudeBrowserCompanion.appex" >/dev/null 2>&1 || true
        if ! "$swap_binary" "$staged" "$HOST_PATH" >/dev/null 2>&1; then
            rollback_failed=true
            printf '%s\n' SAFARI_HOST_MIGRATION_ROLLBACK_FAILED >&2
            return
        fi
        "$LSREGISTER" -f "$HOST_PATH" >/dev/null 2>&1 || true
        /usr/bin/pluginkit -a "$HOST_PATH/Contents/PlugIns/ClaudeBrowserCompanion.appex" >/dev/null 2>&1 || true
        if ! single_canonical_registration; then
            rollback_failed=true
            printf '%s\n' SAFARI_HOST_MIGRATION_ROLLBACK_REGISTRATION_FAILED >&2
        fi
    elif [[ "$installed_new" == true && -d "$HOST_PATH" ]]; then
        /usr/bin/pluginkit -r "$HOST_PATH/Contents/PlugIns/ClaudeBrowserCompanion.appex" >/dev/null 2>&1 || true
        /bin/rm -rf -- "$HOST_PATH"
    fi
}
cleanup() {
    status=$?
    trap - EXIT HUP INT TERM
    rollback
    /bin/rm -rf -- "$scratch"
    if [[ "$rollback_failed" == false ]]; then /bin/rm -rf -- "$staged"; fi
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM
if [[ "$host_was_present" == true ]]; then
    "$swap_binary" "$staged" "$HOST_PATH"
    swapped=true
else
    /bin/mv "$staged" "$HOST_PATH"
    installed_new=true
fi
"$LSREGISTER" -f "$HOST_PATH"
/usr/bin/pluginkit -r "$HOST_PATH/Contents/PlugIns/ClaudeBrowserCompanion.appex" >/dev/null 2>&1 || true
/usr/bin/pluginkit -a "$HOST_PATH/Contents/PlugIns/ClaudeBrowserCompanion.appex"
registered="$(registered_extension_paths)"
registered_count="$(printf '%s\n' "$registered" | /usr/bin/awk 'NF { count += 1 } END { print count + 0 }')"
[[ "$registered_count" == 1 \
    && "$registered" == "$HOST_PATH/Contents/PlugIns/ClaudeBrowserCompanion.appex" ]] || exit 1
/usr/bin/codesign --verify --deep --strict --verbose=4 "$HOST_PATH"
"$TRUST_PREFLIGHT" --mode verification --artifact "$HOST_PATH" \
    --profile "$HOST_PATH/Contents/embedded.provisionprofile"
"$TRUST_PREFLIGHT" --mode verification \
    --artifact "$HOST_PATH/Contents/PlugIns/ClaudeBrowserCompanion.appex" \
    --profile "$HOST_PATH/Contents/PlugIns/ClaudeBrowserCompanion.appex/Contents/embedded.provisionprofile"
[[ "$(bundle_tree_sha256 "$HOST_PATH")" == "$(plist "$receipt" hostBundleSHA256)" \
    && "$(bundle_tree_sha256 "$HOST_PATH/Contents/PlugIns/ClaudeBrowserCompanion.appex")" == "$(plist "$receipt" extensionBundleSHA256)" ]] || exit 1
rollback_required=false
printf 'SAFARI_HOST_MIGRATION_INSTALLED path=%s extension=%s registration_count=1\n' "$HOST_PATH" "$EXTENSION_ID"
