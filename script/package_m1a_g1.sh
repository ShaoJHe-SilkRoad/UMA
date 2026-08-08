#!/usr/bin/env bash
# Packages a one-off, local-only M1A-G1 evidence app. It never overwrites an
# installed application, signs with a developer identity, or accesses a live
# Codex account itself.
set -euo pipefail

readonly ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
readonly PRODUCT="CodexUsageMonitor"
readonly BUNDLE_PREFIX="com.silkrd.uma.m1a-g1.evidence."

usage() {
    printf '%s\n' "Usage: $0 --output <temporary.app> --bundle-id <unique-id> --build <number>"
}

output=""
bundle_id=""
build_number=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --output) output="${2:-}"; shift 2 ;;
        --bundle-id) bundle_id="${2:-}"; shift 2 ;;
        --build) build_number="${2:-}"; shift 2 ;;
        *) usage >&2; exit 2 ;;
    esac
done

[[ "$output" = /* && "$output" == */"$PRODUCT".app ]] || { usage >&2; exit 2; }
case "$output" in
    "$ROOT_DIR"/.build/m1a-g1-package/*|/private/tmp/codexusage-m1a-g1-package/*) ;;
    *) printf '%s\n' "Refusing output outside the authorized M1A-G1 package locations." >&2; exit 2 ;;
esac
[[ ! -e "$output" && ! -L "$output" ]] || { printf '%s\n' "Refusing to overwrite an existing package." >&2; exit 2; }
[[ "$bundle_id" == "$BUNDLE_PREFIX"* ]] || { printf '%s\n' "Bundle ID must use the M1A-G1 evidence namespace." >&2; exit 2; }
[[ "$bundle_id" =~ ^[A-Za-z0-9.-]+$ && "$build_number" =~ ^[0-9]{8,20}$ ]] || { usage >&2; exit 2; }

readonly home_root="$ROOT_DIR/.build/m1a-g1-home"
readonly tmp_root="$ROOT_DIR/.build/m1a-g1-tmp"
readonly scratch_root="$ROOT_DIR/.build/m1a-g1-scratch/package"
readonly clang_cache_root="$ROOT_DIR/.build/m1a-g1-clang-cache"
readonly swiftpm_cache_root="$ROOT_DIR/.build/m1a-g1-swiftpm-cache"
readonly evidence_root="$ROOT_DIR/.build/m1a-g1-evidence"
mkdir -p "$(dirname "$output")" "$home_root" "$tmp_root" "$scratch_root" "$clang_cache_root" "$swiftpm_cache_root" "$evidence_root" "$home_root/config" "$home_root/security"

export HOME="$home_root"
export TMPDIR="$tmp_root"
export CLANG_MODULE_CACHE_PATH="$clang_cache_root"
export SWIFTPM_MODULECACHE_OVERRIDE="$swiftpm_cache_root"
swift_options=(
    --disable-sandbox
    --disable-keychain
    --disable-netrc
    --manifest-cache local
    --scratch-path "$scratch_root"
    --cache-path "$swiftpm_cache_root"
    --config-path "$home_root/config"
    --security-path "$home_root/security"
)
cd "$ROOT_DIR"

/usr/bin/xcrun swift build "${swift_options[@]}" --product "$PRODUCT"
binary_path="$(/usr/bin/xcrun swift build "${swift_options[@]}" --show-bin-path)/$PRODUCT"
[[ -x "$binary_path" ]] || { printf '%s\n' "Expected product was not built." >&2; exit 1; }

contents="$output/Contents"
mkdir -p "$contents/MacOS" "$contents/Resources"
install -m 755 "$binary_path" "$contents/MacOS/$PRODUCT"
install -m 644 "$ROOT_DIR/Assets/AppIcon.icns" "$contents/Resources/AppIcon.icns"

cat > "$contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDisplayName</key><string>Codex Usage Monitor M1A-G1 Evidence</string>
<key>CFBundleExecutable</key><string>$PRODUCT</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleIdentifier</key><string>$bundle_id</string>
<key>CFBundleName</key><string>Codex Usage Monitor M1A-G1 Evidence</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.0.0-m1a-g1</string>
<key>CFBundleVersion</key><string>$build_number</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST

plutil -lint "$contents/Info.plist" >/dev/null
xattr -cr "$output"
codesign --force --sign - "$output"
xattr -cr "$output"
codesign --verify --deep --strict --verbose=2 "$output"
printf 'PACKAGED product=%s output=%s bundle_id=%s build=%s\n' "$PRODUCT" "$output" "$bundle_id" "$build_number"
