#!/usr/bin/env bash
# Builds and audits one immutable, commit-exact M4-N retirement package.
set -euo pipefail

readonly REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
readonly PRODUCT="CodexUsageMonitor"
readonly MARKETING_VERSION="0.11"
readonly BUNDLE_ID="com.kevinchen.CodexUsageMonitor"
readonly DEFAULT_BUILD="202607280004"
readonly SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"

usage() {
    printf '%s\n' \
        "Usage: $0 --commit <40-hex-sha> [--build <12-digit-number>] --output /private/tmp/uma-m4-n-final-<short-commit>/UMA.app"
}

commit=""
build_number="$DEFAULT_BUILD"
output=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --commit) commit="${2:-}"; shift 2 ;;
        --build) build_number="${2:-}"; shift 2 ;;
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
readonly short_commit="${commit:0:12}"
readonly expected_output="/private/tmp/uma-m4-n-final-$short_commit/UMA.app"
[[ "$output" == "$expected_output" ]] || {
    printf 'Refusing output outside %s\n' "$expected_output" >&2
    exit 2
}
[[ ! -e "$output" && ! -L "$output" ]] || {
    printf 'Refusing to overwrite %s\n' "$output" >&2
    exit 2
}
readonly output_parent="$(dirname "$output")"
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
readonly package_root="/private/tmp/uma-m4-n-package-$commit"
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

readonly production_forbidden='ManusUsageConnector|ManusSettingsModel|ManusAPIKeyStore|ManusCreditsAPIClient|ManusRefreshScheduler|officialRemoteUsageAPI|currentOfficialRemoteRead|umaOwnedKeychainCredential|/v2/usage\.availableCredits|x-manus-api-key|com\.kevinchen\.CodexUsageMonitor\.manus-api-v2|Connect Manus|Save and Verify'
if /usr/bin/grep -R -E -q \
    "$production_forbidden" \
    "$source_root/Sources"; then
    printf '%s\n' "Package production source retained a rejected Manus route." >&2
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
readonly binary_path="$(
    /usr/bin/xcrun swift build \
        "${swift_options[@]}" \
        -c release \
        --show-bin-path
)/$PRODUCT"
popd >/dev/null
[[ -x "$binary_path" ]] || {
    printf '%s\n' "Expected release executable is missing." >&2
    exit 1
}

readonly contents="$output/Contents"
mkdir -p "$contents/MacOS" "$contents/Resources"
install -m 755 "$binary_path" "$contents/MacOS/$PRODUCT"
install -m 644 \
    "$source_root/Assets/AppIcon.icns" \
    "$contents/Resources/AppIcon.icns"

cat > "$contents/Resources/UMA-M4-N-Provenance.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Revision</key><string>$commit</string>
<key>SourceArchiveSHA256</key><string>$archive_sha256</string>
<key>SourceState</key><string>commit-exact</string>
<key>ProviderRetirementStatus</key><string>M4-CLOSED-NO-SOURCE</string>
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
<key>UMASourceArchiveSHA256</key><string>$archive_sha256</string>
<key>UMASourceState</key><string>commit-exact</string>
</dict></plist>
PLIST

/usr/bin/plutil -lint "$contents/Info.plist" >/dev/null
/usr/bin/plutil -lint \
    "$contents/Resources/UMA-M4-N-Provenance.plist" >/dev/null
/usr/bin/codesign --force --deep --sign - "$output"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$output"

[[ "$(/usr/bin/lipo -archs "$contents/MacOS/$PRODUCT")" == "arm64" ]] || {
    printf '%s\n' "Package executable is not arm64-only." >&2
    exit 1
}
if /usr/bin/find "$output" -type l -print -quit | /usr/bin/grep -q .; then
    printf '%s\n' "Package contains a symbolic link." >&2
    exit 1
fi
if /usr/bin/find "$output" -type f \
    \( -iname '*.json' -o -iname '*.sqlite*' -o -iname '*.db' \
       -o -iname '*.log' -o -iname '*.png' -o -iname '*.jpg' \
       -o -iname '*.md' -o -iname '*.txt' \) \
    -print -quit | /usr/bin/grep -q .; then
    printf '%s\n' "Package contains a fixture, record, log, or evidence file." >&2
    exit 1
fi

readonly expected_manifest="$(
    printf '%s\n' \
        "Contents/Info.plist" \
        "Contents/MacOS/$PRODUCT" \
        "Contents/Resources/AppIcon.icns" \
        "Contents/Resources/UMA-M4-N-Provenance.plist" \
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

readonly binary_strings="$package_root/binary-strings.txt"
/usr/bin/strings -a "$contents/MacOS/$PRODUCT" > "$binary_strings"
if /usr/bin/grep -E -q \
    "$production_forbidden|usage\.list|/v2/tasks?|BEGIN [A-Z ]*PRIVATE KEY|Bearer [A-Za-z0-9._-]{20,}" \
    "$binary_strings"; then
    printf '%s\n' "Package executable retained rejected route or private material." >&2
    exit 1
fi

readonly dependency_audit="$package_root/dependencies.txt"
/usr/bin/otool -L "$contents/MacOS/$PRODUCT" > "$dependency_audit"
if /usr/bin/awk 'NR > 1 {print $1}' "$dependency_audit" \
    | /usr/bin/grep -Ev '^(/System/Library/|/usr/lib/)' \
    | /usr/bin/grep -q .; then
    printf '%s\n' "Package contains a non-system dependency." >&2
    exit 1
fi

readonly executable_sha256="$(
    /usr/bin/shasum -a 256 "$contents/MacOS/$PRODUCT" \
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

printf 'PACKAGED output=%s commit=%s archive_sha256=%s executable_sha256=%s manifest_sha256=%s version=%s build=%s bundle_id=%s status=%s\n' \
    "$output" \
    "$commit" \
    "$archive_sha256" \
    "$executable_sha256" \
    "$manifest_sha256" \
    "$MARKETING_VERSION" \
    "$build_number" \
    "$BUNDLE_ID" \
    "M4-CLOSED-NO-SOURCE"
