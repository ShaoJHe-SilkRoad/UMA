#!/usr/bin/env bash
# Runs the Swift test suite with the toolchain overrides this checkout requires.
#
# Command Line Tools 27.0 moved three things that a bare `swift test` still
# expects to resolve on its own:
#
#   * the default SDK selection no longer resolves the SwiftUI macro plugin, so
#     the SDK is pinned to the same version script/package_uma_m5_g2.sh uses;
#   * libTestingMacros.dylib moved into a plugins subdirectory the build system
#     does not search, so it is loaded explicitly;
#   * Testing.framework and lib_TestingInterop.dylib are no longer on any
#     default runtime search path, and SIP strips DYLD_FRAMEWORK_PATH from the
#     SwiftPM test helper, so both are added as link-time rpaths instead.
#
# The three moved components are located by search rather than by hardcoded
# path, so a later toolchain move fails with a specific message instead of an
# unrelated compiler or dyld error.
#
# Any argument is forwarded to `swift test`, for example:
#
#   script/test.sh --filter M5AUTOG1
set -euo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly CLT="/Library/Developer/CommandLineTools"
readonly SDK="$CLT/SDKs/MacOSX26.5.sdk"

fail() {
    printf '%s\n' "$@" >&2
    exit 1
}

[[ -d "$CLT" ]] || fail \
    "Missing Command Line Tools at $CLT."

[[ -d "$SDK" ]] || fail \
    "Missing pinned SDK: $SDK" \
    "The pinned SDK must stay in step with script/package_uma_m5_g2.sh." \
    "Update both together; do not let them drift."

readonly testing_macros="$(
    /usr/bin/find "$CLT/usr/lib/swift/host/plugins" \
        -name libTestingMacros.dylib -print -quit 2>/dev/null || true
)"
[[ -n "$testing_macros" ]] || fail \
    "Could not find libTestingMacros.dylib under $CLT/usr/lib/swift/host/plugins." \
    "Swift Testing macros cannot expand without it and every @Test fails to compile."

readonly testing_framework="$(
    /usr/bin/find "$CLT" -maxdepth 5 -type d \
        -name Testing.framework -print -quit 2>/dev/null || true
)"
[[ -n "$testing_framework" ]] || fail \
    "Could not find Testing.framework under $CLT." \
    "Test bundles cannot link or load without it."
readonly framework_dir="$(dirname "$testing_framework")"

readonly testing_interop="$(
    /usr/bin/find "$CLT" -maxdepth 6 \
        -name lib_TestingInterop.dylib -print -quit 2>/dev/null || true
)"
[[ -n "$testing_interop" ]] || fail \
    "Could not find lib_TestingInterop.dylib under $CLT." \
    "Testing.framework links it through @rpath and will fail to load."
readonly interop_dir="$(dirname "$testing_interop")"

export SDKROOT="$SDK"
exec /usr/bin/xcrun swift test \
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
