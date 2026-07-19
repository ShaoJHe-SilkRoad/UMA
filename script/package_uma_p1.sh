#!/usr/bin/env bash
# Builds one immutable UMA 0.9 P1 candidate. Final candidates are constructed
# directly from `git archive <commit>`; provisional candidates may be used for
# pre-commit validation but cannot be promoted by the final-entry helper.
set -euo pipefail

readonly REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
readonly PRODUCT="CodexUsageMonitor"
readonly BUNDLE_PREFIX="com.kevinchen.CodexUsageMonitor.uma0.9.p1."

usage() {
    printf '%s\n' "Usage: $0 (--commit <40-hex-sha> | --provisional-source-archive <tar> --provisional-archive-sha256 <64-hex>) --output <temporary/CodexUsageMonitor.app> --bundle-id <id> --build <number>"
}

commit=""
provisional_source_archive=""
provisional_archive_sha256=""
output=""
bundle_id=""
build_number=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --commit) commit="${2:-}"; shift 2 ;;
        --provisional-source-archive) provisional_source_archive="${2:-}"; shift 2 ;;
        --provisional-archive-sha256) provisional_archive_sha256="${2:-}"; shift 2 ;;
        --output) output="${2:-}"; shift 2 ;;
        --bundle-id) bundle_id="${2:-}"; shift 2 ;;
        --build) build_number="${2:-}"; shift 2 ;;
        *) usage >&2; exit 2 ;;
    esac
done

[[ "$build_number" =~ ^[0-9]{8,20}$ ]] || { usage >&2; exit 2; }
[[ "$bundle_id" == "$BUNDLE_PREFIX"* && "$bundle_id" =~ ^[A-Za-z0-9.-]+$ ]] || { usage >&2; exit 2; }
[[ "$output" = /* && "$output" == */"$PRODUCT".app ]] || { usage >&2; exit 2; }
case "$output" in
    "$REPO_ROOT"/.build/m1a-g2-dbg-c-p1-package/*|/private/tmp/codexusage-m1a-g2-dbg-c-p1-package/*) ;;
    *) printf '%s\n' "Refusing output outside P1-owned package locations." >&2; exit 2 ;;
esac
[[ ! -e "$output" && ! -L "$output" ]] || { printf '%s\n' "Refusing to overwrite an existing candidate." >&2; exit 2; }

readonly home_root="$REPO_ROOT/.build/m1a-g2-dbg-c-p1-home"
readonly tmp_root="$REPO_ROOT/.build/m1a-g2-dbg-c-p1-tmp"
readonly package_root="$REPO_ROOT/.build/m1a-g2-dbg-c-p1-scratch/package-$build_number"
readonly source_root="$package_root/source"
readonly swift_scratch_root="$package_root/swift"
readonly evidence_root="$REPO_ROOT/.build/m1a-g2-dbg-c-p1-evidence"
readonly clang_cache_root="$REPO_ROOT/.build/m1a-g2-dbg-c-p1-clang-cache"
readonly swiftpm_cache_root="$REPO_ROOT/.build/m1a-g2-dbg-c-p1-swiftpm-cache"
[[ ! -e "$package_root" && ! -L "$package_root" ]] || { printf '%s\n' "Refusing to reuse a P1 package scratch root." >&2; exit 2; }
mkdir -p "$(dirname "$output")" "$package_root" "$evidence_root" "$home_root" "$tmp_root" "$clang_cache_root" "$swiftpm_cache_root" "$home_root/config" "$home_root/security"

if [[ -n "$commit" && -z "$provisional_source_archive" && -z "$provisional_archive_sha256" ]]; then
    [[ "$commit" =~ ^[0-9a-f]{40}$ ]] || { usage >&2; exit 2; }
    git -C "$REPO_ROOT" cat-file -e "$commit^{commit}"
    source_archive="$evidence_root/commit-$commit-$build_number.tar"
    git -C "$REPO_ROOT" archive --format=tar --output="$source_archive" "$commit"
    revision="$commit"
elif [[ -z "$commit" && "$provisional_source_archive" = /* && "$provisional_archive_sha256" =~ ^[0-9a-f]{64}$ ]]; then
    case "$provisional_source_archive" in
        "$REPO_ROOT"/.build/m1a-g2-dbg-c-p1-evidence/*|/private/tmp/codexusage-m1a-g2-dbg-c-p1-evidence/*) ;;
        *) printf '%s\n' "Refusing provisional archive outside P1 evidence locations." >&2; exit 2 ;;
    esac
    [[ -f "$provisional_source_archive" ]] || { printf '%s\n' "Missing provisional P1 source archive." >&2; exit 2; }
    source_archive="$provisional_source_archive"
    revision="provisional-$provisional_archive_sha256"
else
    usage >&2
    exit 2
fi

archive_sha256="$(/usr/bin/shasum -a 256 "$source_archive" | /usr/bin/awk '{print $1}')"
[[ -z "$provisional_archive_sha256" || "$archive_sha256" == "$provisional_archive_sha256" ]] || { printf '%s\n' "Provisional P1 source archive hash mismatch." >&2; exit 2; }
mkdir -p "$source_root"
tar -xf "$source_archive" -C "$source_root"
[[ -f "$source_root/Package.swift" && -f "$source_root/Assets/AppIcon.icns" ]] || { printf '%s\n' "P1 archive is incomplete." >&2; exit 2; }
printf '%s\n' "$revision" > "$source_root/P1_SOURCE_COMMIT"
printf '%s\n' "$archive_sha256" > "$source_root/P1_SOURCE_ARCHIVE_SHA256"

export HOME="$home_root"
export TMPDIR="$tmp_root"
export CLANG_MODULE_CACHE_PATH="$clang_cache_root"
export SWIFTPM_MODULECACHE_OVERRIDE="$swiftpm_cache_root"
swift_options=(--disable-sandbox --disable-keychain --disable-netrc --manifest-cache local --scratch-path "$swift_scratch_root" --cache-path "$swiftpm_cache_root" --config-path "$home_root/config" --security-path "$home_root/security")

pushd "$source_root" >/dev/null
/usr/bin/xcrun swift build "${swift_options[@]}" -c release --product "$PRODUCT"
binary_path="$(/usr/bin/xcrun swift build "${swift_options[@]}" -c release --show-bin-path)/$PRODUCT"
popd >/dev/null
[[ -x "$binary_path" ]] || { printf '%s\n' "Expected product was not built." >&2; exit 1; }

contents="$output/Contents"
mkdir -p "$contents/MacOS" "$contents/Resources"
install -m 755 "$binary_path" "$contents/MacOS/$PRODUCT"
install -m 644 "$source_root/Assets/AppIcon.icns" "$contents/Resources/AppIcon.icns"
cat > "$contents/Resources/UMA-P1-Provenance.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Revision</key><string>$revision</string>
<key>Build</key><string>$build_number</string>
<key>SourceArchiveSHA256</key><string>$archive_sha256</string>
</dict></plist>
PLIST
cat > "$contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDisplayName</key><string>Codex Usage Monitor UMA 0.9 P1</string>
<key>CFBundleExecutable</key><string>$PRODUCT</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleIdentifier</key><string>$bundle_id</string>
<key>CFBundleName</key><string>Codex Usage Monitor UMA 0.9 P1</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.9-p1</string>
<key>CFBundleVersion</key><string>$build_number</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>UMAReviewCommit</key><string>$revision</string>
</dict></plist>
PLIST

/usr/bin/plutil -lint "$contents/Info.plist" >/dev/null
/usr/bin/plutil -lint "$contents/Resources/UMA-P1-Provenance.plist" >/dev/null
/usr/bin/xattr -cr "$output"
/usr/bin/codesign --force --sign - "$output"
/usr/bin/xattr -cr "$output"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$output"
printf 'PACKAGED product=%s output=%s revision=%s archive_sha256=%s bundle_id=%s build=%s\n' "$PRODUCT" "$output" "$revision" "$archive_sha256" "$bundle_id" "$build_number"
