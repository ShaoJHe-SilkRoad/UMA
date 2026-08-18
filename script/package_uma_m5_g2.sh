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
readonly SAFARI_EXTENSION="ClaudeBrowserCompanion"
readonly MARKETING_VERSION="0.11"
readonly BUNDLE_ID="com.silkrd.uma"
readonly SAFARI_EXTENSION_ID="$BUNDLE_ID.ClaudeBrowserCompanion"
readonly CHROMIUM_HOST_NAME="com.silkrd.uma.claude_browser"
readonly DEFAULT_BUILD="202608010001"
readonly SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
readonly user_home="$HOME"
# Delivery artifacts must outlive the operating system's periodic purge of
# temporary items, which silently destroyed every earlier M5 package. Only the
# scratch build tree below stays under /private/tmp, where automatic cleanup of
# abandoned intermediates is wanted.
readonly DELIVERY_ROOT="$HOME/Developer/UMA-Packages"

usage() {
    printf '%s\n' \
        "Usage: $0 --commit <40-hex-sha> [--build <12-digit-number>] --phase <m5-browser-preflight|m5-browser-final|m5adbg-preflight|m5adbg-final|m5-auto-preflight|m5-auto-final|m5-slr-final|m5rmx-safari-preflight> --output <exact-path>" \
        "Packages are delivered under $DELIVERY_ROOT and are not purged with /private/tmp." \
        "" \
        "Signing and notarization (both optional):" \
        "  --signing-identity <name>   Developer ID Application identity. Defaults to '-'," \
        "                              which is ad-hoc and cannot be notarized. A real" \
        "                              identity also enables the hardened runtime and a" \
        "                              secure timestamp, which notarization requires." \
        "  --keychain-profile <name>   notarytool profile created once with" \
        "                              'xcrun notarytool store-credentials'. Submits, waits," \
        "                              staples, and assesses. Requires --signing-identity."
}

commit=""
build_number="$DEFAULT_BUILD"
phase=""
output=""
# Ad-hoc by default so every existing invocation keeps its current behaviour.
# A real Developer ID identity additionally enables the hardened runtime and a
# secure timestamp, both of which notarization requires.
signing_identity="-"
notary_profile=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --commit) commit="${2:-}"; shift 2 ;;
        --build) build_number="${2:-}"; shift 2 ;;
        --phase) phase="${2:-}"; shift 2 ;;
        --output) output="${2:-}"; shift 2 ;;
        --signing-identity) signing_identity="${2:-}"; shift 2 ;;
        --keychain-profile) notary_profile="${2:-}"; shift 2 ;;
        *) usage >&2; exit 2 ;;
    esac
done
readonly signing_identity notary_profile
[[ -n "$signing_identity" ]] || { usage >&2; exit 2; }
if [[ -n "$notary_profile" && "$signing_identity" == "-" ]]; then
    printf '%s\n' \
        "Notarization requires --signing-identity with a Developer ID Application certificate." >&2
    exit 2
fi

codesign_options=(--force --sign "$signing_identity")
if [[ "$signing_identity" != "-" ]]; then
    codesign_options+=(--options runtime --timestamp)
fi
readonly codesign_options

[[ "$commit" =~ ^[0-9a-f]{40}$ ]] || { usage >&2; exit 2; }
[[ "$build_number" =~ ^[0-9]{12}$ ]] || { usage >&2; exit 2; }
[[ -d "$SDK" ]] || { printf 'Missing offline SDK: %s\n' "$SDK" >&2; exit 1; }
resolved_marketing_version="$MARKETING_VERSION"
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
        [[ "$signing_identity" != "-" ]] || {
            printf '%s\n' "M5RMX Safari preflight requires a Developer ID Application identity." >&2
            exit 2
        }
        [[ -z "$notary_profile" ]] || {
            printf '%s\n' "M5RMX Safari preflight does not submit for notarization." >&2
            exit 2
        }
        ;;
    *) usage >&2; exit 2 ;;
esac
readonly expected_output source_state integration_status commit_exact resolved_marketing_version
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
[[ ! -L "$DELIVERY_ROOT" ]] || {
    printf 'Refusing symlinked delivery root %s\n' "$DELIVERY_ROOT" >&2
    exit 2
}
mkdir -p "$DELIVERY_ROOT"
[[ -d "$DELIVERY_ROOT" \
    && "$(/usr/bin/stat -f '%u' "$DELIVERY_ROOT")" == "$(/usr/bin/id -u)" ]] || {
    printf 'Refusing delivery root not owned by the current user: %s\n' \
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

case "$phase" in
    m5adbg-*) package_root="/private/tmp/uma-m5adbg-package-$phase-$commit" ;;
    m5-auto-*) package_root="/private/tmp/uma-m5-auto-package-$phase-$commit" ;;
    m5-slr-*) package_root="/private/tmp/uma-m5-slr-package-$phase-$commit" ;;
    m5rmx-safari-*) package_root="/private/tmp/uma-m5rmx-safari-package-$phase-$commit" ;;
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

readonly forbidden_runtime='ClaudeQuotaBroker|ClaudeStatusLine|Claude Code-credentials|SecItem(Add|CopyMatching|Update|Delete)|/api/oauth/usage|Authorization: Bearer|accessToken|refreshToken|ANTHROPIC_API_KEY|CLAUDE_CODE_OAUTH_TOKEN|setup-token'
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
if [[ "$phase" == m5-auto-* \
    || "$phase" == m5-slr-* \
    || "$phase" == m5rmx-safari-* ]]; then
    /usr/bin/grep -F -q '"manifest_version": 2' "$safari_manifest"
    /usr/bin/grep -F -q '"permissions": ["nativeMessaging", "storage", "https://claude.ai/new*"]' "$safari_manifest"
    /usr/bin/grep -F -q '"Shared/claude-usage-extractor.js"' "$safari_manifest"
    /usr/bin/grep -F -q '"Safari/background-loader.js"' "$safari_manifest"
    /usr/bin/grep -F -q '"Shared/background-core.js"' "$safari_manifest"
    /usr/bin/grep -F -q '"persistent": true' "$safari_manifest"
    ! /usr/bin/grep -F -q '"host_permissions"' "$safari_manifest"
    ! /usr/bin/grep -F -q '"service_worker"' "$safari_manifest"
    ! /usr/bin/grep -F -q '"activeTab"' "$safari_manifest"
    ! /usr/bin/grep -F -q '"content_scripts"' "$safari_manifest"
else
    /usr/bin/grep -F -q '"permissions": ["activeTab", "nativeMessaging", "scripting"]' "$safari_manifest"
    ! /usr/bin/grep -F -q '"host_permissions"' "$safari_manifest"
    ! /usr/bin/grep -F -q '"content_scripts"' "$safari_manifest"
fi
/usr/bin/grep -F -q '"permissions": ["activeTab", "nativeMessaging", "scripting"]' "$chromium_manifest"
! /usr/bin/grep -F -q '"host_permissions"' "$chromium_manifest"
! /usr/bin/grep -F -q '"content_scripts"' "$chromium_manifest"
/usr/bin/grep -F -q 'href: "https://claude.ai/new#settings/usage"' \
    "$source_root/BrowserExtension/Shared/claude-usage-extractor.js"
! /usr/bin/grep -F -q 'tabs.onUpdated' \
    "$source_root/BrowserExtension/Shared/background-core.js"
/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' \
    "$source_root/BrowserExtension/Safari/Native/ClaudeBrowserCompanion.entitlements" \
    | /usr/bin/grep -Fx -q 'true'
if /usr/libexec/PlistBuddy -c 'Print :com.apple.security.network.client' \
    "$source_root/BrowserExtension/Safari/Native/ClaudeBrowserCompanion.entitlements" \
    >/dev/null 2>&1; then
    printf '%s\n' "Safari companion must not receive a network-client entitlement." >&2
    exit 1
fi
/usr/libexec/PlistBuddy -c \
    'Print :com.apple.security.temporary-exception.files.home-relative-path.read-write:0' \
    "$source_root/BrowserExtension/Safari/Native/ClaudeBrowserCompanion.entitlements" \
    | /usr/bin/grep -Fx -q \
        '/Library/Application Support/CodexUsageMonitor/ClaudeBrowserCompanion/'

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
/usr/bin/xcrun swift build "${swift_options[@]}" -c release --product "$PRODUCT"
/usr/bin/xcrun swift build "${swift_options[@]}" -c release --product "$NATIVE_HOST"
readonly bin_path="$(
    /usr/bin/xcrun swift build "${swift_options[@]}" -c release --show-bin-path
)"
popd >/dev/null
readonly binary_path="$bin_path/$PRODUCT"
readonly native_host_path="$bin_path/$NATIVE_HOST"
[[ -x "$binary_path" && -x "$native_host_path" ]] || {
    printf '%s\n' "Expected release executables are missing." >&2
    exit 1
}

readonly appex_binary="$package_root/$SAFARI_EXTENSION"
/Library/Developer/CommandLineTools/usr/bin/swiftc \
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

readonly contents="$output/Contents"
readonly appex="$contents/PlugIns/$SAFARI_EXTENSION.appex"
readonly appex_contents="$appex/Contents"
readonly chromium_root="$contents/Resources/BrowserCompanion/Chromium"
readonly chromium_host_root="$contents/Resources/BrowserCompanion/ChromiumNativeHost"
mkdir -p \
    "$contents/MacOS" \
    "$contents/Helpers" \
    "$contents/Resources" \
    "$appex_contents/MacOS" \
    "$appex_contents/Resources/Shared" \
    "$appex_contents/Resources/Safari" \
    "$chromium_root/Shared" \
    "$chromium_root/Chromium" \
    "$chromium_host_root"
install -m 755 "$binary_path" "$contents/MacOS/$PRODUCT"
install -m 755 "$native_host_path" "$contents/Helpers/$NATIVE_HOST"
install -m 755 "$appex_binary" "$appex_contents/MacOS/$SAFARI_EXTENSION"
install -m 644 "$source_root/Assets/AppIcon.icns" "$contents/Resources/AppIcon.icns"
install -m 644 "$source_root/BrowserExtension/Safari/Native/Info.plist" "$appex_contents/Info.plist"
install -m 644 "$source_root/BrowserExtension/Safari/manifest.json" "$appex_contents/Resources/manifest.json"
install -m 644 "$source_root/BrowserExtension/Safari/background-loader.js" "$appex_contents/Resources/Safari/background-loader.js"
install -m 644 "$source_root/BrowserExtension/Shared/claude-usage-extractor.js" "$appex_contents/Resources/Shared/claude-usage-extractor.js"
install -m 644 "$source_root/BrowserExtension/Shared/content-script.js" "$appex_contents/Resources/Shared/content-script.js"
install -m 644 "$source_root/BrowserExtension/Shared/background-core.js" "$appex_contents/Resources/Shared/background-core.js"
install -m 644 "$source_root/BrowserExtension/Chromium/manifest.json" "$chromium_root/manifest.json"
install -m 644 "$source_root/BrowserExtension/Chromium/background-loader.js" "$chromium_root/Chromium/background-loader.js"
install -m 644 "$source_root/BrowserExtension/Shared/claude-usage-extractor.js" "$chromium_root/Shared/claude-usage-extractor.js"
install -m 644 "$source_root/BrowserExtension/Shared/content-script.js" "$chromium_root/Shared/content-script.js"
install -m 644 "$source_root/BrowserExtension/Shared/background-core.js" "$chromium_root/Shared/background-core.js"
/usr/bin/sed \
    "s#__UMA_CLAUDE_BROWSER_NATIVE_HOST_PATH__#$contents/Helpers/$NATIVE_HOST#" \
    "$source_root/BrowserExtension/Chromium/$CHROMIUM_HOST_NAME.json" \
    > "$chromium_host_root/$CHROMIUM_HOST_NAME.json"
chmod 644 "$chromium_host_root/$CHROMIUM_HOST_NAME.json"

cat > "$contents/Resources/UMA-M5-BROWSER-Provenance.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Revision</key><string>$commit</string>
<key>SourceArchiveSHA256</key><string>$archive_sha256</string>
<key>SourceState</key><string>$source_state</string>
<key>ClaudeIntegrationStatus</key><string>$integration_status</string>
<key>ClaudeSource</key><string>Official Usage page via Browser Companion</string>
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
</dict></plist>
PLIST
chmod 644 "$contents/Info.plist"

for plist in \
    "$contents/Info.plist" \
    "$contents/Resources/UMA-M5-BROWSER-Provenance.plist" \
    "$appex_contents/Info.plist"; do
    /usr/bin/plutil -lint "$plist" >/dev/null
done
for json in \
    "$appex_contents/Resources/manifest.json" \
    "$chromium_root/manifest.json" \
    "$chromium_host_root/$CHROMIUM_HOST_NAME.json"; do
    /usr/bin/ruby -rjson -e 'JSON.parse(File.binread(ARGV.fetch(0)))' "$json"
done

HOME="$user_home" /usr/bin/codesign "${codesign_options[@]}" \
    --identifier "$BUNDLE_ID.ClaudeBrowserNativeHost" \
    "$contents/Helpers/$NATIVE_HOST"
HOME="$user_home" /usr/bin/codesign "${codesign_options[@]}" \
    --identifier "$SAFARI_EXTENSION_ID" \
    --entitlements "$source_root/BrowserExtension/Safari/Native/ClaudeBrowserCompanion.entitlements" \
    "$appex"
HOME="$user_home" /usr/bin/codesign \
    "${codesign_options[@]}" --identifier "$BUNDLE_ID" "$output"
HOME="$user_home" /usr/bin/codesign --verify --deep --strict --verbose=2 "$output"

if [[ "$phase" == "m5rmx-safari-preflight" ]]; then
    for signed_target in \
        "$contents/Helpers/$NATIVE_HOST" \
        "$appex" \
        "$output"; do
        signing_report="$package_root/$(basename "$signed_target")-signing.txt"
        HOME="$user_home" /usr/bin/codesign \
            -d --verbose=4 "$signed_target" 2> "$signing_report"
        /usr/bin/grep -q '^TeamIdentifier=C6TUZVJ6SJ$' "$signing_report" || {
            printf 'Unexpected signing Team ID: %s\n' "$signed_target" >&2
            exit 1
        }
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

for executable in \
    "$contents/MacOS/$PRODUCT" \
    "$contents/Helpers/$NATIVE_HOST" \
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

readonly expected_manifest="$(
    printf '%s\n' \
        "Contents/Helpers/$NATIVE_HOST" \
        "Contents/Info.plist" \
        "Contents/MacOS/$PRODUCT" \
        "Contents/PlugIns/$SAFARI_EXTENSION.appex/Contents/Info.plist" \
        "Contents/PlugIns/$SAFARI_EXTENSION.appex/Contents/MacOS/$SAFARI_EXTENSION" \
        "Contents/PlugIns/$SAFARI_EXTENSION.appex/Contents/Resources/Safari/background-loader.js" \
        "Contents/PlugIns/$SAFARI_EXTENSION.appex/Contents/Resources/Shared/background-core.js" \
        "Contents/PlugIns/$SAFARI_EXTENSION.appex/Contents/Resources/Shared/claude-usage-extractor.js" \
        "Contents/PlugIns/$SAFARI_EXTENSION.appex/Contents/Resources/Shared/content-script.js" \
        "Contents/PlugIns/$SAFARI_EXTENSION.appex/Contents/Resources/manifest.json" \
        "Contents/PlugIns/$SAFARI_EXTENSION.appex/Contents/_CodeSignature/CodeResources" \
        "Contents/Resources/AppIcon.icns" \
        "Contents/Resources/BrowserCompanion/Chromium/Chromium/background-loader.js" \
        "Contents/Resources/BrowserCompanion/Chromium/Shared/background-core.js" \
        "Contents/Resources/BrowserCompanion/Chromium/Shared/claude-usage-extractor.js" \
        "Contents/Resources/BrowserCompanion/Chromium/Shared/content-script.js" \
        "Contents/Resources/BrowserCompanion/Chromium/manifest.json" \
        "Contents/Resources/BrowserCompanion/ChromiumNativeHost/$CHROMIUM_HOST_NAME.json" \
        "Contents/Resources/UMA-M5-BROWSER-Provenance.plist" \
        "Contents/_CodeSignature/CodeResources" \
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
readonly appex_sha256="$(
    /usr/bin/shasum -a 256 "$appex_contents/MacOS/$SAFARI_EXTENSION" | /usr/bin/awk '{print $1}'
)"
readonly manifest_sha256="$(
    (
        cd "$output"
        /usr/bin/find . -type f -print0 \
            | LC_ALL=C /usr/bin/sort -z \
            | /usr/bin/xargs -0 /usr/bin/shasum -a 256
    ) | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}'
)"

printf 'PACKAGED output=%s commit=%s source_state=%s archive_sha256=%s executable_sha256=%s native_host_sha256=%s safari_extension_sha256=%s manifest_sha256=%s version=%s build=%s bundle_id=%s status=%s\n' \
    "$output" \
    "$commit" \
    "$source_state" \
    "$archive_sha256" \
    "$executable_sha256" \
    "$native_host_sha256" \
    "$appex_sha256" \
    "$manifest_sha256" \
    "$resolved_marketing_version" \
    "$build_number" \
    "$BUNDLE_ID" \
    "$integration_status"

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
