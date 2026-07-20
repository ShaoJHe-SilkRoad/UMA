#!/usr/bin/env bash
# Build an immutable UMA 0.9 P2 review candidate from exactly one Git commit.
set -euo pipefail

readonly REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
readonly PRODUCT="CodexUsageMonitor"
readonly BUNDLE_PREFIX="com.kevinchen.CodexUsageMonitor.uma0.9.p2."

usage() {
    printf '%s\n' "Usage: $0 --commit <40-hex-sha> --output </private/tmp/codexusage-m1a-g2-dbg-c-p2-package/.../CodexUsageMonitor.app> --bundle-id <id> --build <number>"
}

commit=""
output=""
bundle_id=""
build_number=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --commit) commit="${2:-}"; shift 2 ;;
        --output) output="${2:-}"; shift 2 ;;
        --bundle-id) bundle_id="${2:-}"; shift 2 ;;
        --build) build_number="${2:-}"; shift 2 ;;
        *) usage >&2; exit 2 ;;
    esac
done

[[ "$commit" =~ ^[0-9a-f]{40}$ ]] || { usage >&2; exit 2; }
[[ "$build_number" =~ ^[0-9]{8,20}$ ]] || { usage >&2; exit 2; }
[[ "$bundle_id" == "$BUNDLE_PREFIX"* && "$bundle_id" =~ ^[A-Za-z0-9.-]+$ ]] || { usage >&2; exit 2; }
[[ "$output" = /private/tmp/codexusage-m1a-g2-dbg-c-p2-package/*/"$PRODUCT".app ]] || { usage >&2; exit 2; }
[[ ! -e "$output" && ! -L "$output" ]] || { printf '%s\n' "Refusing to overwrite candidate." >&2; exit 2; }
git -C "$REPO_ROOT" cat-file -e "$commit^{commit}"

readonly build_root="${output%/$PRODUCT.app}"
readonly source_root="$build_root/source"
readonly archive="$build_root/source-$commit.tar"
readonly swift_root="$build_root/swift"
readonly home_root="$build_root/home"
mkdir -p "$source_root" "$home_root/config" "$home_root/security" "$home_root/cache" "$home_root/tmp"
git -C "$REPO_ROOT" archive --format=tar --output="$archive" "$commit"
tar -xf "$archive" -C "$source_root"
archive_sha256="$(/usr/bin/shasum -a 256 "$archive" | /usr/bin/awk '{print $1}')"

export HOME="$home_root"
export TMPDIR="$home_root/tmp"
export CLANG_MODULE_CACHE_PATH="$home_root/cache/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$home_root/cache/swiftpm"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$SWIFTPM_MODULECACHE_OVERRIDE"
swift_options=(--disable-sandbox --disable-keychain --disable-netrc --manifest-cache local --scratch-path "$swift_root" --cache-path "$SWIFTPM_MODULECACHE_OVERRIDE" --config-path "$home_root/config" --security-path "$home_root/security")

pushd "$source_root" >/dev/null
/usr/bin/xcrun swift build "${swift_options[@]}" -c release --product "$PRODUCT"
binary_path="$(/usr/bin/xcrun swift build "${swift_options[@]}" -c release --show-bin-path)/$PRODUCT"
popd >/dev/null
[[ -x "$binary_path" ]] || { printf '%s\n' "Expected product was not built." >&2; exit 1; }

contents="$output/Contents"
font_resources="$source_root/Sources/CodexUsageUI/Resources/Fonts/Roboto"
mkdir -p "$contents/MacOS" "$contents/Resources/Fonts/Roboto"
install -m 755 "$binary_path" "$contents/MacOS/$PRODUCT"
install -m 644 "$source_root/Assets/AppIcon.icns" "$contents/Resources/AppIcon.icns"
for resource in Roboto-Regular.ttf Roboto-Medium.ttf Roboto-Bold.ttf OFL.txt PROVENANCE.md; do
    install -m 644 "$font_resources/$resource" "$contents/Resources/Fonts/Roboto/$resource"
done
{
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>'
    printf '%s\n' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    printf '%s\n' '<plist version="1.0"><dict>'
    printf '<key>Revision</key><string>%s</string>\n' "$commit"
    printf '<key>Build</key><string>%s</string>\n' "$build_number"
    printf '<key>SourceArchiveSHA256</key><string>%s</string>\n' "$archive_sha256"
    printf '%s\n' '</dict></plist>'
} > "$contents/Resources/UMA-P2-Provenance.plist"
{
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>'
    printf '%s\n' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    printf '%s\n' '<plist version="1.0"><dict>'
    printf '%s\n' '<key>CFBundleDisplayName</key><string>Codex Usage Monitor UMA 0.9 P2</string>'
    printf '%s\n' "<key>CFBundleExecutable</key><string>$PRODUCT</string>"
    printf '%s\n' '<key>CFBundleIconFile</key><string>AppIcon</string>'
    printf '%s\n' "<key>CFBundleIdentifier</key><string>$bundle_id</string>"
    printf '%s\n' '<key>CFBundleName</key><string>Codex Usage Monitor UMA 0.9 P2</string>'
    printf '%s\n' '<key>CFBundlePackageType</key><string>APPL</string>'
    printf '%s\n' '<key>CFBundleShortVersionString</key><string>0.9-p2</string>'
    printf '%s\n' "<key>CFBundleVersion</key><string>$build_number</string>"
    printf '%s\n' '<key>LSMinimumSystemVersion</key><string>14.0</string>'
    printf '%s\n' '<key>LSUIElement</key><true/>'
    printf '%s\n' "<key>UMAReviewCommit</key><string>$commit</string>"
    printf '%s\n' '</dict></plist>'
} > "$contents/Info.plist"

/usr/bin/plutil -lint "$contents/Info.plist" >/dev/null
/usr/bin/plutil -lint "$contents/Resources/UMA-P2-Provenance.plist" >/dev/null
/usr/bin/xattr -cr "$output"
/usr/bin/codesign --force --sign - "$output"
/usr/bin/xattr -cr "$output"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$output"
printf 'PACKAGED output=%s revision=%s archive_sha256=%s build=%s\n' "$output" "$commit" "$archive_sha256" "$build_number"
