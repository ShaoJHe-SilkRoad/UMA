#!/usr/bin/env bash
# Build and audit an M6 Antigravity preflight or commit-exact package.
set -euo pipefail
umask 077

readonly REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
readonly PRODUCT="CodexUsageMonitor"
readonly NATIVE_HOST="ClaudeBrowserNativeHost"
readonly SAFARI_EXTENSION="ClaudeBrowserCompanion"
readonly CHROMIUM_HOST_NAME="com.silkrd.uma.claude_browser"
readonly BUNDLE_ID="com.silkrd.uma"
readonly MARKETING_VERSION="0.11"
readonly DELIVERY_ROOT="$HOME/Developer/UMA-Packages"
readonly DEFAULT_DEVELOPER_DIR="/Library/Developer/CommandLineTools"
readonly DEFAULT_CLT_SDK="$DEFAULT_DEVELOPER_DIR/SDKs/MacOSX26.5.sdk"

usage() {
    printf '%s\n' \
        "Usage: $0 --commit <40-hex-sha> --phase <preflight|final|g3-preflight|g3-final|m6dbg-preflight|m6dbg-final> --output <exact-path> [--build <12-digit-number>]" \
        "Expected output: $DELIVERY_ROOT/uma-m6[-g3|-m6dbg]-<phase>-<commit>/UMA.app"
}

commit=""
phase=""
output=""
build_number="202608090001"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --commit) commit="${2:-}"; shift 2 ;;
        --phase) phase="${2:-}"; shift 2 ;;
        --output) output="${2:-}"; shift 2 ;;
        --build) build_number="${2:-}"; shift 2 ;;
        *) usage >&2; exit 2 ;;
    esac
done

[[ "$commit" =~ ^[0-9a-f]{40}$ ]] || { usage >&2; exit 2; }
[[ "$phase" == "preflight" || "$phase" == "final" \
    || "$phase" == "g3-preflight" || "$phase" == "g3-final" \
    || "$phase" == "m6dbg-preflight" || "$phase" == "m6dbg-final" ]] \
    || { usage >&2; exit 2; }
[[ "$build_number" =~ ^[0-9]{12}$ ]] || { usage >&2; exit 2; }
if [[ "$phase" == m6dbg-* ]]; then
    readonly expected_output="$DELIVERY_ROOT/uma-m6dbg-${phase#m6dbg-}-$commit/UMA.app"
elif [[ "$phase" == g3-* ]]; then
    readonly expected_output="$DELIVERY_ROOT/uma-m6-g3-${phase#g3-}-$commit/UMA.app"
else
    readonly expected_output="$DELIVERY_ROOT/uma-m6-$phase-$commit/UMA.app"
fi
[[ "$output" == "$expected_output" ]] || {
    printf 'Refusing output outside %s\n' "$expected_output" >&2
    exit 2
}
[[ ! -e "$output" && ! -L "$output" ]] || {
    printf 'Refusing to overwrite %s\n' "$output" >&2
    exit 2
}

readonly developer_dir="${DEVELOPER_DIR:-$DEFAULT_DEVELOPER_DIR}"
[[ -d "$developer_dir" && ! -L "$developer_dir" ]] || {
    printf 'Missing supported Xcode developer directory: %s\n' "$developer_dir" >&2
    exit 1
}
if [[ "$developer_dir" == "$DEFAULT_DEVELOPER_DIR" ]]; then
    [[ -d "$DEFAULT_CLT_SDK" && ! -L "$DEFAULT_CLT_SDK" ]] || {
        printf 'Missing supported Command Line Tools SDK: %s\n' "$DEFAULT_CLT_SDK" >&2
        exit 1
    }
    sdk="$DEFAULT_CLT_SDK"
else
    readonly xcode_bundle="$(cd "$developer_dir/../.." && pwd -P)"
    [[ "$(/usr/bin/plutil -extract CFBundleIdentifier raw "$xcode_bundle/Contents/Info.plist")" == "com.apple.dt.Xcode" ]] || {
        printf '%s\n' "Refusing a non-Xcode developer directory." >&2
        exit 1
    }
    sdk="$(DEVELOPER_DIR="$developer_dir" /usr/bin/xcrun --sdk macosx --show-sdk-path)"
fi
readonly sdk
readonly swift_version="$(DEVELOPER_DIR="$developer_dir" /usr/bin/xcrun swift --version | /usr/bin/head -n 1)"
[[ "$swift_version" == *"Apple Swift version"* ]] || {
    printf '%s\n' "Refusing a non-Apple Swift toolchain." >&2
    exit 1
}

git -C "$REPO_ROOT" cat-file -e "$commit^{commit}"
[[ "$(git -C "$REPO_ROOT" rev-parse HEAD)" == "$commit" ]] || {
    printf '%s\n' "Requested commit is not current HEAD." >&2
    exit 1
}

mkdir -p "$DELIVERY_ROOT"
[[ ! -L "$DELIVERY_ROOT" \
    && "$(/usr/bin/stat -f '%u' "$DELIVERY_ROOT")" == "$(/usr/bin/id -u)" ]] || {
    printf '%s\n' "Delivery root must be current-user owned and not a symlink." >&2
    exit 1
}
readonly output_parent="$(dirname "$output")"
[[ ! -e "$output_parent" && ! -L "$output_parent" ]] || {
    printf 'Refusing existing package parent %s\n' "$output_parent" >&2
    exit 2
}
mkdir "$output_parent"

readonly package_root="/private/tmp/uma-m6-package-$phase-$commit"
[[ ! -e "$package_root" && ! -L "$package_root" ]] || {
    printf 'Refusing existing task path %s\n' "$package_root" >&2
    exit 2
}
completed=0
cleanup() {
    if [[ -d "$package_root" && ! -L "$package_root" ]]; then
        rm -rf -- "$package_root"
    fi
    if [[ "$completed" != 1 && -d "$output_parent" && ! -L "$output_parent" ]]; then
        rm -rf -- "$output_parent"
    fi
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM

mkdir -p "$package_root/home" "$package_root/tmp" \
    "$package_root/cache/clang" "$package_root/cache/swiftpm" \
    "$package_root/config" "$package_root/security"
if [[ "$phase" == "final" || "$phase" == "g3-final" \
    || "$phase" == "m6dbg-final" ]]; then
    source_root="$package_root/source"
    mkdir "$source_root"
    git -C "$REPO_ROOT" archive --format=tar --output="$package_root/source.tar" "$commit"
    /usr/bin/tar -xf "$package_root/source.tar" -C "$source_root"
    archive_sha256="$(/usr/bin/shasum -a 256 "$package_root/source.tar" | /usr/bin/awk '{print $1}')"
    source_state="commit-exact"
else
    source_root="$REPO_ROOT"
    archive_sha256="WORKING-TREE-PREFLIGHT"
    source_state="working-tree-preflight"
fi
readonly source_root archive_sha256 source_state

[[ -f "$source_root/Package.swift" \
    && -f "$source_root/Assets/AppIcon.icns" \
    && -f "$source_root/BrowserExtension/Safari/manifest.json" \
    && -f "$source_root/BrowserExtension/Chromium/manifest.json" ]] || {
    printf '%s\n' "Package source set is incomplete." >&2
    exit 1
}

export HOME="$package_root/home"
export TMPDIR="$package_root/tmp"
export SDKROOT="$sdk"
export CLANG_MODULE_CACHE_PATH="$package_root/cache/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$package_root/cache/swiftpm"
readonly swift_options=(
    --package-path "$source_root"
    --scratch-path "$package_root/swift"
    --cache-path "$package_root/cache/swiftpm"
    --config-path "$package_root/config"
    --security-path "$package_root/security"
    --disable-sandbox
    --disable-keychain
    --disable-netrc
    --manifest-cache local
    --sdk "$sdk"
    -Xswiftc -sdk -Xswiftc "$sdk"
)
DEVELOPER_DIR="$developer_dir" /usr/bin/xcrun swift build \
    "${swift_options[@]}" -c release --product "$PRODUCT"
DEVELOPER_DIR="$developer_dir" /usr/bin/xcrun swift build \
    "${swift_options[@]}" -c release --product "$NATIVE_HOST"
readonly bin_path="$(
    DEVELOPER_DIR="$developer_dir" /usr/bin/xcrun swift build \
        "${swift_options[@]}" -c release --show-bin-path
)"
readonly product_binary="$bin_path/$PRODUCT"
readonly native_binary="$bin_path/$NATIVE_HOST"
[[ -x "$product_binary" && -x "$native_binary" ]] || {
    printf '%s\n' "Release executables are missing." >&2
    exit 1
}

readonly appex_binary="$package_root/$SAFARI_EXTENSION"
DEVELOPER_DIR="$developer_dir" /usr/bin/xcrun swiftc \
    -sdk "$sdk" \
    -target arm64-apple-macosx14.0 \
    -application-extension \
    -Xlinker -application_extension \
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
mkdir -p "$contents/MacOS" "$contents/Helpers" "$contents/Resources" \
    "$appex_contents/MacOS" "$appex_contents/Resources/Shared" \
    "$appex_contents/Resources/Safari" "$chromium_root/Shared" \
    "$chromium_root/Chromium" "$chromium_host_root"
/usr/bin/install -m 755 "$product_binary" "$contents/MacOS/$PRODUCT"
/usr/bin/install -m 755 "$native_binary" "$contents/Helpers/$NATIVE_HOST"
/usr/bin/install -m 755 "$appex_binary" "$appex_contents/MacOS/$SAFARI_EXTENSION"
/usr/bin/install -m 644 "$source_root/Assets/AppIcon.icns" "$contents/Resources/AppIcon.icns"
/usr/bin/install -m 644 "$source_root/BrowserExtension/Safari/Native/Info.plist" "$appex_contents/Info.plist"
/usr/bin/install -m 644 "$source_root/BrowserExtension/Safari/manifest.json" "$appex_contents/Resources/manifest.json"
/usr/bin/install -m 644 "$source_root/BrowserExtension/Safari/background-loader.js" "$appex_contents/Resources/Safari/background-loader.js"
for file in background-core.js claude-usage-extractor.js content-script.js; do
    /usr/bin/install -m 644 "$source_root/BrowserExtension/Shared/$file" "$appex_contents/Resources/Shared/$file"
    /usr/bin/install -m 644 "$source_root/BrowserExtension/Shared/$file" "$chromium_root/Shared/$file"
done
/usr/bin/install -m 644 "$source_root/BrowserExtension/Chromium/manifest.json" "$chromium_root/manifest.json"
/usr/bin/install -m 644 "$source_root/BrowserExtension/Chromium/background-loader.js" "$chromium_root/Chromium/background-loader.js"
/usr/bin/sed \
    "s#__UMA_CLAUDE_BROWSER_NATIVE_HOST_PATH__#$contents/Helpers/$NATIVE_HOST#" \
    "$source_root/BrowserExtension/Chromium/$CHROMIUM_HOST_NAME.json" \
    > "$chromium_host_root/$CHROMIUM_HOST_NAME.json"
/bin/chmod 644 "$chromium_host_root/$CHROMIUM_HOST_NAME.json"

cat > "$contents/Resources/UMA-M6-Provenance.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Revision</key><string>$commit</string>
<key>SourceArchiveSHA256</key><string>$archive_sha256</string>
<key>SourceState</key><string>$source_state</string>
<key>AntigravitySource</key><string>Official read-only CLI usage command</string>
<key>CreditsStatus</key><string>DEFERRED</string>
</dict></plist>
PLIST
cat > "$contents/Resources/UMA-M5-BROWSER-Provenance.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Revision</key><string>$commit</string>
<key>SourceArchiveSHA256</key><string>$archive_sha256</string>
<key>SourceState</key><string>$source_state</string>
<key>ClaudeIntegrationStatus</key><string>AUTOMATIC-BROWSER-SYNC-ACCEPTED-STATUS-LINE-REMOVED</string>
<key>ClaudeSource</key><string>Official Usage page via Browser Companion</string>
</dict></plist>
PLIST
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
<key>CFBundleShortVersionString</key><string>$MARKETING_VERSION</string>
<key>CFBundleVersion</key><string>$build_number</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>UMAReviewCommit</key><string>$commit</string>
<key>UMASourceState</key><string>$source_state</string>
</dict></plist>
PLIST
/bin/chmod 644 "$contents/Info.plist" \
    "$contents/Resources/UMA-M5-BROWSER-Provenance.plist" \
    "$contents/Resources/UMA-M6-Provenance.plist"
/usr/bin/plutil -lint "$contents/Info.plist" >/dev/null
/usr/bin/plutil -lint "$contents/Resources/UMA-M6-Provenance.plist" >/dev/null
/usr/bin/plutil -lint "$contents/Resources/UMA-M5-BROWSER-Provenance.plist" >/dev/null
/usr/bin/plutil -lint "$appex_contents/Info.plist" >/dev/null
for json in \
    "$appex_contents/Resources/manifest.json" \
    "$chromium_root/manifest.json" \
    "$chromium_host_root/$CHROMIUM_HOST_NAME.json"; do
    /usr/bin/ruby -rjson -e 'JSON.parse(File.binread(ARGV.fetch(0)))' "$json"
done

/usr/bin/codesign --force --sign - --identifier "$BUNDLE_ID.ClaudeBrowserNativeHost" "$contents/Helpers/$NATIVE_HOST"
/usr/bin/codesign --force --sign - \
    --identifier "$BUNDLE_ID.ClaudeBrowserCompanion" \
    --entitlements "$source_root/BrowserExtension/Safari/Native/ClaudeBrowserCompanion.entitlements" \
    "$appex"
/usr/bin/codesign --force --sign - --identifier "$BUNDLE_ID" "$output"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$output"

for executable in "$contents/MacOS/$PRODUCT" "$contents/Helpers/$NATIVE_HOST" "$appex_contents/MacOS/$SAFARI_EXTENSION"; do
    [[ "$(/usr/bin/lipo -archs "$executable")" == "arm64" ]] || {
        printf 'Non-arm64 executable: %s\n' "$executable" >&2
        exit 1
    }
    if /usr/bin/otool -L "$executable" \
        | /usr/bin/awk 'NR > 1 {print $1}' \
        | /usr/bin/grep -Ev '^(/System/Library/|/usr/lib/)' \
        | /usr/bin/grep -q .; then
        printf 'Non-system dependency: %s\n' "$executable" >&2
        exit 1
    fi
done
if /usr/bin/find "$output" -type l -print -quit | /usr/bin/grep -q .; then
    printf '%s\n' "Package contains a symlink." >&2
    exit 1
fi
if /usr/bin/find "$output" -type f \
    \( -iname '*.db' -o -iname '*.sqlite*' -o -iname '*.log' \
       -o -iname '*.md' -o -iname '*.txt' -o -iname '*.sock' -o -iname '*backup*' \) \
    -print -quit | /usr/bin/grep -q .; then
    printf '%s\n' "Package contains a saved record, fixture, log, or evidence file." >&2
    exit 1
fi
if /usr/bin/find "$output" -type f -print0 \
    | /usr/bin/xargs -0 /usr/bin/grep -a -E -l \
        'Claude Code-credentials|ANTHROPIC_API_KEY|setup-token|x-manus-api-key|remaining_fraction.*reset_time' \
    | /usr/bin/grep -q .; then
    printf '%s\n' "Package contains a credential route or provider fixture." >&2
    exit 1
fi
[[ ! -e "$contents/MacOS/agy" && ! -e "$contents/Helpers/agy" ]] || {
    printf '%s\n' "The provider CLI must not be bundled." >&2
    exit 1
}

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
        "Contents/Resources/UMA-M6-Provenance.plist" \
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

printf 'M6 package PASS\ncommit=%s\nsource=%s\nswift=%s\noutput=%s\n' \
    "$commit" "$source_state" "$swift_version" "$output"
completed=1
