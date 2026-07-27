#!/usr/bin/env bash
# Builds and audits one immutable, commit-exact UMA 0.11 manual-test package.
set -euo pipefail

readonly REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
readonly PRODUCT="CodexUsageMonitor"
readonly MARKETING_VERSION="0.11"
readonly BUNDLE_ID="com.kevinchen.CodexUsageMonitor"
readonly DEFAULT_BUILD="202607270002"

usage() {
    printf '%s\n' \
        "Usage: $0 --commit <40-hex-sha> [--build <12-digit-number>] --output /private/tmp/uma-0.11-manual-<short-commit>/UMA.app"
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
readonly short_commit="${commit:0:12}"
readonly expected_output="/private/tmp/uma-0.11-manual-$short_commit/UMA.app"
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
[[ "$(cd /private/tmp && pwd -P)" == "$(cd "$(dirname "$output_parent")" && pwd -P)" ]] || {
    printf '%s\n' "Refusing a package parent outside canonical /private/tmp." >&2
    exit 2
}

git -C "$REPO_ROOT" cat-file -e "$commit^{commit}"
readonly package_root="/private/tmp/uma-0.11-manual-package-$commit"
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
    "$output_parent" \
    "$source_root" \
    "$home_root" \
    "$tmp_root" \
    "$cache_root" \
    "$config_root" \
    "$security_root"
readonly canonical_output_parent="$(cd "$output_parent" && pwd -P)"
[[ "$canonical_output_parent" == "/private/tmp/$(basename "$output_parent")" ]] || {
    printf 'Refusing redirected package parent %s\n' "$canonical_output_parent" >&2
    exit 2
}

git -C "$REPO_ROOT" archive --format=tar --output="$source_archive" "$commit"
tar -xf "$source_archive" -C "$source_root"
readonly archive_sha256="$(
    /usr/bin/shasum -a 256 "$source_archive" | /usr/bin/awk '{print $1}'
)"
[[ -f "$source_root/Package.swift" && -f "$source_root/Assets/AppIcon.icns" ]] || {
    printf '%s\n' "Commit archive is incomplete." >&2
    exit 1
}

export HOME="$home_root"
export TMPDIR="$tmp_root"
export CLANG_MODULE_CACHE_PATH="$cache_root/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$cache_root/swiftpm"
readonly swift_options=(
    --disable-sandbox
    --disable-keychain
    --disable-netrc
    --manifest-cache local
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
install -m 644 "$source_root/Assets/AppIcon.icns" "$contents/Resources/AppIcon.icns"

cat > "$contents/Resources/UMA-Stability-Provenance.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Revision</key><string>$commit</string>
<key>SourceArchiveSHA256</key><string>$archive_sha256</string>
<key>SourceState</key><string>commit-exact</string>
<key>TypographyDecision</key><string>CLAUDE TYPOGRAPHY FALLBACK USED</string>
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
/usr/bin/plutil -lint "$contents/Resources/UMA-Stability-Provenance.plist" >/dev/null
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
    \( -iname '*.ttf' -o -iname '*.otf' -o -iname '*.ttc' -o -iname '*.woff' \
       -o -iname '*.woff2' -o -iname '*.json' -o -iname '*.sqlite*' \
       -o -iname '*.log' -o -iname '*.png' -o -iname '*.jpg' \) \
    -print -quit | /usr/bin/grep -q .; then
    printf '%s\n' "Package contains a prohibited font, fixture, record, log, or evidence file." >&2
    exit 1
fi
if /usr/bin/strings -a "$contents/MacOS/$PRODUCT" \
    | /usr/bin/grep -E -i 'Claude\.app|AnthropicSans|BEGIN [A-Z ]*PRIVATE KEY|Bearer [A-Za-z0-9._-]{20,}' \
    >/dev/null; then
    printf '%s\n' "Package executable contains a prohibited font dependency or secret-like material." >&2
    exit 1
fi
if /usr/bin/otool -L "$contents/MacOS/$PRODUCT" \
    | /usr/bin/tail -n +2 \
    | /usr/bin/awk '{print $1}' \
    | /usr/bin/grep -Ev '^(/System/|/usr/lib/)' \
    | /usr/bin/grep -q .; then
    printf '%s\n' "Package executable contains a non-system dependency." >&2
    exit 1
fi

readonly actual_files="$(
    cd "$output"
    /usr/bin/find . -type f -print | LC_ALL=C /usr/bin/sort
)"
readonly expected_files="$(
    printf '%s\n' \
        "./Contents/Info.plist" \
        "./Contents/MacOS/$PRODUCT" \
        "./Contents/Resources/AppIcon.icns" \
        "./Contents/Resources/UMA-Stability-Provenance.plist" \
        "./Contents/_CodeSignature/CodeResources" \
        | LC_ALL=C /usr/bin/sort
)"
[[ "$actual_files" == "$expected_files" ]] || {
    printf '%s\n' "Package file allowlist mismatch." >&2
    printf '%s\n' "$actual_files" >&2
    exit 1
}

readonly executable_sha256="$(
    /usr/bin/shasum -a 256 "$contents/MacOS/$PRODUCT" | /usr/bin/awk '{print $1}'
)"
readonly manifest_digest="$(
    cd "$output"
    while IFS= read -r file; do
        mode="$(/usr/bin/stat -f '%Lp' "$file")"
        digest="$(/usr/bin/shasum -a 256 "$file" | /usr/bin/awk '{print $1}')"
        printf '%s %s %s\n' "$mode" "$digest" "$file"
    done < <(/usr/bin/find . -type f -print | LC_ALL=C /usr/bin/sort)
)"; readonly manifest_sha256="$(
    printf '%s\n' "$manifest_digest" | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}'
)"

printf 'PACKAGED output=%s commit=%s archive_sha256=%s executable_sha256=%s manifest_sha256=%s version=%s build=%s bundle_id=%s\n' \
    "$output" \
    "$commit" \
    "$archive_sha256" \
    "$executable_sha256" \
    "$manifest_sha256" \
    "$MARKETING_VERSION" \
    "$build_number" \
    "$BUNDLE_ID"
