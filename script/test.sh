#!/usr/bin/env bash
# Runs the Swift test suite with one coherent Xcode compiler/SDK/runtime.
#
# Command Line Tools currently exposes a Swift 6.4 driver while the historical
# test helper pinned a macOS 26.5 SDK and loaded test support from the CLT tree.
# That mixed installation is not a supported compiler environment. The Apple
# Development test/package path already requires Xcode beta 27, so tests use
# that same developer directory, macOS SDK, Swift Testing macro plug-in,
# framework, and interop library as one atomic toolchain selection.
#
# Any argument is forwarded to `swift test`, for example:
#
#   script/test.sh --filter M5AUTOG1
set -euo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "${1:-}" == "--native-app-host" ]]; then
    shift
    exec /bin/bash "$REPO_ROOT/script/native_app_host.sh" "$@"
fi
readonly DEVELOPER_DIR_REQUIRED="/Applications/Xcode-beta.app/Contents/Developer"
readonly TOOLCHAIN="$DEVELOPER_DIR_REQUIRED/Toolchains/XcodeDefault.xctoolchain"
readonly SDK="$DEVELOPER_DIR_REQUIRED/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk"
readonly PLATFORM_DEVELOPER="$DEVELOPER_DIR_REQUIRED/Platforms/MacOSX.platform/Developer"

fail() {
    printf '%s\n' "$@" >&2
    exit 1
}

[[ -d "$DEVELOPER_DIR_REQUIRED" ]] || fail \
    "Missing required Xcode developer directory: $DEVELOPER_DIR_REQUIRED"

[[ -d "$SDK" ]] || fail \
    "Missing pinned SDK: $SDK" \
    "The deterministic test toolchain must remain coherent with the Apple Development package path."

readonly testing_macros="$(
    /usr/bin/find "$TOOLCHAIN/usr/lib/swift/host/plugins" \
        -name libTestingMacros.dylib -print -quit 2>/dev/null || true
)"
[[ -n "$testing_macros" ]] || fail \
    "Could not find libTestingMacros.dylib under the selected Xcode toolchain." \
    "Swift Testing macros cannot expand without it and every @Test fails to compile."

readonly testing_framework="$(
    /usr/bin/find "$PLATFORM_DEVELOPER" -maxdepth 5 -type d \
        -name Testing.framework -print -quit 2>/dev/null || true
)"
[[ -n "$testing_framework" ]] || fail \
    "Could not find Testing.framework under the selected Xcode macOS platform." \
    "Test bundles cannot link or load without it."
readonly framework_dir="$(dirname "$testing_framework")"

readonly testing_interop="$(
    /usr/bin/find "$PLATFORM_DEVELOPER" -maxdepth 6 \
        -name lib_TestingInterop.dylib -print -quit 2>/dev/null || true
)"
[[ -n "$testing_interop" ]] || fail \
    "Could not find lib_TestingInterop.dylib under the selected Xcode macOS platform." \
    "Testing.framework links it through @rpath and will fail to load."
readonly interop_dir="$(dirname "$testing_interop")"

export DEVELOPER_DIR="$DEVELOPER_DIR_REQUIRED"
export SDKROOT="$SDK"
swift_subcommand=test
if [[ "${1:-}" == "--native-build-tests" ]]; then
    shift
    swift_subcommand=build
    set -- --build-tests "$@"
fi
exec /usr/bin/xcrun swift "$swift_subcommand" \
    --package-path "$REPO_ROOT" \
    --disable-sandbox \
    --disable-keychain \
    --disable-netrc \
    --manifest-cache local \
    --sdk "$SDK" \
    -Xswiftc -sdk -Xswiftc "$SDK" \
    -Xswiftc -load-plugin-library -Xswiftc "$testing_macros" \
    -Xswiftc -F -Xswiftc "$framework_dir" \
    -Xlinker -rpath -Xlinker "$framework_dir" \
    -Xlinker -rpath -Xlinker "$interop_dir" \
    "$@"
