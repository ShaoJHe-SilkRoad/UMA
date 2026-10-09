#!/usr/bin/env bash
# Build an isolated foreground app host for the SwiftPM test bundle. The normal
# script/test.sh path remains unchanged unless --native-app-host is explicit.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
toolchain="/Applications/Xcode-beta.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain"
helper="$toolchain/usr/libexec/swift/pm/swiftpm-testing-helper"
filter=""
scratch=""
prepare_only=false
while (($#)); do
    case "$1" in
        --prepare-only) prepare_only=true; shift ;;
        --filter) filter="${2:?missing filter}"; shift 2 ;;
        --scratch-path) scratch="${2:?missing scratch path}"; shift 2 ;;
        *) printf 'Unsupported native host argument: %s\n' "$1" >&2; exit 2 ;;
    esac
done
[[ "$filter" == "attachedProductionWindowKeyboardAcceptance" ]] || {
    printf 'Native host is restricted to the opt-in foreground acceptance test.\n' >&2
    exit 2
}
[[ -n "$scratch" && "$scratch" == /private/tmp/* ]] || {
    printf 'Native host requires an explicit /private/tmp scratch path.\n' >&2
    exit 2
}
[[ -f "$helper" ]] || { printf 'Missing selected SwiftPM test helper.\n' >&2; exit 2; }
output="${UMA015_FOREGROUND_ACCEPTANCE_DIR:?foreground output directory required}"
[[ "$output" == /Volumes/HE/DEV/TOSUMA/.thread-os-runtime/evidence/UMA-0150-UI-REDOX-THREADOS-01/* ]] || {
    printf 'Native host output must be under the private task evidence root.\n' >&2
    exit 2
}
mkdir -p "$output"

# Build the original SwiftPM test target using the same pinned compiler/SDK.
"$repo_root/script/test.sh" --native-build-tests --scratch-path "$scratch"
test_bundle="$scratch/out/Products/Debug/CodexUsageUITests.xctest/Contents/MacOS/CodexUsageUITests"
[[ -f "$test_bundle" ]] || { printf 'Built SwiftPM test bundle was not found.\n' >&2; exit 2; }
app="$output/host/UMA015NativeTestHost.app"
mkdir -p "$app/Contents/MacOS"
cp "$helper" "$app/Contents/MacOS/swiftpm-testing-helper"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.tosuma.uma015.native-test-host</string>
<key>CFBundleName</key><string>UMA015 Native Test Host</string>
<key>CFBundleExecutable</key><string>swiftpm-testing-helper</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
/usr/bin/plutil -lint "$app/Contents/Info.plist"
source_hash="$(/usr/bin/shasum -a 256 "$helper" | /usr/bin/awk '{print $1}')"
copied_hash="$(/usr/bin/shasum -a 256 "$app/Contents/MacOS/swiftpm-testing-helper" | /usr/bin/awk '{print $1}')"
[[ "$source_hash" == "$copied_hash" ]] || { printf 'Native host helper copy differs from selected toolchain.\n' >&2; exit 2; }
printf 'host_app=%s\ntest_bundle=%s\nhelper_sha256=%s\n' "$app" "$test_bundle" "$copied_hash" > "$output/native-host-build.txt"
if $prepare_only; then
    printf 'Native app host prepared without launch: %s\n' "$app"
    exit 0
fi

# LaunchServices gives the test helper an actual app identity. The helper still
# loads the original test bundle and test filter; all fixture assertions remain.
source "$repo_root/script/native_host_launch_args.sh"
native_host_build_open_args "$app" "$output" "$test_bundle" "$filter" \
    "${UMA015_NATIVE_CAPTURE_STAGE:-}" "${UMA015_NATIVE_MATRIX_SCENE:-}" \
    "${UMA015_MATCHED_INPUT_DIR:-}" "${UMA015_NATIVE_PROBE:-}"
set +e
/usr/bin/open "${NATIVE_HOST_OPEN_ARGS[@]}"
open_status=$?
set -e
printf 'open_wait_exit=%s\n' "$open_status" > "$output/native-host-launch-status.txt"
[[ "$open_status" -eq 0 ]] || exit "$open_status"
/usr/bin/python3 "$repo_root/script/native_host_result.py" \
    --stdout "$output/native-host-stdout.log" \
    --stderr "$output/native-host-stderr.log" \
    --lifecycle "$output/window/native-entry-host-lifecycle.json" \
    --readiness "$output/window/native-entry-host-readiness.json" \
    --expected-bundle "$app" \
    --case "$filter"
