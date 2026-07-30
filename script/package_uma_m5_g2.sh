#!/usr/bin/env bash
# Builds and audits one immutable, commit-exact offline M5-G2 package.
set -euo pipefail
umask 077

package_root=""
output_parent=""
completed=0
cleanup() {
    if [[ -n "$package_root" && -d "$package_root" ]]; then
        rm -rf -- "$package_root"
    fi
    if [[ "$completed" != 1
        && -n "$output_parent"
        && -d "$output_parent" ]]; then
        rm -rf -- "$output_parent"
    fi
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM

readonly REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
readonly PRODUCT="CodexUsageMonitor"
readonly HELPER="ClaudeStatusLineRelay"
readonly MARKETING_VERSION="0.11"
readonly BUNDLE_ID="com.kevinchen.CodexUsageMonitor"
readonly DEFAULT_BUILD="202607290003"
readonly SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"

usage() {
    printf '%s\n' \
        "Usage: $0 --commit <40-hex-sha> [--build <12-digit-number>] [--phase g2-final|g3-preflight|g3-final] --output <phase-exact-path>/UMA.app"
}

commit=""
build_number="$DEFAULT_BUILD"
phase="g2-final"
output=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --commit) commit="${2:-}"; shift 2 ;;
        --build) build_number="${2:-}"; shift 2 ;;
        --phase) phase="${2:-}"; shift 2 ;;
        --output) output="${2:-}"; shift 2 ;;
        *) usage >&2; exit 2 ;;
    esac
done

[[ "$commit" =~ ^[0-9a-f]{40}$ ]] || { usage >&2; exit 2; }
[[ "$build_number" =~ ^[0-9]{12}$ ]] || { usage >&2; exit 2; }
[[ -d "$SDK" ]] || {
    printf 'Required offline SDK is unavailable: %s\n' "$SDK" >&2
    exit 1
}
case "$phase" in
    g2-final)
        expected_output="/private/tmp/uma-m5-g2-final-$commit/UMA.app"
        provenance_name="UMA-M5-G2-Provenance.plist"
        integration_status="OFFLINE-READY-LIVE-NOT-VALIDATED"
        report_status="LIVE-CLAUDE-QUOTA-NOT-YET-VALIDATED"
        ;;
    g3-preflight)
        expected_output="/private/tmp/uma-m5-g3-preflight-${commit:0:12}/UMA.app"
        provenance_name="UMA-M5-G3-Provenance.plist"
        integration_status="LIVE-PREFLIGHT"
        report_status="$integration_status"
        ;;
    g3-final)
        expected_output="/private/tmp/uma-m5-g3-final-$commit/UMA.app"
        provenance_name="UMA-M5-G3-Provenance.plist"
        integration_status="LIVE-VALIDATED-SETTINGS-RESTORED"
        report_status="$integration_status"
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac
readonly expected_output
readonly provenance_name
readonly integration_status
readonly report_status
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
readonly canonical_tmp="$(cd /private/tmp && pwd -P)"
readonly canonical_parent_base="$(cd "$(dirname "$output_parent")" && pwd -P)"
[[ "$canonical_parent_base" == "$canonical_tmp" ]] || {
    printf 'Refusing non-canonical package parent %s\n' \
        "$canonical_parent_base" >&2
    exit 2
}
mkdir "$output_parent"

git -C "$REPO_ROOT" cat-file -e "$commit^{commit}"
package_root="/private/tmp/uma-m5-package-$phase-$commit"
readonly source_root="$package_root/source"
readonly source_archive="$package_root/source-$commit.tar"
readonly scratch_root="$package_root/swift"
readonly home_root="$package_root/home"
readonly tmp_root="$package_root/tmp"
readonly cache_root="$package_root/cache"
readonly config_root="$package_root/config"
readonly security_root="$package_root/security"
[[ ! -e "$package_root" && ! -L "$package_root" ]] || {
    printf 'Refusing to reuse %s\n' "$package_root" >&2
    exit 2
}
mkdir -p \
    "$source_root" \
    "$home_root" \
    "$tmp_root" \
    "$cache_root/clang" \
    "$cache_root/swiftpm" \
    "$config_root" \
    "$security_root"

git -C "$REPO_ROOT" archive \
    --format=tar \
    --output="$source_archive" \
    "$commit"
tar -xf "$source_archive" -C "$source_root"
readonly archive_sha256="$(
    /usr/bin/shasum -a 256 "$source_archive" | /usr/bin/awk '{print $1}'
)"
[[ -f "$source_root/Package.swift" && -f "$source_root/Assets/AppIcon.icns" ]] || {
    printf '%s\n' "Commit archive is incomplete." >&2
    exit 1
}

readonly forbidden_runtime='ANTHROPIC_API_KEY|CLAUDE_CODE_OAUTH_TOKEN|apiKeyHelper|Authorization:|Bearer [A-Za-z0-9._-]{20,}|ManusUsageConnector|x-manus-api-key|/v2/usage\.availableCredits'
readonly forbidden_private_field='session_id|session_name|prompt_id|transcript_path|account_identity|workspace_path|worktree_path|tool_input|tool_output|raw_json|"(cwd|response|task)"'
if /usr/bin/grep -R -E -q \
    "$forbidden_runtime" \
    "$source_root/Sources"; then
    printf '%s\n' "Production source retained forbidden private or credential material." >&2
    exit 1
fi
if /usr/bin/grep -R -E -q \
    "$forbidden_private_field" \
    "$source_root/Sources/ClaudeStatusLineCore" \
    "$source_root/Sources/ClaudeStatusLineRelay"; then
    printf '%s\n' "Relay source retained a forbidden provider field." >&2
    exit 1
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
)

pushd "$source_root" >/dev/null
/usr/bin/xcrun swift build \
    "${swift_options[@]}" \
    -c release \
    --product "$PRODUCT"
/usr/bin/xcrun swift build \
    "${swift_options[@]}" \
    -c release \
    --product "$HELPER"
readonly bin_path="$(
    /usr/bin/xcrun swift build \
        "${swift_options[@]}" \
        -c release \
        --show-bin-path
)"
popd >/dev/null
readonly binary_path="$bin_path/$PRODUCT"
readonly helper_path="$bin_path/$HELPER"
[[ -x "$binary_path" && -x "$helper_path" ]] || {
    printf '%s\n' "Expected release executables are missing." >&2
    exit 1
}

readonly contents="$output/Contents"
mkdir -p "$contents/MacOS" "$contents/Helpers" "$contents/Resources"
install -m 755 "$binary_path" "$contents/MacOS/$PRODUCT"
install -m 755 "$helper_path" "$contents/Helpers/$HELPER"
install -m 644 \
    "$source_root/Assets/AppIcon.icns" \
    "$contents/Resources/AppIcon.icns"

cat > "$contents/Resources/$provenance_name" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Revision</key><string>$commit</string>
<key>SourceArchiveSHA256</key><string>$archive_sha256</string>
<key>SourceState</key><string>commit-exact</string>
<key>ClaudeIntegrationStatus</key><string>$integration_status</string>
<key>ClaudeSource</key><string>Official local status line</string>
</dict></plist>
PLIST
chmod 644 \
    "$contents/Resources/$provenance_name"

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
<key>UMASourceArchiveSHA256</key><string>$archive_sha256</string>
<key>UMASourceState</key><string>commit-exact</string>
</dict></plist>
PLIST
chmod 644 "$contents/Info.plist"

/usr/bin/plutil -lint "$contents/Info.plist" >/dev/null
/usr/bin/plutil -lint \
    "$contents/Resources/$provenance_name" >/dev/null
/usr/bin/codesign --force --deep --sign - "$output"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$output"

for executable in "$contents/MacOS/$PRODUCT" "$contents/Helpers/$HELPER"; do
    [[ "$(/usr/bin/lipo -archs "$executable")" == "arm64" ]] || {
        printf 'Executable is not arm64-only: %s\n' "$executable" >&2
        exit 1
    }
done
if /usr/bin/find "$output" -type l -print -quit | /usr/bin/grep -q .; then
    printf '%s\n' "Package contains a symbolic link." >&2
    exit 1
fi
if /usr/bin/find "$output" -type f \
    \( -iname '*.json' -o -iname '*.sqlite*' -o -iname '*.db' \
       -o -iname '*.log' -o -iname '*.png' -o -iname '*.jpg' \
       -o -iname '*.md' -o -iname '*.txt' -o -iname '*.sock' \
       -o -iname '*backup*' \) \
    -print -quit | /usr/bin/grep -q .; then
    printf '%s\n' "Package contains a fixture, backup, socket, log, or evidence file." >&2
    exit 1
fi

readonly expected_manifest="$(
    printf '%s\n' \
        "Contents/Helpers/$HELPER" \
        "Contents/Info.plist" \
        "Contents/MacOS/$PRODUCT" \
        "Contents/Resources/AppIcon.icns" \
        "Contents/Resources/$provenance_name" \
        "Contents/_CodeSignature/CodeResources"
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

for executable in "$contents/MacOS/$PRODUCT" "$contents/Helpers/$HELPER"; do
    strings_file="$package_root/$(basename "$executable")-strings.txt"
    /usr/bin/strings -a "$executable" > "$strings_file"
    if /usr/bin/grep -E -q \
        "$forbidden_runtime|BEGIN [A-Z ]*PRIVATE KEY" \
        "$strings_file"; then
        printf 'Executable retained forbidden material: %s\n' "$executable" >&2
        exit 1
    fi
    if [[ "$(basename "$executable")" == "$HELPER" ]] \
        && /usr/bin/grep -E -q \
            "$forbidden_private_field" \
            "$strings_file"; then
        printf '%s\n' "Relay helper retained a forbidden provider field." >&2
        exit 1
    fi

    dependency_audit="$package_root/$(basename "$executable")-dependencies.txt"
    /usr/bin/otool -L "$executable" > "$dependency_audit"
    if /usr/bin/awk 'NR > 1 {print $1}' "$dependency_audit" \
        | /usr/bin/grep -Ev '^(/System/Library/|/usr/lib/)' \
        | /usr/bin/grep -q .; then
        printf 'Executable contains a non-system dependency: %s\n' "$executable" >&2
        exit 1
    fi
done

readonly executable_sha256="$(
    /usr/bin/shasum -a 256 "$contents/MacOS/$PRODUCT" \
        | /usr/bin/awk '{print $1}'
)"
readonly helper_sha256="$(
    /usr/bin/shasum -a 256 "$contents/Helpers/$HELPER" \
        | /usr/bin/awk '{print $1}'
)"
readonly manifest_sha256="$(
    (
        cd "$output"
        /usr/bin/find . -type f -print0 \
            | LC_ALL=C /usr/bin/sort -z \
            | /usr/bin/xargs -0 /usr/bin/shasum -a 256
    ) | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}'
)"

printf 'PACKAGED output=%s commit=%s archive_sha256=%s executable_sha256=%s helper_sha256=%s manifest_sha256=%s version=%s build=%s bundle_id=%s status=%s\n' \
    "$output" \
    "$commit" \
    "$archive_sha256" \
    "$executable_sha256" \
    "$helper_sha256" \
    "$manifest_sha256" \
    "$MARKETING_VERSION" \
    "$build_number" \
    "$BUNDLE_ID" \
    "$report_status"
completed=1
