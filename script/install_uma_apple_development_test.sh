#!/usr/bin/env bash
# Installs one verified Apple Development artifact at UMA's stable Test Channel
# path. Immutable package artifacts are never active installations.
set -euo pipefail
umask 077

readonly REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
readonly DELIVERY_VOLUME="/Volumes/HE/DEV"
readonly DELIVERY_ROOT="$DELIVERY_VOLUME/UMA/Packages"
# Registration inventory compatibility only; never a build-output or active-install root.
readonly LEGACY_DEVELOPMENT_PACKAGE_ROOT="$HOME/Developer/UMA-Packages"
readonly CANONICAL_INSTALL_PATH="$HOME/Applications/UMA_0.13.0-Test.app"
readonly APP_ID="com.silkrd.uma.test"
readonly EXTENSION_ID="$APP_ID.ClaudeBrowserCompanion"
readonly NATIVE_HOST_ID="$APP_ID.ClaudeBrowserNativeHost"
readonly STATUS_RELAY_ID="$APP_ID.ClaudeStatusLineRelay"
readonly EXPECTED_TEAM="C6TUZVJ6SJ"
readonly EXPECTED_AUTHORITY="Apple Development: SHAOTING HE (5BN4FAQSUF)"
readonly EXPECTED_DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer"
readonly LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"
readonly ATOMIC_SWAP_SOURCE="$REPO_ROOT/AppleDevelopmentSigning/TestChannelAtomicSwap.swift"
readonly INVENTORY_DIRECTORY="$HOME/Library/Application Support/CodexUsageMonitor/SafariTestChannel"
readonly INVENTORY_RECEIPT="$INVENTORY_DIRECTORY/inventory.plist"
runtime_generation_id=""

# A mutable UMA install is not a Safari containing-app install. Delegate before
# the legacy combined-app parser can require or inspect a nested appex.
for ((argument_index = 1; argument_index <= $#; argument_index += 1)); do
    if [[ "${!argument_index}" == --packaging-mode ]]; then
        value_index=$((argument_index + 1))
        if (( value_index <= $# )) && [[ "${!value_index}" == UMA_APP_ONLY ]]; then
            exec "$REPO_ROOT/script/install_uma_app_only_test.sh" "$@"
        fi
    fi
done

usage() {
    printf '%s\n' \
        "Usage:" \
        "  $0 --artifact <package/UMA_0.13.0-Test.zip> --expected-version <app-version>" \
        "     --expected-extension-version <extension-version>" \
        "     --expected-app-build <build> --expected-extension-build <build>" \
        "     --packaging-mode <UMA_APP_ONLY|APP_ONLY|COMPANION_MIGRATION>" \
        "  $0 --classify-inventory --expected-extension-version <version> --expected-extension-build <build>" \
        "     --safari-running <yes|no> --observed-version <version|none>" \
        "     --observed-extension-build <build|none>" \
        "  $0 --mark-inventory-current --expected-version <app-version>" \
        "     --expected-extension-version <extension-version>" \
        "     --expected-app-build <build> --expected-extension-build <build> --handshake-verified" \
        "  $0 --classify-launchservices-path <absolute-app-path>" \
        "  $0 --retire-historical-development-apps" \
        "  $0 --print-transition-contract"
}

print_transition_contract() {
    printf '%s\n' \
        'NO_TEST_APP->INSTALLING' \
        'READY_OLD_BUILD->INSTALLING_NEW_BUILD' \
        'INSTALLING->SIGNED_APP_INSTALLED' \
        'INSTALLING_NEW_BUILD->SIGNED_APP_INSTALLED' \
        'SIGNED_APP_INSTALLED->EXTENSION_REGISTERED' \
        'EXTENSION_REGISTERED->SAFARI_INVENTORY_CURRENT' \
        'EXTENSION_REGISTERED->SAFARI_INVENTORY_STALE' \
        'SAFARI_INVENTORY_STALE->SAFARI_RESTART_REQUIRED' \
        'SAFARI_RESTART_REQUIRED->SAFARI_INVENTORY_CURRENT' \
        'SAFARI_INVENTORY_CURRENT->COMPANION_STARTING' \
        'COMPANION_STARTING->COMPANION_VERIFIED' \
        'COMPANION_VERIFIED->READY'
}

classify_launchservices_path() {
    local candidate="$1"
    local package_directory normalized_package_directory
    if [[ "$candidate" == "$CANONICAL_INSTALL_PATH" ]]; then
        printf '%s\n' 'CANONICAL_TEST_APP'
    elif [[ "$candidate" == "$HOME/Desktop/"* \
        || "$candidate" == /Applications/* \
        || "$candidate" == "$HOME/Applications/"* \
        || "$candidate" == *'/Archive/'* \
        || "$candidate" == *'/Archives/'* \
        || "$candidate" == *'/Rollback/'* ]]; then
        printf '%s\n' 'PROTECTED_APP'
    elif [[ "$candidate" == "$DELIVERY_ROOT"/uma-*/UMA_0.13.0-Test.app \
        || "$candidate" == "$LEGACY_DEVELOPMENT_PACKAGE_ROOT"/uma-*/UMA_0.13.0-Test.app ]]; then
        if [[ "$candidate" == "$DELIVERY_ROOT"/* ]]; then
            package_directory="${candidate#"$DELIVERY_ROOT"/}"
        else
            package_directory="${candidate#"$LEGACY_DEVELOPMENT_PACKAGE_ROOT"/}"
        fi
        package_directory="${package_directory%%/*}"
        normalized_package_directory="$(printf '%s' "$package_directory" | /usr/bin/tr '[:upper:]' '[:lower:]')"
        if [[ "$normalized_package_directory" == *final* \
            || "$normalized_package_directory" == *release* \
            || "$normalized_package_directory" == *preflight* \
            || "$normalized_package_directory" == *archive* \
            || "$normalized_package_directory" == *rollback* \
            || "$normalized_package_directory" == *notary* ]]; then
            printf '%s\n' 'PROTECTED_PACKAGE_ARTIFACT'
        elif [[ "$normalized_package_directory" == uma-0.13-dev-* \
            || "$normalized_package_directory" == *apple-dev-test* \
            || "$normalized_package_directory" == *development-test* \
            || "$normalized_package_directory" == *signed-test* \
            || "$normalized_package_directory" == *inventory-test* \
            || "$normalized_package_directory" == *safari-test* ]]; then
            printf '%s\n' 'RETIRE_TASK_OWNED_DEVELOPMENT_REGISTRATION'
        else
            printf '%s\n' 'PROTECTED_PACKAGE_ARTIFACT'
        fi
    else
        printf '%s\n' 'UNRELATED'
    fi
}


artifact=""
expected_version=""
expected_extension_version=""
expected_app_build=""
expected_extension_build=""
classify_launchservices_candidate=""
classify_inventory=0
mark_inventory_current=0
handshake_verified=0
print_contract=0
retire_historical_apps=0
safari_running=""
observed_version=""
observed_extension_build=""
packaging_mode=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --artifact) artifact="${2:-}"; shift 2 ;;
        --expected-version) expected_version="${2:-}"; shift 2 ;;
        --expected-extension-version) expected_extension_version="${2:-}"; shift 2 ;;
        --expected-app-build) expected_app_build="${2:-}"; shift 2 ;;
        --expected-extension-build) expected_extension_build="${2:-}"; shift 2 ;;
        --classify-launchservices-path) classify_launchservices_candidate="${2:-}"; shift 2 ;;
        --classify-inventory) classify_inventory=1; shift ;;
        --mark-inventory-current) mark_inventory_current=1; shift ;;
        --handshake-verified) handshake_verified=1; shift ;;
        --print-transition-contract) print_contract=1; shift ;;
        --retire-historical-development-apps) retire_historical_apps=1; shift ;;
        --safari-running) safari_running="${2:-}"; shift 2 ;;
        --observed-version) observed_version="${2:-}"; shift 2 ;;
        --observed-extension-build) observed_extension_build="${2:-}"; shift 2 ;;
        --packaging-mode) packaging_mode="${2:-}"; shift 2 ;;
        *) usage >&2; exit 2 ;;
    esac
done

retire_historical_development_apps() {
    local app parent archive receipt scratch original_tree extracted_tree bundle_id
    while IFS= read -r app; do
        [[ -n "$app" ]] || continue
        [[ -d "$app" && ! -L "$app" \
            && "$(/usr/bin/stat -f %u "$app")" == "$(/usr/bin/id -u)" \
            && "$(classify_launchservices_path "$app")" == RETIRE_TASK_OWNED_DEVELOPMENT_REGISTRATION ]] || {
            printf 'Refusing unsafe historical Test artifact: %s\n' "$app" >&2
            return 1
        }
        bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")"
        [[ "$bundle_id" == "$APP_ID" ]] || {
            printf 'Refusing unexpected historical bundle identity: %s\n' "$bundle_id" >&2
            return 1
        }
        parent="$(dirname "$app")"
        archive="$parent/$(basename "$app" .app)-retired.zip"
        receipt="$parent/$(basename "$app" .app)-retired.receipt.plist"
        [[ ! -e "$archive" && ! -L "$archive" && ! -e "$receipt" && ! -L "$receipt" ]] || {
            printf 'Refusing existing retirement output in %s\n' "$parent" >&2
            return 1
        }
        scratch="$(/usr/bin/mktemp -d /private/tmp/uma-test-retirement.XXXXXX)"
        original_tree="$(
            cd "$app"
            /usr/bin/find . -type f -print0 | LC_ALL=C /usr/bin/sort -z \
                | /usr/bin/xargs -0 /usr/bin/shasum -a 256 \
                | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}'
        )"
        /usr/bin/ditto -c -k --keepParent "$app" "$archive"
        /usr/bin/ditto -x -k "$archive" "$scratch"
        extracted="$scratch/$(basename "$app")"
        [[ -d "$extracted" && ! -L "$extracted" && -z "$(/usr/bin/find "$extracted" -type l -print -quit)" ]]
        extracted_tree="$(
            cd "$extracted"
            /usr/bin/find . -type f -print0 | LC_ALL=C /usr/bin/sort -z \
                | /usr/bin/xargs -0 /usr/bin/shasum -a 256 \
                | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}'
        )"
        [[ "$extracted_tree" == "$original_tree" ]] || {
            /bin/rm -rf -- "$scratch"
            printf 'Historical archive integrity mismatch: %s\n' "$app" >&2
            return 1
        }
        /usr/bin/plutil -create xml1 "$receipt"
        /usr/bin/plutil -insert schemaVersion -integer 1 "$receipt"
        /usr/bin/plutil -insert originalPath -string "$app" "$receipt"
        /usr/bin/plutil -insert bundleIdentifier -string "$bundle_id" "$receipt"
        /usr/bin/plutil -insert treeSHA256 -string "$original_tree" "$receipt"
        /usr/bin/plutil -insert archiveSHA256 -string "$(/usr/bin/shasum -a 256 "$archive" | /usr/bin/awk '{print $1}')" "$receipt"
        /usr/bin/plutil -insert retiredAt -string "$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)" "$receipt"
        /bin/chmod 600 "$archive" "$receipt"
        /usr/bin/pluginkit -r "$app/Contents/PlugIns/ClaudeBrowserCompanion.appex" >/dev/null 2>&1 || true
        "$LSREGISTER" -u "$app" >/dev/null 2>&1 || true
        /bin/rm -rf -- "$app"
        /bin/rm -rf -- "$scratch"
        printf 'HISTORICAL_TEST_APP_RETIRED archive=%s receipt=%s\n' "$archive" "$receipt"
    done < <(
        for package_root in "$DELIVERY_ROOT" "$LEGACY_DEVELOPMENT_PACKAGE_ROOT"; do
            [[ -e "$package_root" || -L "$package_root" ]] || continue
            [[ -d "$package_root" \
                && "$(/usr/bin/stat -f %u "$package_root")" == "$(/usr/bin/id -u)" ]] || {
                printf 'Refusing unsafe historical package root: %s\n' "$package_root" >&2
                exit 1
            }
            /usr/bin/find -H "$package_root" -mindepth 2 -maxdepth 2 -type d \
                -name UMA_0.13.0-Test.app -print
        done | while IFS= read -r candidate; do
            [[ "$(classify_launchservices_path "$candidate")" \
                == RETIRE_TASK_OWNED_DEVELOPMENT_REGISTRATION ]] \
                && printf '%s\n' "$candidate"
        done | LC_ALL=C /usr/bin/sort -u
    )
}

if [[ "$retire_historical_apps" == 1 ]]; then
    retire_historical_development_apps
    exit 0
fi

if [[ -n "$classify_launchservices_candidate" ]]; then
    [[ "$classify_launchservices_candidate" == /* ]] || { usage >&2; exit 2; }
    classify_launchservices_path "$classify_launchservices_candidate"
    exit 0
fi

if [[ "$print_contract" == 1 ]]; then
    print_transition_contract
    exit 0
fi

if [[ "$classify_inventory" == 1 ]]; then
    [[ -n "$expected_extension_version" && -n "$expected_extension_build" \
        && "$safari_running" =~ ^(yes|no)$ \
        && -n "$observed_version" && -n "$observed_extension_build" ]] || {
        usage >&2
        exit 2
    }
    if [[ "$safari_running" == no ]]; then
        printf 'SAFARI_INVENTORY_REFRESH_ON_LAUNCH restart_required=false\n'
    elif [[ "$observed_version" == "$expected_extension_version" \
        && "$observed_extension_build" == "$expected_extension_build" ]]; then
        printf 'SAFARI_INVENTORY_CURRENT restart_required=false\n'
    else
        printf 'SAFARI_INVENTORY_STALE restart_required=true\n'
    fi
    exit 0
fi

validate_identity_arguments() {
    [[ -n "$expected_version" && "$expected_version" =~ ^[0-9]+([.][0-9]+)*$ \
        && -n "$expected_extension_version" && "$expected_extension_version" =~ ^[0-9]+([.][0-9]+)*$ \
        && -n "$expected_app_build" && "$expected_app_build" =~ ^[0-9]+$ \
        && -n "$expected_extension_build" && "$expected_extension_build" =~ ^[0-9]+$ ]]
}

bundle_tree_sha256() {
    local bundle="$1"
    (
        cd "$bundle"
        /usr/bin/find . -mindepth 1 -print0 | LC_ALL=C /usr/bin/sort -z \
            | while IFS= read -r -d '' entry; do
                if [[ -L "$entry" ]]; then
                    printf 'L\0%s\0%s\0' "$entry" "$(/usr/bin/readlink "$entry")"
                elif [[ -d "$entry" ]]; then
                    printf 'D\0%s\0%s\0' "$entry" "$(/usr/bin/stat -f %Lp "$entry")"
                elif [[ -f "$entry" ]]; then
                    printf 'F\0%s\0%s\0%s\0' "$entry" \
                        "$(/usr/bin/stat -f %Lp "$entry")" \
                        "$(/usr/bin/shasum -a 256 "$entry" | /usr/bin/awk '{print $1}')"
                else
                    printf 'UNSUPPORTED\0%s\0' "$entry"
                fi
            done
    ) | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}'
}

plist_value() {
    /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist"
}

verify_bundle_identity() {
    local app="$1"
    local appex="$app/Contents/PlugIns/ClaudeBrowserCompanion.appex"
    [[ "$(plist_value "$app" CFBundleIdentifier)" == "$APP_ID" \
        && "$(plist_value "$app" CFBundleShortVersionString)" == "$expected_version" \
        && "$(plist_value "$app" CFBundleVersion)" == "$expected_app_build" \
        && "$(plist_value "$appex" CFBundleIdentifier)" == "$EXTENSION_ID" \
        && "$(plist_value "$appex" CFBundleShortVersionString)" == "$expected_extension_version" \
        && "$(plist_value "$appex" CFBundleVersion)" == "$expected_extension_build" ]]
}

verify_runtime_generation() {
    local app="$1"
    local appex="$app/Contents/PlugIns/ClaudeBrowserCompanion.appex"
    [[ "$(plist_value "$app" UMATestRuntimeGenerationID)" == "$runtime_generation_id" \
        && "$(plist_value "$appex" UMATestRuntimeGenerationID)" == "$runtime_generation_id" \
        && "$(plist_value "$app" UMARuntimeGenerationID)" == "$runtime_generation_id" \
        && "$(plist_value "$appex" UMARuntimeGenerationID)" == "$runtime_generation_id" \
        && "$(plist_value "$app" UMAContainingApplicationIdentifier)" == "$APP_ID" \
        && "$(plist_value "$appex" UMAContainingApplicationIdentifier)" == "$APP_ID" \
        && "$(plist_value "$app" UMAExtensionBundleIdentifier)" == "$EXTENSION_ID" \
        && "$(plist_value "$appex" UMAExtensionBundleIdentifier)" == "$EXTENSION_ID" \
        && "$(plist_value "$app" UMARuntimeChannel)" == test \
        && "$(plist_value "$appex" UMARuntimeChannel)" == test \
        && "$(plist_value "$app" UMAExtensionVersion)" == "$expected_extension_version" \
        && "$(plist_value "$appex" UMAExtensionVersion)" == "$expected_extension_version" \
        && "$(plist_value "$app" UMAExtensionBuild)" == "$expected_extension_build" \
        && "$(plist_value "$appex" UMAExtensionBuild)" == "$expected_extension_build" \
        && "$(plist_value "$app" UMAAppPackageGenerationID)" == "$app_package_generation_id" \
        && "$(plist_value "$app" UMAPackagingMode)" == "$packaging_mode" \
        && "$(plist_value "$app" UMATeamIdentifier)" == "$EXPECTED_TEAM" \
        && "$(plist_value "$appex" UMATeamIdentifier)" == "$EXPECTED_TEAM" ]]
}

ensure_inventory_directory() {
    /bin/mkdir -p "$INVENTORY_DIRECTORY"
    [[ -d "$INVENTORY_DIRECTORY" && ! -L "$INVENTORY_DIRECTORY" \
        && "$(/usr/bin/stat -f %u "$INVENTORY_DIRECTORY")" == "$(/usr/bin/id -u)" ]] || {
        printf '%s\n' 'Unsafe Safari Test Channel inventory directory.' >&2
        exit 1
    }
    /bin/chmod 700 "$INVENTORY_DIRECTORY"
    if [[ -e "$INVENTORY_RECEIPT" || -L "$INVENTORY_RECEIPT" ]]; then
        [[ -f "$INVENTORY_RECEIPT" && ! -L "$INVENTORY_RECEIPT" \
            && "$(/usr/bin/stat -f %u "$INVENTORY_RECEIPT")" == "$(/usr/bin/id -u)" ]] || {
            printf '%s\n' 'Unsafe Safari Test Channel inventory receipt.' >&2
            exit 1
        }
    fi
}

write_inventory_receipt() {
    local lifecycle_state="$1"
    local verified="$2"
    ensure_inventory_directory
    local temporary
    temporary="$(/usr/bin/mktemp "$INVENTORY_DIRECTORY/.inventory.XXXXXX")"
    /usr/bin/plutil -create xml1 "$temporary"
    /usr/bin/plutil -insert schemaVersion -integer 2 "$temporary"
    /usr/bin/plutil -insert canonicalAppPath -string "$CANONICAL_INSTALL_PATH" "$temporary"
    /usr/bin/plutil -insert appBundleIdentifier -string "$APP_ID" "$temporary"
    /usr/bin/plutil -insert appVersion -string "$expected_version" "$temporary"
    /usr/bin/plutil -insert appBuild -string "$expected_app_build" "$temporary"
    /usr/bin/plutil -insert extensionBundleIdentifier -string "$EXTENSION_ID" "$temporary"
    /usr/bin/plutil -insert extensionVersion -string "$expected_extension_version" "$temporary"
    /usr/bin/plutil -insert extensionBuild -string "$expected_extension_build" "$temporary"
    /usr/bin/plutil -insert teamIdentifier -string "$EXPECTED_TEAM" "$temporary"
    if [[ -z "$runtime_generation_id" && -d "$CANONICAL_INSTALL_PATH" ]]; then
        runtime_generation_id="$(plist_value "$CANONICAL_INSTALL_PATH" UMATestRuntimeGenerationID)"
    fi
    /usr/bin/plutil -insert runtimeGenerationID -string "$runtime_generation_id" "$temporary"
    /usr/bin/plutil -insert lifecycleState -string "$lifecycle_state" "$temporary"
    /usr/bin/plutil -insert handshakeVerified -bool "$verified" "$temporary"
    /usr/bin/plutil -insert updatedAt -string "$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)" "$temporary"
    /usr/bin/plutil -lint "$temporary" >/dev/null
    /bin/chmod 600 "$temporary"
    /bin/mv -f "$temporary" "$INVENTORY_RECEIPT"
    [[ ! -L "$INVENTORY_RECEIPT" \
        && "$(/usr/bin/stat -f %Lp "$INVENTORY_RECEIPT")" == 600 ]]
}

if [[ "$mark_inventory_current" == 1 ]]; then
    validate_identity_arguments && [[ "$handshake_verified" == 1 ]] || {
        printf '%s\n' 'inventoryCurrent requires an explicit machine handshake receipt.' >&2
        exit 2
    }
    [[ -d "$CANONICAL_INSTALL_PATH" && ! -L "$CANONICAL_INSTALL_PATH" ]] \
        && verify_bundle_identity "$CANONICAL_INSTALL_PATH" || {
        printf '%s\n' 'Canonical Test App identity does not match the verified handshake.' >&2
        exit 1
    }
    /usr/bin/codesign --verify --deep --strict --verbose=2 "$CANONICAL_INSTALL_PATH"
    write_inventory_receipt inventoryCurrent true
    printf 'SAFARI_TEST_CHANNEL_INVENTORY_CURRENT receipt=%s active_install=%s app_version=%s extension_version=%s app_build=%s extension_build=%s team=%s handshake_verified=true\n' \
        "$INVENTORY_RECEIPT" "$CANONICAL_INSTALL_PATH" "$expected_version" "$expected_extension_version" \
        "$expected_app_build" "$expected_extension_build" "$EXPECTED_TEAM"
    exit 0
fi

validate_identity_arguments && [[ -n "$artifact" \
    && ( "$packaging_mode" == APP_ONLY || "$packaging_mode" == COMPANION_MIGRATION ) ]] \
    || { usage >&2; exit 2; }
[[ "${DEVELOPER_DIR:-}" == "$EXPECTED_DEVELOPER_DIR" ]] || {
    printf 'Required task-scoped DEVELOPER_DIR is %s\n' "$EXPECTED_DEVELOPER_DIR" >&2
    exit 2
}
mount_line="$(/sbin/mount | /usr/bin/grep -E " on $DELIVERY_VOLUME \\(apfs," || true)"
[[ -n "$mount_line" && "$mount_line" != *read-only* && -w "$DELIVERY_VOLUME" ]] || {
    printf '%s\n' 'STOP — DEV_APFS_NOT_MOUNTED' >&2
    exit 1
}
[[ "$artifact" == "$DELIVERY_ROOT"/uma-*/UMA_0.13.0-Test.zip \
    && -f "$artifact" && ! -L "$artifact" ]] || {
    printf 'Artifact is outside the immutable package boundary, absent, or symbolic: %s\n' "$artifact" >&2
    exit 2
}
[[ "$(/usr/bin/stat -f %u "$artifact")" == "$(/usr/bin/id -u)" ]] || {
    printf 'Artifact is not owned by the current user: %s\n' "$artifact" >&2
    exit 1
}
readonly canonical_artifact="$(cd "$(dirname "$artifact")" && pwd -P)/$(basename "$artifact")"
[[ "$canonical_artifact" == "$artifact" ]] || {
    printf 'Artifact path is not canonical: %s\n' "$artifact" >&2
    exit 1
}
readonly package_receipt="${artifact%.zip}.receipt.plist"
[[ -f "$package_receipt" && ! -L "$package_receipt" \
    && "$(/usr/bin/stat -f %u "$package_receipt")" == "$(/usr/bin/id -u)" ]] || {
    printf '%s\n' 'Immutable package receipt is missing or unsafe.' >&2
    exit 1
}
[[ "$(/usr/libexec/PlistBuddy -c 'Print :schemaVersion' "$package_receipt")" == 3 \
    && "$(/usr/libexec/PlistBuddy -c 'Print :archiveFilename' "$package_receipt")" == "$(basename "$artifact")" \
    && "$(/usr/libexec/PlistBuddy -c 'Print :appBundleIdentifier' "$package_receipt")" == "$APP_ID" \
    && "$(/usr/libexec/PlistBuddy -c 'Print :extensionBundleIdentifier' "$package_receipt")" == "$EXTENSION_ID" \
    && "$(/usr/libexec/PlistBuddy -c 'Print :appVersion' "$package_receipt")" == "$expected_version" \
    && "$(/usr/libexec/PlistBuddy -c 'Print :appBuild' "$package_receipt")" == "$expected_app_build" \
    && "$(/usr/libexec/PlistBuddy -c 'Print :extensionVersion' "$package_receipt")" == "$expected_extension_version" \
    && "$(/usr/libexec/PlistBuddy -c 'Print :extensionBuild' "$package_receipt")" == "$expected_extension_build" \
    && "$(/usr/libexec/PlistBuddy -c 'Print :teamIdentifier' "$package_receipt")" == "$EXPECTED_TEAM" \
    && "$(/usr/libexec/PlistBuddy -c 'Print :runtimeChannel' "$package_receipt")" == test \
    && "$(/usr/libexec/PlistBuddy -c 'Print :packagingMode' "$package_receipt")" == "$packaging_mode" ]] || {
    printf '%s\n' 'Immutable package receipt identity mismatch.' >&2
    exit 1
}
archive_sha256="$(/usr/bin/shasum -a 256 "$artifact" | /usr/bin/awk '{print $1}')"
[[ "$archive_sha256" == "$(/usr/libexec/PlistBuddy -c 'Print :archiveSHA256' "$package_receipt")" ]] || {
    printf '%s\n' 'Immutable package archive hash mismatch.' >&2
    exit 1
}

readonly scratch="$(/usr/bin/mktemp -d /private/tmp/uma-test-channel-install.XXXXXX)"
staged_app=""
cleanup() {
    if [[ -n "$staged_app" && -d "$staged_app" && ! -L "$staged_app" \
        && "$(/usr/bin/dirname "$staged_app")" == "$HOME/Applications" \
        && "$(/usr/bin/stat -f %u "$staged_app")" == "$(/usr/bin/id -u)" \
        && "$(/usr/bin/basename "$staged_app")" == .UMA_0.13.0-Test.install.* ]]; then
        /bin/rm -rf -- "$staged_app"
    fi
    /bin/rm -rf -- "$scratch"
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM

archive_listing="$scratch/archive-listing.txt"
/usr/bin/zipinfo -1 "$artifact" > "$archive_listing"
[[ -s "$archive_listing" \
    && -z "$(/usr/bin/grep -E '(^/|(^|/)\.\.(/|$))' "$archive_listing" || true)" \
    && "$(/usr/bin/awk -F/ 'NF {print $1}' "$archive_listing" | /usr/bin/sort -u)" == UMA_0.13.0-Test.app ]] || {
    printf '%s\n' 'Archive root or traversal contract failed.' >&2
    exit 1
}
extract_root="$scratch/extracted"
/bin/mkdir "$extract_root"
/usr/bin/ditto -x -k "$artifact" "$extract_root"
artifact="$extract_root/UMA_0.13.0-Test.app"
[[ -d "$artifact" && ! -L "$artifact" && -z "$(/usr/bin/find "$artifact" -type l -print -quit)" ]] || {
    printf '%s\n' 'Extracted Test App is missing, symbolic, or contains symbolic links.' >&2
    exit 1
}

readonly artifact_appex="$artifact/Contents/PlugIns/ClaudeBrowserCompanion.appex"
readonly artifact_native_host="$artifact/Contents/Helpers/ClaudeBrowserNativeHost"
readonly artifact_status_relay="$artifact/Contents/Helpers/ClaudeStatusLineRelay"
for target in "$artifact" "$artifact_appex" "$artifact_native_host" "$artifact_status_relay"; do
    [[ -e "$target" && ! -L "$target" ]] || {
        printf 'Required signed component missing or symbolic: %s\n' "$target" >&2
        exit 1
    }
done
verify_bundle_identity "$artifact" || {
    printf '%s\n' 'Artifact bundle identity/version/build mismatch.' >&2
    exit 1
}
runtime_generation_id="$(plist_value "$artifact" UMATestRuntimeGenerationID)"
appex_generation_id="$(plist_value "$artifact_appex" UMATestRuntimeGenerationID)"
receipt_generation_id="$(/usr/libexec/PlistBuddy -c 'Print :runtimeGenerationID' "$package_receipt")"
app_package_generation_id="$(/usr/libexec/PlistBuddy -c 'Print :appPackageGenerationID' "$package_receipt")"
[[ "$runtime_generation_id" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ \
    && "$appex_generation_id" == "$runtime_generation_id" \
    && "$receipt_generation_id" == "$runtime_generation_id" \
    && "$app_package_generation_id" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] || {
    printf '%s\n' 'RUNTIME_IDENTITY_AMBIGUOUS: package generation mismatch.' >&2
    exit 1
}
verify_runtime_generation "$artifact" || {
    printf '%s\n' 'RUNTIME_IDENTITY_AMBIGUOUS: signed bundle metadata mismatch.' >&2
    exit 1
}
/usr/bin/codesign --verify --deep --strict --verbose=2 "$artifact"

verify_signer() {
    local target="$1"
    local identifier="$2"
    local report="$3"
    /usr/bin/codesign -d --verbose=4 "$target" 2> "$report"
    /usr/bin/grep -Fx -q "Identifier=$identifier" "$report"
    /usr/bin/grep -Fx -q "Authority=$EXPECTED_AUTHORITY" "$report"
    /usr/bin/grep -Fx -q "TeamIdentifier=$EXPECTED_TEAM" "$report"
    ! /usr/bin/grep -Fx -q 'Signature=adhoc' "$report"
}
verify_signer "$artifact_native_host" "$NATIVE_HOST_ID" "$scratch/native-host.signing"
verify_signer "$artifact_status_relay" "$STATUS_RELAY_ID" "$scratch/status-relay.signing"
verify_signer "$artifact_appex" "$EXTENSION_ID" "$scratch/appex.signing"
verify_signer "$artifact" "$APP_ID" "$scratch/app.signing"

readonly artifact_extension_hash="$(
    /usr/bin/shasum -a 256 "$artifact_appex/Contents/MacOS/ClaudeBrowserCompanion" \
        | /usr/bin/awk '{print $1}'
)"
readonly receipt_extension_hash="$(/usr/libexec/PlistBuddy -c 'Print :extensionExecutableSHA256' "$package_receipt")"
readonly receipt_extension_cdhash="$(/usr/libexec/PlistBuddy -c 'Print :extensionCDHash' "$package_receipt")"
readonly receipt_extension_bundle_sha256="$(/usr/libexec/PlistBuddy -c 'Print :extensionBundleSHA256' "$package_receipt")"
readonly artifact_extension_bundle_sha256="$(bundle_tree_sha256 "$artifact_appex")"
readonly artifact_extension_cdhash="$(
    /usr/bin/awk -F= '/^CDHash=/{print $2; exit}' "$scratch/appex.signing"
)"
[[ "$artifact_extension_hash" == "$receipt_extension_hash" \
    && "$artifact_extension_cdhash" == "$receipt_extension_cdhash" \
    && "$artifact_extension_bundle_sha256" == "$receipt_extension_bundle_sha256" ]] || {
    printf '%s\n' 'UNINTENDED_COMPANION_MUTATION: artifact Companion differs from receipt.' >&2
    exit 1
}
readonly artifact_app_cdhash="$(
    /usr/bin/awk -F= '/^CDHash=/{print $2; exit}' "$scratch/app.signing"
)"
readonly canonical_appex="$CANONICAL_INSTALL_PATH/Contents/PlugIns/ClaudeBrowserCompanion.appex"
readonly launchservices_query="$scratch/LaunchServicesUMAInventory"
CLANG_MODULE_CACHE_PATH="$scratch/launchservices-module-cache" /usr/bin/xcrun swiftc \
    -o "$launchservices_query" - <<'SWIFT'
import AppKit
import CoreServices
import Darwin
import Foundation

if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--resolve" {
    print(
        URL(fileURLWithPath: CommandLine.arguments[2])
            .resolvingSymlinksInPath()
            .standardizedFileURL.path
    )
} else if CommandLine.arguments.count == 1 {
    let urls = LSCopyApplicationURLsForBundleIdentifier(
        "com.silkrd.uma.test" as CFString,
        nil
    )?.takeRetainedValue() as? [URL] ?? []
    for path in Set(urls.map { $0.standardizedFileURL.path }).sorted() {
        print(path)
    }
} else {
    exit(2)
}
SWIFT

launchservices_app_paths() {
    "$launchservices_query" | /usr/bin/sort -u
}

launchservices_resolved_path() {
    [[ $# == 1 ]] || return 2
    "$launchservices_query" --resolve "$1"
}
validated_resolved_retirement_path() {
    local recorded_path="$1"
    local recorded_classification resolved_path resolved_classification
    recorded_classification="$(classify_launchservices_path "$recorded_path")"
    [[ "$recorded_classification" == RETIRE_TASK_OWNED_DEVELOPMENT_REGISTRATION \
        && -d "$recorded_path" && ! -L "$recorded_path" \
        && "$(/usr/bin/stat -f %u "$recorded_path")" == "$(/usr/bin/id -u)" ]] || return 1
    if [[ "$recorded_path" == "$LEGACY_DEVELOPMENT_PACKAGE_ROOT"/* ]]; then
        [[ -L "$LEGACY_DEVELOPMENT_PACKAGE_ROOT" \
            && "$(/usr/bin/stat -f %u "$LEGACY_DEVELOPMENT_PACKAGE_ROOT")" == "$(/usr/bin/id -u)" ]] \
            || return 1
    fi
    resolved_path="$(launchservices_resolved_path "$recorded_path")" || return 1
    resolved_classification="$(classify_launchservices_path "$resolved_path")"
    [[ "$resolved_classification" == RETIRE_TASK_OWNED_DEVELOPMENT_REGISTRATION \
        && -d "$resolved_path" && ! -L "$resolved_path" \
        && "$(/usr/bin/stat -f %u "$resolved_path")" == "$(/usr/bin/id -u)" ]] || return 1
    printf '%s\n' "$resolved_path"
}

retire_stale_launchservices_registrations() {
    local app_path classification resolved_path
    while IFS= read -r app_path; do
        [[ -n "$app_path" ]] || continue
        classification="$(classify_launchservices_path "$app_path")"
        if [[ "$classification" == RETIRE_TASK_OWNED_DEVELOPMENT_REGISTRATION ]]; then
            resolved_path="$(validated_resolved_retirement_path "$app_path")" || {
                printf '%s\n' 'Stale LaunchServices alias failed ownership or resolved-target validation.' >&2
                return 1
            }
            "$LSREGISTER" -u "$app_path" >/dev/null 2>&1 || true
            if [[ "$resolved_path" != "$app_path" ]]; then
                "$LSREGISTER" -u "$resolved_path" >/dev/null 2>&1 || true
            fi
        fi
    done < <(launchservices_app_paths)
}

require_canonical_launchservices_registration() {
    local owner_paths
    owner_paths="$(launchservices_app_paths)"
    [[ "$owner_paths" == "$CANONICAL_INSTALL_PATH" ]] || {
        printf 'RUNTIME_IDENTITY_AMBIGUOUS: LaunchServices owners=%s\n' \
            "${owner_paths:-none}" >&2
        return 1
    }
}


registered_extension_paths() {
    # -vv exposes the current `Path = ...appex` record; the second anchored rule
    # preserves the older single-line pluginkit format across supported macOS versions.
    /usr/bin/pluginkit -m -A -D -vv -i "$EXTENSION_ID" 2>/dev/null \
        | /usr/bin/sed -nE \
            's#^[[:space:]]*Path = (/.*\.appex)[[:space:]]*$#\1#p; s#^.* (/.*\.appex)[[:space:]]*$#\1#p' \
        | /usr/bin/sort -u
}

retire_task_owned_package_registrations() {
    local registered_appex containing_package_app classification
    while IFS= read -r registered_appex; do
        [[ -n "$registered_appex" ]] || continue
        containing_package_app="${registered_appex%/Contents/PlugIns/ClaudeBrowserCompanion.appex}"
        classification="$(classify_launchservices_path "$containing_package_app")"
        if [[ "$classification" == RETIRE_TASK_OWNED_DEVELOPMENT_REGISTRATION ]]; then
            /usr/bin/pluginkit -r "$registered_appex" >/dev/null 2>&1 || true
            "$LSREGISTER" -u "$containing_package_app" >/dev/null 2>&1 || true
            if registered_extension_paths | /usr/bin/grep -F -x -q "$registered_appex"; then
                printf 'Task-owned stale extension registration remains: %s\n' "$registered_appex" >&2
                return 1
            fi
        fi
    done < <(registered_extension_paths)
}

require_unique_canonical_registration() {
    local registration_paths="$scratch/pluginkit-paths.txt"
    registered_extension_paths > "$registration_paths"
    local registered_path_count canonical_path_count
    registered_path_count="$(/usr/bin/awk 'NF { count += 1 } END { print count + 0 }' "$registration_paths")"
    canonical_path_count="$(/usr/bin/grep -F -x -c "$canonical_appex" "$registration_paths" || true)"
    [[ "$registered_path_count" == 1 && "$canonical_path_count" == 1 ]] || {
        printf 'RUNTIME_IDENTITY_AMBIGUOUS: PlugInKit owners count=%s canonical=%s\n' \
            "$registered_path_count" "$canonical_path_count" >&2
        return 1
    }
}

reconcile_canonical_registration_once() {
    local ls_owners plugin_owners
    ls_owners="$(launchservices_app_paths)"
    plugin_owners="$(registered_extension_paths)"
    if [[ -n "$ls_owners" && "$ls_owners" != "$CANONICAL_INSTALL_PATH" ]]; then
        printf 'RUNTIME_IDENTITY_AMBIGUOUS: LaunchServices owners=%s\n' "$ls_owners" >&2
        return 1
    fi
    if [[ -n "$plugin_owners" && "$plugin_owners" != "$canonical_appex" ]]; then
        printf 'RUNTIME_IDENTITY_AMBIGUOUS: PlugInKit owners=%s\n' "$plugin_owners" >&2
        return 1
    fi
    if [[ -z "$ls_owners" ]]; then
        "$LSREGISTER" -f "$CANONICAL_INSTALL_PATH"
    fi
    if [[ -z "$plugin_owners" ]]; then
        /usr/bin/pluginkit -a "$canonical_appex"
    fi
    require_canonical_launchservices_registration
    require_unique_canonical_registration
}

if [[ "$packaging_mode" == APP_ONLY ]]; then
    [[ -d "$CANONICAL_INSTALL_PATH" && ! -L "$CANONICAL_INSTALL_PATH" \
        && -d "$canonical_appex" && ! -L "$canonical_appex" ]] || {
        printf '%s\n' 'APP_ONLY requires an existing canonical Test App with the frozen Companion.' >&2
        exit 1
    }
    /usr/bin/codesign --verify --strict --verbose=2 "$canonical_appex"
    [[ "$(bundle_tree_sha256 "$canonical_appex")" == "$receipt_extension_bundle_sha256" ]] || {
        printf '%s\n' 'UNINTENDED_COMPANION_MUTATION: installed Companion is not the frozen generation.' >&2
        exit 1
    }
    require_canonical_launchservices_registration
    require_unique_canonical_registration
fi

launch_canonical_once() {
    # `open -j` launches the LSUIElement application hidden. A hidden
    # containing app can retain its status item while AppKit suppresses the
    # panel it orders, which makes a real menu-bar click look non-responsive.
    # Keep launch in the background without putting NSApplication into the
    # hidden state.
    /usr/bin/open -ga "$CANONICAL_INSTALL_PATH"
}

installed_extension_cdhash="none"
installed_app_cdhash="none"
extension_changed=true
canonical_app_file_id="none"
canonical_extension_file_id="none"
if [[ -e "$CANONICAL_INSTALL_PATH" || -L "$CANONICAL_INSTALL_PATH" ]]; then
    [[ -d "$CANONICAL_INSTALL_PATH" && ! -L "$CANONICAL_INSTALL_PATH" ]] || {
        printf '%s\n' 'Canonical Test App destination is unsafe.' >&2
        exit 1
    }
    /usr/bin/codesign -d --verbose=4 "$CANONICAL_INSTALL_PATH" \
        2> "$scratch/current-app.signing" || true
    /usr/bin/codesign -d --verbose=4 "$canonical_appex" \
        2> "$scratch/current-appex.signing" || true
    installed_app_cdhash="$(
        /usr/bin/awk -F= '/^CDHash=/{print $2; exit}' "$scratch/current-app.signing"
    )"
    installed_extension_cdhash="$(
        /usr/bin/awk -F= '/^CDHash=/{print $2; exit}' "$scratch/current-appex.signing"
    )"
    canonical_app_file_id="$(/usr/bin/stat -f '%d:%i' "$CANONICAL_INSTALL_PATH")"
    canonical_extension_file_id="$(/usr/bin/stat -f '%d:%i' "$canonical_appex")"
    if [[ "$installed_extension_cdhash" == "$artifact_extension_cdhash" \
        && "$(bundle_tree_sha256 "$canonical_appex")" == "$artifact_extension_bundle_sha256" \
        && "$(plist_value "$canonical_appex" CFBundleShortVersionString)" == "$expected_extension_version" \
        && "$(plist_value "$canonical_appex" CFBundleVersion)" == "$expected_extension_build" ]]; then
        extension_changed=false
    fi
fi
if [[ "$installed_app_cdhash" == "$artifact_app_cdhash" ]]; then
    /usr/bin/codesign --verify --deep --strict --verbose=2 "$CANONICAL_INSTALL_PATH"
    verify_bundle_identity "$CANONICAL_INSTALL_PATH"
    verify_runtime_generation "$CANONICAL_INSTALL_PATH"
    if [[ "$packaging_mode" == APP_ONLY ]]; then
        require_canonical_launchservices_registration
        require_unique_canonical_registration
    else
        retire_task_owned_package_registrations
        retire_stale_launchservices_registrations
        reconcile_canonical_registration_once
    fi
    launch_canonical_once
    write_inventory_receipt inventoryCurrent false
    printf 'TEST_APP_ALREADY_CURRENT build_artifact=%s active_install=%s app_version=%s extension_version=%s app_build=%s extension_build=%s extension_cdhash=%s update=false inventory_refresh_required=false receipt=%s\n' \
        "$canonical_artifact" "$CANONICAL_INSTALL_PATH" "$expected_version" "$expected_extension_version" "$expected_app_build" \
        "$expected_extension_build" "$artifact_extension_cdhash" "$INVENTORY_RECEIPT"
    exit 0
fi

if [[ -d "$CANONICAL_INSTALL_PATH" ]]; then
    printf '%s\n' 'STATE READY_OLD_BUILD->INSTALLING_NEW_BUILD'
else
    printf '%s\n' 'STATE NO_TEST_APP->INSTALLING'
fi

# Stop only a process whose text image is the canonical Test App executable.
canonical_executable="$CANONICAL_INSTALL_PATH/Contents/MacOS/CodexUsageMonitor"
for pid in $(/usr/bin/pgrep -x CodexUsageMonitor 2>/dev/null || true); do
    text_path="$(/usr/sbin/lsof -a -p "$pid" -d txt -Fn 2>/dev/null \
        | /usr/bin/sed -n 's/^n//p' | /usr/bin/head -n 1)"
    if [[ "$text_path" == "$canonical_executable" ]]; then
        /bin/kill -TERM "$pid"
        /bin/sleep 1
        /bin/kill -0 "$pid" 2>/dev/null && {
            printf 'Canonical Test App did not terminate normally: pid=%s\n' "$pid" >&2
            exit 1
        }
    fi
done

/bin/mkdir -p "$HOME/Applications"
[[ ! -L "$HOME/Applications" && -d "$HOME/Applications" ]] || {
    printf '%s\n' 'Canonical Applications directory is unsafe.' >&2
    exit 1
}
staged_app="$(/usr/bin/mktemp -d "$HOME/Applications/.UMA_0.13.0-Test.install.XXXXXX")"
/usr/bin/ditto "$artifact" "$staged_app"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$staged_app"
verify_signer "$staged_app" "$APP_ID" "$scratch/staged-app.signing"
verify_signer "$staged_app/Contents/PlugIns/ClaudeBrowserCompanion.appex" \
    "$EXTENSION_ID" "$scratch/staged-appex.signing"

readonly swap_binary="$scratch/TestChannelAtomicSwap"
CLANG_MODULE_CACHE_PATH="$scratch/module-cache" /usr/bin/xcrun swiftc \
    "$ATOMIC_SWAP_SOURCE" -o "$swap_binary"
# APP_ONLY must preserve the physical identity of the canonical app and frozen
# appex directories, not merely their paths and bytes. Replacing the whole app
# bundle causes Safari to treat the byte-identical nested extension as a new
# installation and discard its Human enablement decision.
if [[ "$packaging_mode" == APP_ONLY ]]; then
    "$swap_binary" --preserve-nested-extension "$staged_app" "$CANONICAL_INSTALL_PATH"
else
    "$swap_binary" "$staged_app" "$CANONICAL_INSTALL_PATH"
fi
if [[ "$packaging_mode" == COMPANION_MIGRATION ]]; then
    "$LSREGISTER" -f "$CANONICAL_INSTALL_PATH"
fi
/usr/bin/codesign --verify --deep --strict --verbose=2 "$CANONICAL_INSTALL_PATH"
verify_bundle_identity "$CANONICAL_INSTALL_PATH"
verify_runtime_generation "$CANONICAL_INSTALL_PATH"
verify_signer "$CANONICAL_INSTALL_PATH" "$APP_ID" "$scratch/installed-app.signing"
verify_signer "$CANONICAL_INSTALL_PATH/Contents/PlugIns/ClaudeBrowserCompanion.appex" \
    "$EXTENSION_ID" "$scratch/installed-appex.signing"
printf '%s\n' 'STATE INSTALLING->SIGNED_APP_INSTALLED'
if [[ -d "$staged_app" ]]; then
    /bin/rm -rf -- "$staged_app"
fi

if [[ "$packaging_mode" == APP_ONLY ]]; then
    [[ "$extension_changed" == false \
        && "$(bundle_tree_sha256 "$canonical_appex")" == "$artifact_extension_bundle_sha256" \
        && "$(/usr/bin/stat -f '%d:%i' "$CANONICAL_INSTALL_PATH")" == "$canonical_app_file_id" \
        && "$(/usr/bin/stat -f '%d:%i' "$canonical_appex")" == "$canonical_extension_file_id" ]] || {
        printf '%s\n' 'UNINTENDED_COMPANION_MUTATION: APP_ONLY update changed Companion bytes.' >&2
        exit 1
    }
    # The canonical app and frozen appex filesystem identities are unchanged.
    # App-only updates must not mutate LaunchServices or PlugInKit.
    require_canonical_launchservices_registration
    require_unique_canonical_registration
else
    retire_stale_launchservices_registrations
    retire_task_owned_package_registrations
    reconcile_canonical_registration_once
fi
launch_canonical_once
printf '%s\n' 'STATE SIGNED_APP_INSTALLED->EXTENSION_REGISTERED'
if [[ "$extension_changed" == true ]]; then
    inventory_state="safariRestartRequired"
    inventory_refresh_required=true
else
    inventory_state="inventoryCurrent"
    inventory_refresh_required=false
fi
write_inventory_receipt "$inventory_state" false
printf 'TEST_APP_INSTALLED build_artifact=%s active_install=%s app_version=%s extension_version=%s app_build=%s extension_build=%s team=%s extension_id=%s extension_hash=%s extension_cdhash=%s update=true inventory_refresh_required=%s receipt=%s\n' \
    "$canonical_artifact" "$CANONICAL_INSTALL_PATH" "$expected_version" "$expected_extension_version" "$expected_app_build" \
    "$expected_extension_build" "$EXPECTED_TEAM" "$EXTENSION_ID" \
    "$artifact_extension_hash" "$artifact_extension_cdhash" "$inventory_refresh_required" \
    "$INVENTORY_RECEIPT"
