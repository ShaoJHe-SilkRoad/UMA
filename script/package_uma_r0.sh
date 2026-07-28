#!/usr/bin/env bash
# Builds an immutable, commit-exact UMA 0.10.1 reconstruction package.
set -euo pipefail

readonly REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
readonly PRODUCT="CodexUsageMonitor"
readonly MARKETING_VERSION="0.10.1"
readonly BUNDLE_ID="com.kevinchen.CodexUsageMonitor"
readonly HISTORICAL_ACCEPTED_REVISION="a8c5ff23fdfb4652481b8b4d2447bcfb2d152cbd"
readonly RECONSTRUCTED_PARENT="f1da999cf518433d108867d14ea1476678911ebf"
readonly DEFAULT_BUILD="202607231820"

usage() {
    printf '%s\n' "Usage: $0 --commit <40-hex-sha> [--build <number>] --output /private/tmp/uma-r0-final-<commit>/UMA_0.10.1.app"
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
[[ "$output" == "/private/tmp/uma-r0-final-$commit/UMA_0.10.1.app" ]] || {
    printf '%s\n' "Refusing output outside the commit-owned UMA R0 package path." >&2
    exit 2
}
[[ ! -e "$output" && ! -L "$output" ]] || {
    printf '%s\n' "Refusing to overwrite an existing package." >&2
    exit 2
}

git -C "$REPO_ROOT" cat-file -e "$commit^{commit}"
[[ "$(git -C "$REPO_ROOT" rev-parse "$commit^")" == "$RECONSTRUCTED_PARENT" ]] || {
    printf '%s\n' "The reconstruction commit must directly descend from the recorded donor parent." >&2
    exit 2
}

readonly package_root="/private/tmp/uma-r0-package-$commit"
readonly source_root="$package_root/source"
readonly scratch_root="$package_root/swift"
readonly home_root="$package_root/home"
readonly tmp_root="$package_root/tmp"
readonly cache_root="$package_root/cache"
readonly config_root="$package_root/config"
readonly security_root="$package_root/security"
readonly source_archive="$package_root/source-$commit.tar"

[[ ! -e "$package_root" && ! -L "$package_root" ]] || {
    printf '%s\n' "Refusing to reuse the commit-owned package scratch path." >&2
    exit 2
}
mkdir -p "$(dirname "$output")" "$source_root" "$home_root" "$tmp_root" "$cache_root" "$config_root" "$security_root"

git -C "$REPO_ROOT" archive --format=tar --output="$source_archive" "$commit"
tar -xf "$source_archive" -C "$source_root"
readonly archive_sha256="$(/usr/bin/shasum -a 256 "$source_archive" | /usr/bin/awk '{print $1}')"
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
/usr/bin/xcrun swift build "${swift_options[@]}" -c release --product "$PRODUCT"
readonly binary_path="$(/usr/bin/xcrun swift build "${swift_options[@]}" -c release --show-bin-path)/$PRODUCT"
popd >/dev/null
[[ -x "$binary_path" ]] || {
    printf '%s\n' "Expected release executable is missing." >&2
    exit 1
}

readonly contents="$output/Contents"
mkdir -p "$contents/MacOS" "$contents/Resources"
install -m 755 "$binary_path" "$contents/MacOS/$PRODUCT"
install -m 644 "$source_root/Assets/AppIcon.icns" "$contents/Resources/AppIcon.icns"

cat > "$contents/Resources/UMA-R0-Provenance.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>HistoricalAcceptedBinaryRevision</key><string>$HISTORICAL_ACCEPTED_REVISION</string>
<key>ReconstructedSourceParent</key><string>$RECONSTRUCTED_PARENT</string>
<key>ReconstructedSourceCommit</key><string>$commit</string>
<key>SourceArchiveSHA256</key><string>$archive_sha256</string>
<key>SourceState</key><string>reconstructed-commit</string>
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
<key>UMAHistoricalAcceptedRevision</key><string>$HISTORICAL_ACCEPTED_REVISION</string>
<key>UMAReconstructedSourceParent</key><string>$RECONSTRUCTED_PARENT</string>
<key>UMAReviewCommit</key><string>$commit</string>
<key>UMASourceArchiveSHA256</key><string>$archive_sha256</string>
<key>UMASourceState</key><string>reconstructed-commit</string>
</dict></plist>
PLIST

/usr/bin/plutil -lint "$contents/Info.plist" >/dev/null
/usr/bin/plutil -lint "$contents/Resources/UMA-R0-Provenance.plist" >/dev/null
/usr/bin/xattr -cr "$output"
/usr/bin/codesign --force --sign - "$output"
/usr/bin/xattr -cr "$output"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$output"

readonly executable_sha256="$(/usr/bin/shasum -a 256 "$contents/MacOS/$PRODUCT" | /usr/bin/awk '{print $1}')"
printf 'PACKAGED output=%s commit=%s parent=%s archive_sha256=%s executable_sha256=%s version=%s build=%s bundle_id=%s\n' \
    "$output" "$commit" "$RECONSTRUCTED_PARENT" "$archive_sha256" "$executable_sha256" "$MARKETING_VERSION" "$build_number" "$BUNDLE_ID"
