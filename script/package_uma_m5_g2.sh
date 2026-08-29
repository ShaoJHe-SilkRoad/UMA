#!/usr/bin/env bash
# Builds and audits the M5 Browser Sync preflight or commit-exact package.
set -euo pipefail
umask 077

package_root=""
output_parent=""
completed=0
cleanup() {
    if [[ -n "$package_root" && -d "$package_root" ]]; then
        rm -rf -- "$package_root"
    fi
    if [[ "$completed" != 1 && -n "$output_parent" && -d "$output_parent" ]]; then
        rm -rf -- "$output_parent"
    fi
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM

readonly REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
readonly PRODUCT="CodexUsageMonitor"
readonly NATIVE_HOST="ClaudeBrowserNativeHost"
readonly STATUS_RELAY="ClaudeStatusLineRelay"
readonly SAFARI_EXTENSION="ClaudeBrowserCompanion"
readonly MARKETING_VERSION="0.11"
BUNDLE_ID="com.silkrd.uma"
SAFARI_EXTENSION_ID="$BUNDLE_ID.ClaudeBrowserCompanion"
NATIVE_HOST_ID="$BUNDLE_ID.ClaudeBrowserNativeHost"
STATUS_RELAY_ID="$BUNDLE_ID.ClaudeStatusLineRelay"
CHROMIUM_HOST_NAME="com.silkrd.uma.claude_browser"
runtime_generation_id=""
readonly DEFAULT_BUILD="202608010001"
readonly DEFAULT_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
readonly APPLE_DEVELOPMENT_DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer"
readonly user_home="$HOME"
# Delivery artifacts live directly on the mounted external APFS development
# volume. Internal compatibility paths are never resolved or accepted as the
# canonical package boundary. Only scratch build data remains under /private/tmp.
readonly DELIVERY_VOLUME="/Volumes/HE/DEV"
readonly DELIVERY_BASE="$DELIVERY_VOLUME/UMA"
readonly DELIVERY_ROOT="$DELIVERY_BASE/Packages"

# The immutable-host architecture deliberately bypasses the historical
# combined-app packager. The dedicated packager never creates Contents/PlugIns
# and never executes Safari registration logic.
for ((argument_index = 1; argument_index <= $#; argument_index += 1)); do
    if [[ "${!argument_index}" == --packaging-mode ]]; then
        value_index=$((argument_index + 1))
        if (( value_index <= $# )) && [[ "${!value_index}" == UMA_APP_ONLY ]]; then
            exec "$REPO_ROOT/script/package_uma_app_only_test.sh" "$@"
        fi
    fi
done

usage() {
    printf '%s\n' \
        "Usage: $0 --commit <40-hex-sha> [--build <12-digit-number>] --phase <m5-browser-preflight|m5-browser-final|m5adbg-preflight|m5adbg-final|m5-auto-preflight|m5-auto-final|m5-slr-final|m5rmx-safari-preflight|m5rmx-smart-preflight|m5rmx-smart-live-link-preflight|m5rmx-smart-0.13-preflight|apple-development-test> --output <exact-path>" \
        "  apple-development-test additionally requires:" \
        "    --packaging-mode <UMA_APP_ONLY|APP_ONLY|COMPANION_MIGRATION>" \
        "    UMA_APP_ONLY: --immutable-safari-host <exact.app> --immutable-host-receipt <receipt.plist>" \
        "    APP_ONLY: --frozen-companion <exact.appex> --frozen-companion-receipt <receipt.plist>" \
        "Packages are delivered under $DELIVERY_ROOT and are not purged with /private/tmp." \
        "" \
        "Signing and notarization:" \
        "  --signing-identity <name>   Developer ID Application or Apple Development identity." \
        "                              apple-development-test requires the exact Founder identity." \
        "                              The default '-'," \
        "                              is allowed only for m5rmx-smart-0.13-preflight," \
        "                              is ad-hoc development signing, and cannot be notarized. A real" \
        "                              identity also enables the hardened runtime and a" \
        "                              secure timestamp, which notarization requires." \
        "  --keychain-profile <name>   notarytool profile created once with" \
        "                              'xcrun notarytool store-credentials'. Submits, waits," \
        "                              staples, and assesses. Requires --signing-identity."
}

mint_runtime_generation_id() {
    /usr/bin/uuidgen | /usr/bin/tr '[:upper:]' '[:lower:]'
}

commit=""
build_number="$DEFAULT_BUILD"
build_supplied=0
phase=""
output=""
# Ad-hoc remains the command-line default only for the explicitly gated 0.13
# development preflight. Every historical, final, and signed phase rejects it.
# A real Developer ID identity additionally enables the hardened runtime and a
# secure timestamp, both of which notarization requires.
signing_identity="-"
notary_profile=""
print_runtime_generation=0
packaging_mode=""
frozen_companion=""
frozen_companion_receipt=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --commit) commit="${2:-}"; shift 2 ;;
        --build) build_number="${2:-}"; build_supplied=1; shift 2 ;;
        --phase) phase="${2:-}"; shift 2 ;;
        --output) output="${2:-}"; shift 2 ;;
        --signing-identity) signing_identity="${2:-}"; shift 2 ;;
        --keychain-profile) notary_profile="${2:-}"; shift 2 ;;
        --print-runtime-generation) print_runtime_generation=1; shift ;;
        --packaging-mode) packaging_mode="${2:-}"; shift 2 ;;
        --frozen-companion) frozen_companion="${2:-}"; shift 2 ;;
        --frozen-companion-receipt) frozen_companion_receipt="${2:-}"; shift 2 ;;
        *) usage >&2; exit 2 ;;
    esac
done
readonly signing_identity notary_profile
if [[ "$print_runtime_generation" == 1 ]]; then
    [[ -z "$commit" && -z "$phase" && -z "$output" && "$build_supplied" == 0 \
        && "$signing_identity" == "-" && -z "$notary_profile" ]] || {
        usage >&2
        exit 2
    }
    mint_runtime_generation_id
    exit 0
fi
[[ -n "$signing_identity" ]] || { usage >&2; exit 2; }
if [[ -n "$notary_profile" && "$signing_identity" == "-" ]]; then
    printf '%s\n' \
        "Notarization requires --signing-identity with a Developer ID Application certificate." >&2
    exit 2
fi

signing_kind="developer-id"
if [[ "$phase" == "apple-development-test" ]]; then
    signing_kind="apple-development"
elif [[ "$signing_identity" == "-" ]]; then
    signing_kind="ad-hoc"
fi
codesign_options=(--force --sign "$signing_identity")
if [[ "$signing_kind" == "developer-id" ]]; then
    codesign_options+=(--options runtime --timestamp)
elif [[ "$signing_kind" == "apple-development" ]]; then
    codesign_options+=(--timestamp=none)
fi
readonly codesign_options signing_kind

[[ "$commit" =~ ^[0-9a-f]{40}$ ]] || { usage >&2; exit 2; }
[[ "$build_number" =~ ^[0-9]{12}$ ]] || { usage >&2; exit 2; }
resolved_marketing_version="$MARKETING_VERSION"
claude_source="Safari Browser Sync"
signing_provenance="Developer ID Application"
notarization_eligible="true"
case "$phase" in
    m5-browser-preflight)
        expected_output="$DELIVERY_ROOT/uma-m5-browser-preflight-${commit:0:12}/UMA.app"
        source_state="working-tree-preflight"
        integration_status="BROWSER-SYNC-LIVE-PREFLIGHT"
        commit_exact=0
        ;;
    m5-browser-final)
        expected_output="$DELIVERY_ROOT/uma-m5-browser-final-$commit/UMA.app"
        source_state="commit-exact"
        integration_status="SYSTEM-BROWSER-USAGE-SYNC-ACCEPTED"
        commit_exact=1
        ;;
    m5adbg-preflight)
        expected_output="$DELIVERY_ROOT/uma-m5adbg-preflight-${commit:0:12}/UMA.app"
        source_state="working-tree-m5adbg-preflight"
        integration_status="BROWSER-SYNC-DEFECT-CLOSURE-PREFLIGHT"
        commit_exact=0
        ;;
    m5adbg-final)
        expected_output="$DELIVERY_ROOT/uma-m5adbg-final-$commit/UMA.app"
        source_state="commit-exact"
        integration_status="BROWSER-SYNC-DEFECT-CLOSURE-PASS"
        commit_exact=1
        ;;
    m5-auto-preflight)
        expected_output="$DELIVERY_ROOT/uma-m5-auto-preflight-${commit:0:12}/UMA.app"
        source_state="working-tree-m5-auto-preflight"
        integration_status="AUTOMATIC-BROWSER-SYNC-LIVE-PREFLIGHT"
        commit_exact=0
        ;;
    m5-auto-final)
        expected_output="$DELIVERY_ROOT/uma-m5-auto-final-$commit/UMA.app"
        source_state="commit-exact"
        integration_status="AUTOMATIC-BROWSER-SYNC-ACCEPTED"
        commit_exact=1
        ;;
    m5-slr-final)
        expected_output="$DELIVERY_ROOT/uma-m5-slr-final-$commit/UMA.app"
        source_state="commit-exact"
        integration_status="AUTOMATIC-BROWSER-SYNC-ACCEPTED-STATUS-LINE-REMOVED"
        commit_exact=1
        ;;
    m5rmx-safari-preflight)
        expected_output="$DELIVERY_ROOT/uma-m5rmx-safari-preflight-$commit/UMA.app"
        source_state="commit-exact-signed-preflight"
        integration_status="SIGNED-SAFARI-EXTENSION-PREFLIGHT"
        commit_exact=1
        resolved_marketing_version="0.12"
        notarization_eligible="false"
        [[ "$signing_identity" != "-" ]] || {
            printf '%s\n' "M5RMX Safari preflight requires a Developer ID Application identity." >&2
            exit 2
        }
        [[ -z "$notary_profile" ]] || {
            printf '%s\n' "M5RMX Safari preflight does not submit for notarization." >&2
            exit 2
        }
        ;;
    m5rmx-smart-preflight)
        expected_output="$DELIVERY_ROOT/uma-m5rmx-smart-preflight-${commit:0:12}/UMA.app"
        source_state="working-tree-smart-preflight"
        integration_status="LOCAL-SMART-LIVE-PREFLIGHT"
        commit_exact=0
        resolved_marketing_version="0.12"
        claude_source="Local Smart Mode with on-demand Accuracy Sync"
        notarization_eligible="false"
        [[ "$signing_identity" != "-" ]] || {
            printf '%s\n' "M5RMX Smart preflight requires a Developer ID Application identity." >&2
            exit 2
        }
        [[ -z "$notary_profile" ]] || {
            printf '%s\n' "M5RMX Smart preflight does not submit for notarization." >&2
            exit 2
        }
        ;;
    m5rmx-smart-live-link-preflight)
        [[ "$build_supplied" == 1 ]] || {
            printf '%s\n' "M5RMX Smart live-link preflight requires an explicit 12-digit build." >&2
            exit 2
        }
        expected_output="$DELIVERY_ROOT/uma-m5rmx-smart-live-link-preflight-${commit:0:12}-$build_number/UMA.app"
        source_state="working-tree-smart-live-link-preflight"
        integration_status="LOCAL-SMART-LIVE-LINK-PREFLIGHT"
        commit_exact=0
        resolved_marketing_version="0.12"
        claude_source="Local Smart Mode with on-demand Accuracy Sync"
        notarization_eligible="false"
        [[ "$signing_identity" != "-" ]] || {
            printf '%s\n' "M5RMX Smart live-link preflight requires a Developer ID Application identity." >&2
            exit 2
        }
        [[ -z "$notary_profile" ]] || {
            printf '%s\n' "M5RMX Smart live-link preflight does not submit for notarization." >&2
            exit 2
        }
        ;;
    m5rmx-smart-0.13-preflight)
        [[ "$build_supplied" == 1 ]] || {
            printf '%s\n' "M5RMX Smart 0.13 preflight requires an explicit 12-digit build." >&2
            exit 2
        }
        expected_output="$DELIVERY_ROOT/uma-0.13-dev-${commit:0:12}-$build_number/UMA_0.13.0.app"
        source_state="working-tree-smart-0.13-preflight"
        integration_status="UMA-0.13-SINGLE-ACTIVE-LOCAL-SMART-PREFLIGHT"
        commit_exact=0
        resolved_marketing_version="0.13.0"
        claude_source="Local Smart Mode with on-demand Accuracy Sync"
        notarization_eligible="false"
        if [[ "$signing_identity" == "-" ]]; then
            signing_provenance="AD-HOC UNSIGNED DEVELOPMENT"
        fi
        [[ -z "$notary_profile" ]] || {
            printf '%s\n' "M5RMX Smart 0.13 preflight does not submit for notarization." >&2
            exit 2
        }
        ;;
    apple-development-test)
        [[ "$build_supplied" == 1 ]] || {
            printf '%s\n' "Apple Development test mode requires an explicit 12-digit build." >&2
            exit 2
        }
        expected_output="$DELIVERY_ROOT/uma-0.13-apple-dev-test-${commit:0:12}-$build_number/UMA_0.13.0-Test.zip"
        source_state="working-tree-apple-development-test"
        integration_status="UMA-0.13-APPLE-DEVELOPMENT-SIGNED-TEST-CHANNEL"
        commit_exact=0
        resolved_marketing_version="0.13.0"
        claude_source="Local Smart Mode with on-demand Accuracy Sync"
        signing_provenance="Apple Development via Xcode automatic signing"
        notarization_eligible="false"
        BUNDLE_ID="com.silkrd.uma.test"
        SAFARI_EXTENSION_ID="$BUNDLE_ID.ClaudeBrowserCompanion"
        NATIVE_HOST_ID="$BUNDLE_ID.ClaudeBrowserNativeHost"
        STATUS_RELAY_ID="$BUNDLE_ID.ClaudeStatusLineRelay"
        [[ "$signing_identity" == "Apple Development: SHAOTING HE (5BN4FAQSUF)" ]] || {
            printf '%s\n' "Apple Development test mode requires the exact Founder identity." >&2
            exit 2
        }
        [[ -z "$notary_profile" ]] || {
            printf '%s\n' "Apple Development test mode never submits for notarization." >&2
            exit 2
        }
        [[ "$packaging_mode" == APP_ONLY || "$packaging_mode" == COMPANION_MIGRATION ]] || {
            printf '%s\n' "Apple Development test mode requires explicit APP_ONLY or COMPANION_MIGRATION." >&2
            exit 2
        }
        if [[ "$packaging_mode" == APP_ONLY ]]; then
            [[ "$frozen_companion" == /* && "$frozen_companion_receipt" == /* ]] || {
                printf '%s\n' "APP_ONLY requires exact absolute frozen Companion and receipt paths." >&2
                exit 2
            }
        elif [[ -n "$frozen_companion" || -n "$frozen_companion_receipt" ]]; then
            printf '%s\n' "COMPANION_MIGRATION must build the Companion from source, not a frozen input." >&2
            exit 2
        fi
        ;;
    *) usage >&2; exit 2 ;;
esac
app_package_generation_id="$(mint_runtime_generation_id)"
runtime_generation_id="$app_package_generation_id"
[[ "$app_package_generation_id" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] || {
    printf '%s\n' "Package runtime generation is invalid." >&2
    exit 1
}
if [[ "$phase" == "apple-development-test" ]]; then
    runtime_channel="test"
else
    runtime_channel="production"
fi
SDK="$DEFAULT_SDK"
swift_driver=(/usr/bin/xcrun swift)
appex_compiler="/Library/Developer/CommandLineTools/usr/bin/swiftc"
if [[ "$phase" == "apple-development-test" ]]; then
    export DEVELOPER_DIR="$APPLE_DEVELOPMENT_DEVELOPER_DIR"
    SDK="$APPLE_DEVELOPMENT_DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk"
    swift_driver=(/usr/bin/xcrun swift)
    appex_compiler="$APPLE_DEVELOPMENT_DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"
fi
readonly SDK appex_compiler
readonly -a swift_driver
[[ -d "$SDK" ]] || { printf 'Missing offline SDK: %s\n' "$SDK" >&2; exit 1; }
[[ -x "${swift_driver[0]}" && -x "$appex_compiler" ]] || {
    printf '%s\n' "Selected Swift toolchain is incomplete." >&2
    exit 1
}
if [[ "$signing_identity" == "-" && "$phase" != "m5rmx-smart-0.13-preflight" ]]; then
    printf '%s\n' \
        "Ad-hoc signing is allowed only for the M5RMX Smart 0.13 development preflight." >&2
    exit 2
fi
readonly expected_output source_state integration_status commit_exact resolved_marketing_version claude_source
readonly signing_provenance notarization_eligible
readonly BUNDLE_ID SAFARI_EXTENSION_ID NATIVE_HOST_ID STATUS_RELAY_ID CHROMIUM_HOST_NAME
readonly app_package_generation_id runtime_channel packaging_mode
[[ "$output" == "$expected_output" ]] || {
    printf 'Refusing output outside %s\n' "$expected_output" >&2
    exit 2
}
[[ ! -e "$output" && ! -L "$output" ]] || {
    printf 'Refusing to overwrite %s\n' "$output" >&2
    exit 2
}
output_parent="$(dirname "$output")"
[[ ! -e "$output_parent" && ! -L "$output_parent" ]] || {
    printf 'Refusing existing package parent %s\n' "$output_parent" >&2
    exit 2
}
[[ -d "$DELIVERY_VOLUME" && ! -L "$DELIVERY_VOLUME" ]] || {
    printf 'Required external delivery volume is unavailable: %s\n' \
        "$DELIVERY_VOLUME" >&2
    exit 2
}
/sbin/mount | /usr/bin/awk -v volume="$DELIVERY_VOLUME" '
    $2 == "on" && $3 == volume && $0 ~ /\(apfs,/ { found = 1 }
    END { exit(found ? 0 : 1) }
' || {
    printf 'Required external APFS volume is not mounted at %s\n' \
        "$DELIVERY_VOLUME" >&2
    exit 2
}
[[ -d "$DELIVERY_BASE" \
    && ! -L "$DELIVERY_BASE" \
    && -w "$DELIVERY_BASE" \
    && "$(/usr/bin/stat -f '%u' "$DELIVERY_BASE")" == "$(/usr/bin/id -u)" ]] || {
    printf 'Refusing unsafe or unwritable delivery base: %s\n' \
        "$DELIVERY_BASE" >&2
    exit 2
}
[[ ! -L "$DELIVERY_ROOT" ]] || {
    printf 'Refusing symlinked delivery root %s\n' "$DELIVERY_ROOT" >&2
    exit 2
}
mkdir -p "$DELIVERY_ROOT"
[[ -d "$DELIVERY_ROOT" \
    && ! -L "$DELIVERY_ROOT" \
    && -w "$DELIVERY_ROOT" \
    && "$(/usr/bin/stat -f '%u' "$DELIVERY_ROOT")" == "$(/usr/bin/id -u)" ]] || {
    printf 'Refusing unsafe or unwritable delivery root: %s\n' \
        "$DELIVERY_ROOT" >&2
    exit 2
}
readonly canonical_delivery_root="$(cd "$DELIVERY_ROOT" && pwd -P)"
readonly canonical_parent_base="$(cd "$(dirname "$output_parent")" && pwd -P)"
[[ "$canonical_parent_base" == "$canonical_delivery_root" ]] || {
    printf 'Refusing non-canonical package parent %s\n' "$canonical_parent_base" >&2
    exit 2
}

git -C "$REPO_ROOT" cat-file -e "$commit^{commit}"
[[ "$(git -C "$REPO_ROOT" rev-parse HEAD)" == "$commit" ]] || {
    printf '%s\n' "Requested commit is not the current repository HEAD." >&2
    exit 1
}
mkdir "$output_parent"
delivery_output="$output"

case "$phase" in
    m5adbg-*) package_root="/private/tmp/uma-m5adbg-package-$phase-$commit" ;;
    m5-auto-*) package_root="/private/tmp/uma-m5-auto-package-$phase-$commit" ;;
    m5-slr-*) package_root="/private/tmp/uma-m5-slr-package-$phase-$commit" ;;
    m5rmx-safari-*) package_root="/private/tmp/uma-m5rmx-safari-package-$phase-$commit" ;;
    m5rmx-smart-live-link-preflight|m5rmx-smart-0.13-preflight|apple-development-test)
        package_root="/private/tmp/uma-m5rmx-smart-package-$phase-$commit-$build_number"
        ;;
    m5rmx-smart-*) package_root="/private/tmp/uma-m5rmx-smart-package-$phase-$commit" ;;
    *) package_root="/private/tmp/uma-m5-browser-package-$phase-$commit" ;;
esac
[[ ! -e "$package_root" && ! -L "$package_root" ]] || {
    printf 'Refusing to reuse %s\n' "$package_root" >&2
    exit 2
}
readonly source_archive="$package_root/source-$commit.tar"
readonly scratch_root="$package_root/swift"
readonly home_root="$package_root/home"
readonly tmp_root="$package_root/tmp"
readonly cache_root="$package_root/cache"
readonly config_root="$package_root/config"
readonly security_root="$package_root/security"
mkdir -p \
    "$home_root" \
    "$tmp_root" \
    "$cache_root/clang" \
    "$cache_root/swiftpm" \
    "$config_root" \
    "$security_root"
if [[ "$phase" == "apple-development-test" ]]; then
    output="$package_root/UMA_0.13.0-Test.app"
fi

if [[ "$commit_exact" == 1 ]]; then
    source_root="$package_root/source"
    mkdir "$source_root"
    git -C "$REPO_ROOT" archive --format=tar --output="$source_archive" "$commit"
    tar -xf "$source_archive" -C "$source_root"
    archive_sha256="$(/usr/bin/shasum -a 256 "$source_archive" | /usr/bin/awk '{print $1}')"
else
    source_root="$REPO_ROOT"
    archive_sha256="WORKING-TREE-PREFLIGHT"
fi
readonly source_root archive_sha256
[[ -f "$source_root/Package.swift" \
    && -f "$source_root/Assets/AppIcon.icns" \
    && -f "$source_root/BrowserExtension/Safari/manifest.json" \
    && -f "$source_root/BrowserExtension/Chromium/manifest.json" ]] || {
    printf '%s\n' "Browser Sync source set is incomplete." >&2
    exit 1
}

readonly forbidden_runtime='ClaudeQuotaBroker|Claude Code-credentials|SecItem(Add|CopyMatching|Update|Delete)|/api/oauth/usage|Authorization: Bearer|accessToken|refreshToken|ANTHROPIC_API_KEY|CLAUDE_CODE_OAUTH_TOKEN|setup-token'
readonly forbidden_extension='"cookies"|<all_urls>|"tabs"|"webRequest"|"webNavigation"|"identity"|"history"|"bookmarks"|"downloads"|accounts\.google\.com'
readonly forbidden_payload='rawHTML|fullHTML|rawDOM|fullDOM|localStorage|sessionStorage|accountIdentity|account_identity|billing|payment|prompt|response|transcript|project|sourceCode|source_code'
if /usr/bin/grep -R -E -q "$forbidden_runtime" \
    "$source_root/Sources/CodexUsageMonitor" \
    "$source_root/Sources/CodexUsageUI" \
    "$source_root/Sources/ClaudeBrowserBridgeProtocol" \
    "$source_root/Sources/ClaudeBrowserNativeHost" \
    "$source_root/Sources/ClaudeBrowserNativeHostCore"; then
    printf '%s\n' "Production source retained a rejected credential or private-API route." >&2
    exit 1
fi
if /usr/bin/grep -R -E -i -q "$forbidden_extension" \
    "$source_root/BrowserExtension"; then
    printf '%s\n' "Browser Companion retained a forbidden browser permission or login route." >&2
    exit 1
fi
if /usr/bin/grep -R -E -q "$forbidden_payload" \
    "$source_root/Sources/ClaudeBrowserBridgeProtocol" \
    "$source_root/Sources/ClaudeBrowserNativeHost" \
    "$source_root/Sources/ClaudeBrowserNativeHostCore" \
    "$source_root/BrowserExtension"; then
    printf '%s\n' "Browser boundary retained a forbidden payload field." >&2
    exit 1
fi
readonly safari_manifest="$source_root/BrowserExtension/Safari/manifest.json"
readonly chromium_manifest="$source_root/BrowserExtension/Chromium/manifest.json"
readonly safari_info_plist="$source_root/BrowserExtension/Safari/Native/Info.plist"
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

source_extension_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$safari_info_plist")"
extension_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$safari_info_plist")"
frozen_extension_executable_sha256=""
frozen_extension_cdhash=""
frozen_extension_bundle_sha256=""
if [[ "$phase" == apple-development-test && "$packaging_mode" == APP_ONLY ]]; then
    [[ -d "$frozen_companion" && ! -L "$frozen_companion" \
        && -f "$frozen_companion_receipt" && ! -L "$frozen_companion_receipt" \
        && "$(/usr/bin/stat -f %u "$frozen_companion")" == "$(/usr/bin/id -u)" \
        && "$(/usr/bin/stat -f %u "$frozen_companion_receipt")" == "$(/usr/bin/id -u)" \
        && -z "$(/usr/bin/find "$frozen_companion" -type l -print -quit)" ]] || {
        printf '%s\n' 'UNINTENDED_COMPANION_MUTATION: unsafe frozen Companion boundary.' >&2
        exit 1
    }
    /usr/bin/plutil -lint "$frozen_companion_receipt" >/dev/null
    frozen_plist="$frozen_companion/Contents/Info.plist"
    extension_version="$(/usr/libexec/PlistBuddy -c 'Print :extensionVersion' "$frozen_companion_receipt")"
    source_extension_build="$(/usr/libexec/PlistBuddy -c 'Print :extensionBuild' "$frozen_companion_receipt")"
    runtime_generation_id="$(/usr/libexec/PlistBuddy -c 'Print :runtimeGenerationID' "$frozen_companion_receipt")"
    frozen_extension_executable_sha256="$(/usr/libexec/PlistBuddy -c 'Print :extensionExecutableSHA256' "$frozen_companion_receipt")"
    frozen_extension_cdhash="$(/usr/libexec/PlistBuddy -c 'Print :extensionCDHash' "$frozen_companion_receipt")"
    frozen_extension_bundle_sha256="$(/usr/libexec/PlistBuddy -c 'Print :extensionBundleSHA256' "$frozen_companion_receipt")"
    frozen_signing_report="$package_root/frozen-appex.signing"
    HOME="$user_home" /usr/bin/codesign --verify --strict --verbose=2 "$frozen_companion"
    HOME="$user_home" /usr/bin/codesign -d --verbose=4 "$frozen_companion" 2> "$frozen_signing_report"
    actual_frozen_cdhash="$(/usr/bin/awk -F= '/^CDHash=/{print $2; exit}' "$frozen_signing_report")"
    actual_frozen_executable_sha256="$(/usr/bin/shasum -a 256 "$frozen_companion/Contents/MacOS/$SAFARI_EXTENSION" | /usr/bin/awk '{print $1}')"
    actual_frozen_bundle_sha256="$(bundle_tree_sha256 "$frozen_companion")"
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :schemaVersion' "$frozen_companion_receipt")" == 3 \
        && "$(/usr/libexec/PlistBuddy -c 'Print :extensionBundleIdentifier' "$frozen_companion_receipt")" == "$SAFARI_EXTENSION_ID" \
        && "$(/usr/libexec/PlistBuddy -c 'Print :runtimeChannel' "$frozen_companion_receipt")" == test \
        && "$(/usr/libexec/PlistBuddy -c 'Print :teamIdentifier' "$frozen_companion_receipt")" == C6TUZVJ6SJ \
        && "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$frozen_plist")" == "$SAFARI_EXTENSION_ID" \
        && "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$frozen_plist")" == "$extension_version" \
        && "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$frozen_plist")" == "$source_extension_build" \
        && "$(/usr/libexec/PlistBuddy -c 'Print :UMARuntimeGenerationID' "$frozen_plist")" == "$runtime_generation_id" \
        && "$actual_frozen_executable_sha256" == "$frozen_extension_executable_sha256" \
        && "$actual_frozen_cdhash" == "$frozen_extension_cdhash" \
        && "$actual_frozen_bundle_sha256" == "$frozen_extension_bundle_sha256" ]] || {
        printf '%s\n' 'UNINTENDED_COMPANION_MUTATION: frozen Companion receipt mismatch.' >&2
        exit 1
    }
fi
[[ "$extension_version" =~ ^[0-9]+(\.[0-9]+)*$ && "$source_extension_build" =~ ^[0-9]+$ ]] || {
    printf '%s\n' "Safari companion source version/build is invalid." >&2
    exit 1
}
extension_build="$source_extension_build"
if [[ "$phase" == "apple-development-test" && "$packaging_mode" == COMPANION_MIGRATION ]]; then
    # Each changed signed Test Companion must be a real Safari update. Reusing
    # one CFBundleVersion for different signed bytes can make Safari disable the
    # replacement and force a repeated Human enablement loop.
    extension_build="$build_number"
fi
readonly extension_version source_extension_build extension_build
/usr/bin/grep -F -q '"manifest_version": 2' "$safari_manifest"
/usr/bin/grep -F -q '"permissions": ["nativeMessaging", "https://claude.ai/new*"]' "$safari_manifest"
/usr/bin/grep -F -q '"Shared/claude-usage-extractor.js"' "$safari_manifest"
/usr/bin/grep -F -q '"Shared/provider-ownership-v2.js"' "$safari_manifest"
/usr/bin/grep -F -q '"Shared/owned-provider-tab-v2-reducer.js"' "$safari_manifest"
/usr/bin/grep -F -q '"Shared/content-script.js"' "$safari_manifest"
/usr/bin/grep -F -q '"Safari/background-loader.js"' "$safari_manifest"
/usr/bin/grep -F -q '"Shared/background-core.js"' "$safari_manifest"
/usr/bin/grep -F -q '"content_scripts"' "$safari_manifest"
/usr/bin/grep -F -q '"run_at": "document_start"' "$safari_manifest"
/usr/bin/grep -F -q '"all_frames": false' "$safari_manifest"
/usr/bin/grep -F -q '"persistent": true' "$safari_manifest"
! /usr/bin/grep -F -q '"host_permissions"' "$safari_manifest"
! /usr/bin/grep -F -q '"service_worker"' "$safari_manifest"
! /usr/bin/grep -F -q '"activeTab"' "$safari_manifest"
/usr/bin/grep -F -q '"permissions": ["activeTab", "nativeMessaging", "scripting"]' "$chromium_manifest"
! /usr/bin/grep -F -q '"host_permissions"' "$chromium_manifest"
! /usr/bin/grep -F -q '"content_scripts"' "$chromium_manifest"
/usr/bin/grep -F -q 'href: "https://claude.ai/new#settings/usage"' \
    "$source_root/BrowserExtension/Shared/claude-usage-extractor.js"
! /usr/bin/grep -F -q 'tabs.onUpdated' \
    "$source_root/BrowserExtension/Shared/background-core.js"
/usr/bin/grep -F -q 'function observationEnvelope(requestID, observation)' \
    "$source_root/BrowserExtension/Shared/background-core.js"
/usr/bin/grep -F -q 'function runtimeQualificationRequest(requestID)' \
    "$source_root/BrowserExtension/Shared/background-core.js"
/usr/bin/grep -F -q 'void qualifyRuntime(command.requestID, portGeneration)' \
    "$source_root/BrowserExtension/Shared/background-core.js"
/usr/bin/grep -F -q 'The signed handler creates the reply from its own Bundle metadata.' \
    "$source_root/BrowserExtension/Shared/background-core.js"
/usr/bin/grep -F -q 'api.runtime.sendNativeMessage(config.nativeApplication, payload)' \
    "$source_root/BrowserExtension/Shared/background-core.js"
[[ "$(/usr/bin/grep -F -c 'api.runtime.connectNative(config.nativeApplication)' \
    "$source_root/BrowserExtension/Shared/background-core.js")" == 1 ]]
/usr/bin/grep -F -q 'config.browserFamily !== "safari"' \
    "$source_root/BrowserExtension/Shared/background-core.js"
/usr/bin/grep -F -q 'port.onMessage.addListener((message) =>' \
    "$source_root/BrowserExtension/Shared/background-core.js"
/usr/bin/grep -F -q 'port.onDisconnect.addListener(() =>' \
    "$source_root/BrowserExtension/Shared/background-core.js"
/usr/bin/grep -F -q 'containingAppPortGeneration !== generation' \
    "$source_root/BrowserExtension/Shared/background-core.js"
/usr/bin/grep -F -q 'claudeBrowserRuntimeQualificationAcknowledgement' \
    "$source_root/BrowserExtension/Shared/background-core.js"
! /usr/bin/grep -F -q 'runtime.connectNative' \
    "$source_root/BrowserExtension/Chromium/background-loader.js"
! /usr/bin/grep -F -q 'nativeReconnectTimer' \
    "$source_root/BrowserExtension/Shared/background-core.js"
if [[ "$phase" == "apple-development-test" ]]; then
    safari_entitlements="$source_root/AppleDevelopmentSigning/Extension/ClaudeBrowserCompanion.entitlements"
else
    safari_entitlements="$source_root/BrowserExtension/Safari/Native/ClaudeBrowserCompanion.entitlements"
fi
readonly safari_entitlements
/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' \
    "$safari_entitlements" \
    | /usr/bin/grep -Fx -q 'true'
if /usr/libexec/PlistBuddy -c 'Print :com.apple.security.network.client' \
    "$safari_entitlements" \
    >/dev/null 2>&1; then
    printf '%s\n' "Safari companion must not receive a network-client entitlement." >&2
    exit 1
fi
/usr/libexec/PlistBuddy -c \
    'Print :com.apple.security.temporary-exception.files.home-relative-path.read-write:0' \
    "$safari_entitlements" \
    | /usr/bin/grep -Fx -q \
        "$([[ "$phase" == "apple-development-test" ]] \
            && printf '%s' '/Library/Application Support/CodexUsageMonitor/TestChannel/ClaudeBrowserCompanion/' \
            || printf '%s' '/Library/Application Support/CodexUsageMonitor/ClaudeBrowserCompanion/')"

if [[ "$phase" == "apple-development-test" && "$packaging_mode" == COMPANION_MIGRATION ]]; then
    DEVELOPER_DIR="$APPLE_DEVELOPMENT_DEVELOPER_DIR" \
        "$source_root/script/verify_uma_apple_development_signing.sh" \
        --work-root "/private/tmp/uma-apple-development-signing-$commit-$build_number"
fi

export HOME="$home_root"
export TMPDIR="$tmp_root"
export SDKROOT="$SDK"
export CLANG_MODULE_CACHE_PATH="$cache_root/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$cache_root/swiftpm"
readonly swift_options=(
    --disable-sandbox
    --disable-keychain
    --disable-netrc
    --manifest-cache local
    --sdk "$SDK"
    --scratch-path "$scratch_root"
    --cache-path "$cache_root/swiftpm"
    --config-path "$config_root"
    --security-path "$security_root"
    -Xswiftc -sdk -Xswiftc "$SDK"
    -Xswiftc -Xfrontend -Xswiftc -experimental-allow-module-with-compiler-errors
)

pushd "$source_root" >/dev/null
"${swift_driver[@]}" build "${swift_options[@]}" -c release --product "$PRODUCT"
"${swift_driver[@]}" build "${swift_options[@]}" -c release --product "$NATIVE_HOST"
"${swift_driver[@]}" build "${swift_options[@]}" -c release --product "$STATUS_RELAY"
readonly bin_path="$(
    "${swift_driver[@]}" build "${swift_options[@]}" -c release --show-bin-path
)"
popd >/dev/null
readonly binary_path="$bin_path/$PRODUCT"
readonly native_host_path="$bin_path/$NATIVE_HOST"
readonly status_relay_path="$bin_path/$STATUS_RELAY"
[[ -x "$binary_path" && -x "$native_host_path" && -x "$status_relay_path" ]] || {
    printf '%s\n' "Expected release executables are missing." >&2
    exit 1
}

readonly appex_binary="$package_root/$SAFARI_EXTENSION"
if [[ "$packaging_mode" != APP_ONLY ]]; then
    "$appex_compiler" \
        -sdk "$SDK" \
        -target arm64-apple-macosx14.0 \
        -application-extension \
        -Xlinker -application_extension \
        -Xfrontend -experimental-allow-module-with-compiler-errors \
        -O \
        -parse-as-library \
        -module-name "$SAFARI_EXTENSION" \
        -I "$bin_path" \
        "$source_root/BrowserExtension/Safari/Native/SafariWebExtensionHandler.swift" \
        "$bin_path/ClaudeBrowserBridgeProtocol.o" \
        "$bin_path/ClaudeBrowserNativeHostCore.o" \
        -framework Foundation \
        -framework SafariServices \
        -Xlinker -e \
        -Xlinker _NSExtensionMain \
        -o "$appex_binary"
fi

readonly contents="$output/Contents"
readonly appex="$contents/PlugIns/$SAFARI_EXTENSION.appex"
readonly appex_contents="$appex/Contents"
readonly chromium_root="$contents/Resources/BrowserCompanion/Chromium"
readonly chromium_host_root="$contents/Resources/BrowserCompanion/ChromiumNativeHost"
mkdir -p \
    "$contents/MacOS" \
    "$contents/Helpers" \
    "$contents/Resources" \
    "$contents/PlugIns"
if [[ "$packaging_mode" == APP_ONLY ]]; then
    # The frozen Companion is copied as one opaque signed bundle. Nothing below
    # may rewrite its plist, resources, executable, or nested signature.
    /usr/bin/ditto "$frozen_companion" "$appex"
else
    mkdir -p \
        "$appex_contents/MacOS" \
        "$appex_contents/Resources/Shared" \
        "$appex_contents/Resources/Safari"
fi
if [[ "$phase" != "apple-development-test" ]]; then
    mkdir -p \
        "$chromium_root/Shared" \
        "$chromium_root/Chromium" \
        "$chromium_host_root"
fi
install -m 755 "$binary_path" "$contents/MacOS/$PRODUCT"
install -m 755 "$native_host_path" "$contents/Helpers/$NATIVE_HOST"
install -m 755 "$status_relay_path" "$contents/Helpers/$STATUS_RELAY"
if [[ "$packaging_mode" != APP_ONLY ]]; then
    install -m 755 "$appex_binary" "$appex_contents/MacOS/$SAFARI_EXTENSION"
fi
install -m 644 "$source_root/Assets/AppIcon.icns" "$contents/Resources/AppIcon.icns"
if [[ "$packaging_mode" != APP_ONLY ]]; then
    install -m 644 "$source_root/BrowserExtension/Safari/Native/Info.plist" "$appex_contents/Info.plist"
    install -m 644 "$source_root/BrowserExtension/Safari/manifest.json" "$appex_contents/Resources/manifest.json"
    install -m 644 "$source_root/BrowserExtension/Safari/background-loader.js" "$appex_contents/Resources/Safari/background-loader.js"
    install -m 644 "$source_root/BrowserExtension/Shared/claude-usage-extractor.js" "$appex_contents/Resources/Shared/claude-usage-extractor.js"
    install -m 644 "$source_root/BrowserExtension/Shared/content-script.js" "$appex_contents/Resources/Shared/content-script.js"
    install -m 644 "$source_root/BrowserExtension/Shared/background-core.js" "$appex_contents/Resources/Shared/background-core.js"
    install -m 644 "$source_root/BrowserExtension/Shared/provider-ownership-v2.js" "$appex_contents/Resources/Shared/provider-ownership-v2.js"
    install -m 644 "$source_root/BrowserExtension/Shared/owned-provider-tab-v2-reducer.js" "$appex_contents/Resources/Shared/owned-provider-tab-v2-reducer.js"
fi
if [[ "$phase" != "apple-development-test" ]]; then
    install -m 644 "$source_root/BrowserExtension/Chromium/manifest.json" "$chromium_root/manifest.json"
    install -m 644 "$source_root/BrowserExtension/Chromium/background-loader.js" "$chromium_root/Chromium/background-loader.js"
    install -m 644 "$source_root/BrowserExtension/Shared/claude-usage-extractor.js" "$chromium_root/Shared/claude-usage-extractor.js"
    install -m 644 "$source_root/BrowserExtension/Shared/content-script.js" "$chromium_root/Shared/content-script.js"
    install -m 644 "$source_root/BrowserExtension/Shared/background-core.js" "$chromium_root/Shared/background-core.js"
    install -m 644 "$source_root/BrowserExtension/Shared/provider-ownership-v2.js" "$chromium_root/Shared/provider-ownership-v2.js"
    install -m 644 "$source_root/BrowserExtension/Shared/owned-provider-tab-v2-reducer.js" "$chromium_root/Shared/owned-provider-tab-v2-reducer.js"
    /usr/bin/sed \
        "s#__UMA_CLAUDE_BROWSER_NATIVE_HOST_PATH__#$contents/Helpers/$NATIVE_HOST#" \
        "$source_root/BrowserExtension/Chromium/$CHROMIUM_HOST_NAME.json" \
        > "$chromium_host_root/$CHROMIUM_HOST_NAME.json"
    chmod 644 "$chromium_host_root/$CHROMIUM_HOST_NAME.json"
fi

replace_plist_string() {
    local plist="$1"
    local key="$2"
    local value="$3"
    /usr/libexec/PlistBuddy -c "Delete :$key" "$plist" >/dev/null 2>&1 || true
    /usr/libexec/PlistBuddy -c "Add :$key string $value" "$plist"
}

if [[ "$packaging_mode" != APP_ONLY ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $SAFARI_EXTENSION_ID" \
        "$appex_contents/Info.plist"
fi
if [[ "$phase" == "apple-development-test" && "$packaging_mode" == COMPANION_MIGRATION ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $extension_build" \
        "$appex_contents/Info.plist"
fi
if [[ "$packaging_mode" != APP_ONLY ]]; then
for metadata in \
    "UMAContainingApplicationIdentifier=$BUNDLE_ID" \
    "UMAExtensionBundleIdentifier=$SAFARI_EXTENSION_ID" \
    "UMARuntimeChannel=$runtime_channel" \
    "UMATeamIdentifier=C6TUZVJ6SJ" \
    "UMARuntimeGenerationID=$runtime_generation_id" \
    "UMAAppVersion=$resolved_marketing_version" \
    "UMAAppBuild=$build_number" \
    "UMAExtensionVersion=$extension_version" \
    "UMAExtensionBuild=$extension_build"; do
    replace_plist_string \
        "$appex_contents/Info.plist" "${metadata%%=*}" "${metadata#*=}"
done
fi

if [[ "$phase" == "apple-development-test" && "$packaging_mode" == COMPANION_MIGRATION ]]; then
    replace_plist_string \
        "$appex_contents/Info.plist" UMATestRuntimeGenerationID "$runtime_generation_id"
fi

if [[ "$packaging_mode" != APP_ONLY ]]; then
cat > "$appex_contents/Resources/Safari/background-loader.js" <<LOADER
globalThis.UMA_BROWSER_CONFIG = Object.freeze({
  browserFamily: "safari",
  nativeApplication: "$BUNDLE_ID",
  supportsAutomaticRefresh: true,
  supportsManualAction: false,
  exactHostPermission: "https://claude.ai/new*",
  wakeMessageName: "umaClaudeWakeBridge",
  automaticRefreshMessageName: "umaClaudeAutomaticRefresh",
  closeOwnedTabMessageName: "umaClaudeCloseOwnedUsageTab",
  companionVersion: "$extension_version",
  companionBuild: "$extension_build",
  protocolSchemaVersion: 2,
  containingApplicationIdentifier: "$BUNDLE_ID",
  extensionBundleIdentifier: "$SAFARI_EXTENSION_ID",
  teamIdentifier: "C6TUZVJ6SJ",
  runtimeGenerationID: "$runtime_generation_id",
});
LOADER
chmod 644 "$appex_contents/Resources/Safari/background-loader.js"
/usr/bin/grep -F -q "nativeApplication: \"$BUNDLE_ID\"" \
    "$appex_contents/Resources/Safari/background-loader.js"
/usr/bin/grep -F -q "companionVersion: \"$extension_version\"" \
    "$appex_contents/Resources/Safari/background-loader.js"
/usr/bin/grep -F -q "companionBuild: \"$extension_build\"" \
    "$appex_contents/Resources/Safari/background-loader.js"
/usr/bin/grep -F -q 'protocolSchemaVersion: 2' \
    "$appex_contents/Resources/Safari/background-loader.js"
/usr/bin/grep -F -q "containingApplicationIdentifier: \"$BUNDLE_ID\"" \
    "$appex_contents/Resources/Safari/background-loader.js"
/usr/bin/grep -F -q "extensionBundleIdentifier: \"$SAFARI_EXTENSION_ID\"" \
    "$appex_contents/Resources/Safari/background-loader.js"
/usr/bin/grep -F -q 'teamIdentifier: "C6TUZVJ6SJ"' \
    "$appex_contents/Resources/Safari/background-loader.js"
/usr/bin/grep -F -q "runtimeGenerationID: \"$runtime_generation_id\"" \
    "$appex_contents/Resources/Safari/background-loader.js"
fi

cat > "$contents/Resources/UMA-M5-BROWSER-Provenance.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Revision</key><string>$commit</string>
<key>SourceArchiveSHA256</key><string>$archive_sha256</string>
<key>SourceState</key><string>$source_state</string>
<key>ClaudeIntegrationStatus</key><string>$integration_status</string>
<key>ClaudeSource</key><string>$claude_source</string>
<key>SigningProvenance</key><string>$signing_provenance</string>
<key>NotarizationEligible</key><$notarization_eligible/>
</dict></plist>
PLIST
chmod 644 "$contents/Resources/UMA-M5-BROWSER-Provenance.plist"

cat > "$contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDisplayName</key><string>UMA</string>
<key>CFBundleExecutable</key><string>$PRODUCT</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
<key>CFBundleName</key><string>UMA</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$resolved_marketing_version</string>
<key>CFBundleVersion</key><string>$build_number</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>UMAReviewCommit</key><string>$commit</string>
<key>UMASourceArchiveSHA256</key><string>$archive_sha256</string>
<key>UMASourceState</key><string>$source_state</string>
<key>UMARuntimeChannel</key><string>$runtime_channel</string>
<key>UMAContainingApplicationIdentifier</key><string>$BUNDLE_ID</string>
<key>UMAExtensionBundleIdentifier</key><string>$SAFARI_EXTENSION_ID</string>
<key>UMATeamIdentifier</key><string>C6TUZVJ6SJ</string>
<key>UMARuntimeGenerationID</key><string>$runtime_generation_id</string>
<key>UMAAppPackageGenerationID</key><string>$app_package_generation_id</string>
<key>UMAPackagingMode</key><string>${packaging_mode:-COMPANION_MIGRATION}</string>
<key>UMAAppVersion</key><string>$resolved_marketing_version</string>
<key>UMAAppBuild</key><string>$build_number</string>
<key>UMAExtensionVersion</key><string>$extension_version</string>
<key>UMAExtensionBuild</key><string>$extension_build</string>
</dict></plist>
PLIST
chmod 644 "$contents/Info.plist"
if [[ "$phase" == "apple-development-test" ]]; then
    replace_plist_string \
        "$contents/Info.plist" UMATestRuntimeGenerationID "$runtime_generation_id"
fi

verify_packaged_runtime_metadata() {
    local app_plist="$contents/Info.plist"
    local extension_plist="$appex_contents/Info.plist"
    local plist
    for plist in "$app_plist" "$extension_plist"; do
        [[ "$(/usr/libexec/PlistBuddy -c 'Print :UMAContainingApplicationIdentifier' "$plist")" == "$BUNDLE_ID" \
            && "$(/usr/libexec/PlistBuddy -c 'Print :UMAExtensionBundleIdentifier' "$plist")" == "$SAFARI_EXTENSION_ID" \
            && "$(/usr/libexec/PlistBuddy -c 'Print :UMARuntimeChannel' "$plist")" == "$runtime_channel" \
            && "$(/usr/libexec/PlistBuddy -c 'Print :UMATeamIdentifier' "$plist")" == C6TUZVJ6SJ \
            && "$(/usr/libexec/PlistBuddy -c 'Print :UMARuntimeGenerationID' "$plist")" == "$runtime_generation_id" \
            && "$(/usr/libexec/PlistBuddy -c 'Print :UMAExtensionVersion' "$plist")" == "$extension_version" \
            && "$(/usr/libexec/PlistBuddy -c 'Print :UMAExtensionBuild' "$plist")" == "$extension_build" ]] || {
            printf 'Package runtime metadata mismatch: %s\n' "$plist" >&2
            return 1
        }
    done
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :UMAAppVersion' "$app_plist")" == "$resolved_marketing_version" \
        && "$(/usr/libexec/PlistBuddy -c 'Print :UMAAppBuild' "$app_plist")" == "$build_number" \
        && "$(/usr/libexec/PlistBuddy -c 'Print :UMAAppPackageGenerationID' "$app_plist")" == "$app_package_generation_id" ]] || {
        printf '%s\n' "Package app-generation metadata mismatch." >&2
        return 1
    }
    if [[ "$packaging_mode" != APP_ONLY ]]; then
        [[ "$(/usr/libexec/PlistBuddy -c 'Print :UMAAppVersion' "$extension_plist")" == "$resolved_marketing_version" \
            && "$(/usr/libexec/PlistBuddy -c 'Print :UMAAppBuild' "$extension_plist")" == "$build_number" ]] || {
            printf '%s\n' "Companion migration app metadata mismatch." >&2
            return 1
        }
    fi
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_plist")" == "$BUNDLE_ID" \
        && "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_plist")" == "$resolved_marketing_version" \
        && "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app_plist")" == "$build_number" \
        && "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$extension_plist")" == "$SAFARI_EXTENSION_ID" \
        && "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$extension_plist")" == "$extension_version" \
        && "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$extension_plist")" == "$extension_build" ]] || {
        printf '%s\n' "Package bundle identity/version metadata mismatch." >&2
        return 1
    }
}
verify_packaged_runtime_metadata
if [[ "$packaging_mode" == APP_ONLY ]]; then
    [[ "$(bundle_tree_sha256 "$appex")" == "$frozen_extension_bundle_sha256" ]] || {
        printf '%s\n' 'UNINTENDED_COMPANION_MUTATION: packaged Companion differs from frozen receipt.' >&2
        exit 1
    }
fi

for plist in \
    "$contents/Info.plist" \
    "$contents/Resources/UMA-M5-BROWSER-Provenance.plist" \
    "$appex_contents/Info.plist"; do
    /usr/bin/plutil -lint "$plist" >/dev/null
done
/usr/bin/ruby -rjson -e 'JSON.parse(File.binread(ARGV.fetch(0)))' \
    "$appex_contents/Resources/manifest.json"
if [[ "$phase" != "apple-development-test" ]]; then
    for json in \
        "$chromium_root/manifest.json" \
        "$chromium_host_root/$CHROMIUM_HOST_NAME.json"; do
        /usr/bin/ruby -rjson -e 'JSON.parse(File.binread(ARGV.fetch(0)))' "$json"
    done
else
    [[ ! -e "$chromium_root" && ! -e "$chromium_host_root" ]] || {
        printf '%s\n' \
            "Apple Development Test package must be Safari-only; Chromium resources are forbidden." >&2
        exit 1
    }
fi

HOME="$user_home" /usr/bin/codesign "${codesign_options[@]}" \
    --identifier "$NATIVE_HOST_ID" \
    "$contents/Helpers/$NATIVE_HOST"
HOME="$user_home" /usr/bin/codesign "${codesign_options[@]}" \
    --identifier "$STATUS_RELAY_ID" \
    "$contents/Helpers/$STATUS_RELAY"
if [[ "$packaging_mode" != APP_ONLY ]]; then
    HOME="$user_home" /usr/bin/codesign "${codesign_options[@]}" \
        --identifier "$SAFARI_EXTENSION_ID" \
        --entitlements "$safari_entitlements" \
        "$appex"
else
    [[ "$(bundle_tree_sha256 "$appex")" == "$frozen_extension_bundle_sha256" ]] || {
        printf '%s\n' 'UNINTENDED_COMPANION_MUTATION: frozen Companion changed before app signing.' >&2
        exit 1
    }
fi
HOME="$user_home" /usr/bin/codesign \
    "${codesign_options[@]}" --identifier "$BUNDLE_ID" "$output"
HOME="$user_home" /usr/bin/codesign --verify --deep --strict --verbose=2 "$output"
if [[ "$packaging_mode" == APP_ONLY ]]; then
    [[ "$(bundle_tree_sha256 "$appex")" == "$frozen_extension_bundle_sha256" ]] || {
        printf '%s\n' 'UNINTENDED_COMPANION_MUTATION: app signing modified frozen Companion.' >&2
        exit 1
    }
fi

    if [[ "$phase" == "m5rmx-safari-preflight" \
        || "$phase" == "m5rmx-smart-preflight" \
        || "$phase" == "m5rmx-smart-live-link-preflight" \
        || "$phase" == "m5rmx-smart-0.13-preflight" \
        || "$phase" == "apple-development-test" ]]; then
    for signed_target in \
        "$contents/Helpers/$NATIVE_HOST" \
        "$contents/Helpers/$STATUS_RELAY" \
        "$appex" \
        "$output"; do
        case "$signed_target" in
            "$contents/Helpers/$NATIVE_HOST")
                expected_signed_identifier="$NATIVE_HOST_ID"
                ;;
            "$contents/Helpers/$STATUS_RELAY")
                expected_signed_identifier="$STATUS_RELAY_ID"
                ;;
            "$appex") expected_signed_identifier="$SAFARI_EXTENSION_ID" ;;
            "$output") expected_signed_identifier="$BUNDLE_ID" ;;
            *)
                printf 'Unknown signed component: %s\n' "$signed_target" >&2
                exit 1
                ;;
        esac
        signing_report="$package_root/$(basename "$signed_target")-signing.txt"
        HOME="$user_home" /usr/bin/codesign \
            -d --verbose=4 "$signed_target" 2> "$signing_report"
        /usr/bin/grep -Fx -q "Identifier=$expected_signed_identifier" \
            "$signing_report" || {
            printf 'Unexpected signed identifier: %s\n' "$signed_target" >&2
            exit 1
        }
        if [[ "$phase" == "m5rmx-smart-0.13-preflight" \
            && "$signing_identity" == "-" ]]; then
            /usr/bin/grep -q '^Signature=adhoc$' "$signing_report" || {
                printf 'Ad-hoc signature missing: %s\n' "$signed_target" >&2
                exit 1
            }
            continue
        fi
        /usr/bin/grep -q '^TeamIdentifier=C6TUZVJ6SJ$' "$signing_report" || {
            printf 'Unexpected signing Team ID: %s\n' "$signed_target" >&2
            exit 1
        }
        if [[ "$phase" == "apple-development-test" ]]; then
            /usr/bin/grep -Fx -q \
                'Authority=Apple Development: SHAOTING HE (5BN4FAQSUF)' \
                "$signing_report" || {
                printf 'Unexpected Apple Development authority: %s\n' "$signed_target" >&2
                exit 1
            }
            ! /usr/bin/grep -Fx -q 'Signature=adhoc' "$signing_report" || {
                printf 'Ad-hoc signature forbidden in Apple Development mode: %s\n' \
                    "$signed_target" >&2
                exit 1
            }
            continue
        fi
        /usr/bin/grep -q '^Runtime Version=' "$signing_report" || {
            printf 'Hardened Runtime missing: %s\n' "$signed_target" >&2
            exit 1
        }
        /usr/bin/grep -q '^Timestamp=' "$signing_report" || {
            printf 'Secure timestamp missing: %s\n' "$signed_target" >&2
            exit 1
        }
    done
fi

if [[ "$phase" == "apple-development-test" ]]; then
    app_entitlements="$package_root/app-entitlements.plist"
    appex_entitlements="$package_root/appex-entitlements.plist"
    HOME="$user_home" /usr/bin/codesign -d --entitlements :- \
        "$output" > "$app_entitlements" 2>/dev/null
    HOME="$user_home" /usr/bin/codesign -d --entitlements :- \
        "$appex" > "$appex_entitlements" 2>/dev/null
    if /usr/libexec/PlistBuddy -c 'Print :com.apple.security.get-task-allow' \
        "$app_entitlements" >/dev/null 2>&1 \
        || /usr/libexec/PlistBuddy -c 'Print :com.apple.security.get-task-allow' \
            "$appex_entitlements" >/dev/null 2>&1; then
        printf '%s\n' "Apple Development package unexpectedly received get-task-allow." >&2
        exit 1
    fi
    /usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' \
        "$appex_entitlements" | /usr/bin/grep -Fx -q true
    /usr/libexec/PlistBuddy -c \
        'Print :com.apple.security.temporary-exception.files.home-relative-path.read-write:0' \
        "$appex_entitlements" | /usr/bin/grep -Fx -q \
            '/Library/Application Support/CodexUsageMonitor/TestChannel/ClaudeBrowserCompanion/'
fi

for executable in \
    "$contents/MacOS/$PRODUCT" \
    "$contents/Helpers/$NATIVE_HOST" \
    "$contents/Helpers/$STATUS_RELAY" \
    "$appex_contents/MacOS/$SAFARI_EXTENSION"; do
    [[ "$(/usr/bin/lipo -archs "$executable")" == "arm64" ]] || {
        printf 'Executable is not arm64-only: %s\n' "$executable" >&2
        exit 1
    }
    dependency_audit="$package_root/$(basename "$executable")-dependencies.txt"
    /usr/bin/otool -L "$executable" > "$dependency_audit"
    if /usr/bin/awk 'NR > 1 {print $1}' "$dependency_audit" \
        | /usr/bin/grep -Ev '^(/System/Library/|/usr/lib/)' \
        | /usr/bin/grep -q .; then
        printf 'Executable contains a non-system dependency: %s\n' "$executable" >&2
        exit 1
    fi
done

if /usr/bin/find "$output" -type l -print -quit | /usr/bin/grep -q .; then
    printf '%s\n' "Package contains a symbolic link." >&2
    exit 1
fi
if /usr/bin/find "$output" -type f \
    \( -iname '*.sqlite*' -o -iname '*.db' -o -iname '*.log' \
       -o -iname '*.png' -o -iname '*.jpg' -o -iname '*.md' \
       -o -iname '*.txt' -o -iname '*.sock' -o -iname '*backup*' \) \
    -print -quit | /usr/bin/grep -q .; then
    printf '%s\n' "Package contains a fixture, backup, socket, log, or evidence file." >&2
    exit 1
fi

expected_manifest_entries=(
        "Contents/Helpers/$NATIVE_HOST" \
        "Contents/Helpers/$STATUS_RELAY" \
        "Contents/Info.plist" \
        "Contents/MacOS/$PRODUCT" \
        "Contents/PlugIns/$SAFARI_EXTENSION.appex/Contents/Info.plist" \
        "Contents/PlugIns/$SAFARI_EXTENSION.appex/Contents/MacOS/$SAFARI_EXTENSION" \
        "Contents/PlugIns/$SAFARI_EXTENSION.appex/Contents/Resources/Safari/background-loader.js" \
        "Contents/PlugIns/$SAFARI_EXTENSION.appex/Contents/Resources/Shared/background-core.js" \
        "Contents/PlugIns/$SAFARI_EXTENSION.appex/Contents/Resources/Shared/claude-usage-extractor.js" \
        "Contents/PlugIns/$SAFARI_EXTENSION.appex/Contents/Resources/Shared/content-script.js" \
        "Contents/PlugIns/$SAFARI_EXTENSION.appex/Contents/Resources/Shared/provider-ownership-v2.js" \
        "Contents/PlugIns/$SAFARI_EXTENSION.appex/Contents/Resources/Shared/owned-provider-tab-v2-reducer.js" \
        "Contents/PlugIns/$SAFARI_EXTENSION.appex/Contents/Resources/manifest.json" \
        "Contents/PlugIns/$SAFARI_EXTENSION.appex/Contents/_CodeSignature/CodeResources" \
        "Contents/Resources/AppIcon.icns" \
        "Contents/Resources/UMA-M5-BROWSER-Provenance.plist" \
        "Contents/_CodeSignature/CodeResources"
)
if [[ "$phase" != "apple-development-test" ]]; then
    expected_manifest_entries+=(
        "Contents/Resources/BrowserCompanion/Chromium/Chromium/background-loader.js"
        "Contents/Resources/BrowserCompanion/Chromium/Shared/background-core.js"
        "Contents/Resources/BrowserCompanion/Chromium/Shared/claude-usage-extractor.js"
        "Contents/Resources/BrowserCompanion/Chromium/Shared/content-script.js"
        "Contents/Resources/BrowserCompanion/Chromium/Shared/provider-ownership-v2.js"
        "Contents/Resources/BrowserCompanion/Chromium/Shared/owned-provider-tab-v2-reducer.js"
        "Contents/Resources/BrowserCompanion/Chromium/manifest.json"
        "Contents/Resources/BrowserCompanion/ChromiumNativeHost/$CHROMIUM_HOST_NAME.json"
    )
fi
readonly expected_manifest="$(
    printf '%s\n' "${expected_manifest_entries[@]}" \
        | LC_ALL=C /usr/bin/sort
)"
readonly actual_manifest="$(
    /usr/bin/find "$output" -type f -print \
        | /usr/bin/sed "s#^$output/##" \
        | LC_ALL=C /usr/bin/sort
)"
[[ "$actual_manifest" == "$expected_manifest" ]] || {
    printf '%s\n' "Package file allowlist mismatch." >&2
    printf '%s\n' "$actual_manifest" >&2
    exit 1
}

for executable in \
    "$contents/MacOS/$PRODUCT" \
    "$contents/Helpers/$NATIVE_HOST" \
    "$contents/Helpers/$STATUS_RELAY" \
    "$appex_contents/MacOS/$SAFARI_EXTENSION"; do
    strings_file="$package_root/$(basename "$executable")-strings.txt"
    /usr/bin/strings -a "$executable" > "$strings_file"
    if /usr/bin/grep -E -q "$forbidden_runtime|BEGIN [A-Z ]*PRIVATE KEY" "$strings_file"; then
        printf 'Executable retained rejected or secret material: %s\n' "$executable" >&2
        exit 1
    fi
done

readonly executable_sha256="$(
    /usr/bin/shasum -a 256 "$contents/MacOS/$PRODUCT" | /usr/bin/awk '{print $1}'
)"
readonly native_host_sha256="$(
    /usr/bin/shasum -a 256 "$contents/Helpers/$NATIVE_HOST" | /usr/bin/awk '{print $1}'
)"
readonly status_relay_sha256="$(
    /usr/bin/shasum -a 256 "$contents/Helpers/$STATUS_RELAY" | /usr/bin/awk '{print $1}'
)"
readonly appex_sha256="$(
    /usr/bin/shasum -a 256 "$appex_contents/MacOS/$SAFARI_EXTENSION" | /usr/bin/awk '{print $1}'
)"
readonly extension_bundle_sha256="$(bundle_tree_sha256 "$appex")"
extension_signing_report="$package_root/final-appex.signing"
HOME="$user_home" /usr/bin/codesign -d --verbose=4 "$appex" 2> "$extension_signing_report"
readonly extension_cdhash="$(/usr/bin/awk -F= '/^CDHash=/{print $2; exit}' "$extension_signing_report")"
[[ -n "$extension_cdhash" ]] || {
    printf '%s\n' 'Signed Companion CDHash is unavailable.' >&2
    exit 1
}
if [[ "$packaging_mode" == APP_ONLY ]]; then
    [[ "$appex_sha256" == "$frozen_extension_executable_sha256" \
        && "$extension_cdhash" == "$frozen_extension_cdhash" \
        && "$extension_bundle_sha256" == "$frozen_extension_bundle_sha256" ]] || {
        printf '%s\n' 'FAIL PACKAGE — UNINTENDED_COMPANION_MUTATION: final Companion identity drift.' >&2
        exit 1
    }
fi
readonly manifest_sha256="$(
    (
        cd "$output"
        /usr/bin/find . -type f -print0 \
            | LC_ALL=C /usr/bin/sort -z \
            | /usr/bin/xargs -0 /usr/bin/shasum -a 256
    ) | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}'
)"

reported_output="$output"
delivery_archive_sha256="none"
if [[ "$phase" == "apple-development-test" ]]; then
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :UMATestRuntimeGenerationID' "$contents/Info.plist")" \
        == "$runtime_generation_id" ]]
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :UMATestRuntimeGenerationID' "$appex_contents/Info.plist")" \
        == "$runtime_generation_id" ]]
    /usr/bin/grep -F -q "runtimeGenerationID: \"$runtime_generation_id\"" \
        "$appex_contents/Resources/Safari/background-loader.js"
    /usr/bin/grep -F -q 'nativeApplication: "com.silkrd.uma.test"' \
        "$appex_contents/Resources/Safari/background-loader.js"

    /usr/bin/ditto -c -k --keepParent "$output" "$delivery_output"
    delivery_archive_sha256="$(/usr/bin/shasum -a 256 "$delivery_output" | /usr/bin/awk '{print $1}')"
    verify_root="$package_root/archive-verification"
    mkdir "$verify_root"
    /usr/bin/ditto -x -k "$delivery_output" "$verify_root"
    verified_app="$verify_root/UMA_0.13.0-Test.app"
    [[ -d "$verified_app" && ! -L "$verified_app" \
        && "$(/usr/bin/find "$verify_root" -mindepth 1 -maxdepth 1 -type d | /usr/bin/wc -l | /usr/bin/tr -d ' ')" == 1 \
        && -z "$(/usr/bin/find "$verified_app" -type l -print -quit)" ]]
    HOME="$user_home" /usr/bin/codesign --verify --deep --strict --verbose=2 "$verified_app"
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$verified_app/Contents/Info.plist")" \
        == "$BUNDLE_ID" ]]
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
        "$verified_app/Contents/PlugIns/$SAFARI_EXTENSION.appex/Contents/Info.plist")" \
        == "$SAFARI_EXTENSION_ID" ]]
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :UMATestRuntimeGenerationID' \
        "$verified_app/Contents/Info.plist")" == "$runtime_generation_id" ]]
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :UMATestRuntimeGenerationID' \
        "$verified_app/Contents/PlugIns/$SAFARI_EXTENSION.appex/Contents/Info.plist")" \
        == "$runtime_generation_id" ]]

    receipt="${delivery_output%.zip}.receipt.plist"
    /usr/bin/plutil -create xml1 "$receipt"
    /usr/bin/plutil -insert schemaVersion -integer 3 "$receipt"
    /usr/bin/plutil -insert archiveFilename -string "$(basename "$delivery_output")" "$receipt"
    /usr/bin/plutil -insert archiveSHA256 -string "$delivery_archive_sha256" "$receipt"
    /usr/bin/plutil -insert appBundleIdentifier -string "$BUNDLE_ID" "$receipt"
    /usr/bin/plutil -insert extensionBundleIdentifier -string "$SAFARI_EXTENSION_ID" "$receipt"
    /usr/bin/plutil -insert appVersion -string "$resolved_marketing_version" "$receipt"
    /usr/bin/plutil -insert appBuild -string "$build_number" "$receipt"
    /usr/bin/plutil -insert extensionVersion -string "$extension_version" "$receipt"
    /usr/bin/plutil -insert extensionBuild -string "$extension_build" "$receipt"
    /usr/bin/plutil -insert runtimeGenerationID -string "$runtime_generation_id" "$receipt"
    /usr/bin/plutil -insert appPackageGenerationID -string "$app_package_generation_id" "$receipt"
    /usr/bin/plutil -insert packagingMode -string "$packaging_mode" "$receipt"
    /usr/bin/plutil -insert runtimeChannel -string test "$receipt"
    /usr/bin/plutil -insert extensionExecutableSHA256 -string "$appex_sha256" "$receipt"
    /usr/bin/plutil -insert extensionCDHash -string "$extension_cdhash" "$receipt"
    /usr/bin/plutil -insert extensionBundleSHA256 -string "$extension_bundle_sha256" "$receipt"
    /usr/bin/plutil -insert teamIdentifier -string C6TUZVJ6SJ "$receipt"
    /usr/bin/plutil -insert createdAt -string "$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)" "$receipt"
    /usr/bin/plutil -lint "$receipt" >/dev/null
    chmod 600 "$delivery_output" "$receipt"
    reported_output="$delivery_output"
fi

printf 'PACKAGED output=%s commit=%s source_state=%s archive_sha256=%s executable_sha256=%s native_host_sha256=%s status_relay_sha256=%s safari_extension_sha256=%s safari_extension_bundle_sha256=%s safari_extension_cdhash=%s packaging_mode=%s app_package_generation=%s manifest_sha256=%s version=%s build=%s bundle_id=%s status=%s signing_provenance=%s notarization_eligible=%s\n' \
    "$reported_output" \
    "$commit" \
    "$source_state" \
    "$([[ "$phase" == "apple-development-test" ]] && printf '%s' "$delivery_archive_sha256" || printf '%s' "$archive_sha256")" \
    "$executable_sha256" \
    "$native_host_sha256" \
    "$status_relay_sha256" \
    "$appex_sha256" \
    "$extension_bundle_sha256" \
    "$extension_cdhash" \
    "${packaging_mode:-COMPANION_MIGRATION}" \
    "$app_package_generation_id" \
    "$manifest_sha256" \
    "$resolved_marketing_version" \
    "$build_number" \
    "$BUNDLE_ID" \
    "$integration_status" \
    "$signing_provenance" \
    "$notarization_eligible"

# Optional. Runs only when a notarization keychain profile is named, so the
# default packaging path stays entirely offline. The profile is created once by
# `xcrun notarytool store-credentials`; the credential itself lives in the
# operator's keychain and is never read, echoed, or stored by this script.
if [[ -n "$notary_profile" ]]; then
    readonly notary_archive="$package_root/notarize.zip"
    /usr/bin/ditto -c -k --keepParent "$output" "$notary_archive"
    /usr/bin/xcrun notarytool submit "$notary_archive" \
        --keychain-profile "$notary_profile" \
        --wait
    /usr/bin/xcrun stapler staple "$output"
    /usr/bin/xcrun stapler validate "$output"
    /usr/sbin/spctl --assess --type execute --verbose=4 "$output"
    printf 'NOTARIZED output=%s bundle_id=%s\n' "$output" "$BUNDLE_ID"
fi
completed=1
