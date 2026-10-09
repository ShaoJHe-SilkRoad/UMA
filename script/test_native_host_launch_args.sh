#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$root/script/native_host_launch_args.sh"
scratch="$(/usr/bin/mktemp -d /private/tmp/uma015-native-args.XXXXXX)"
trap 'rm -rf "$scratch"' EXIT
stub_open() { /usr/bin/printf '%s\n' "$@" > "$scratch/actual"; }
app="$scratch/UMA015NativeTestHost.app"
output="$scratch/evidence"
bundle="$scratch/CodexUsageUITests"
filter=attachedProductionWindowKeyboardAcceptance
for stage in '' agents-initial minimum-outer benchmark-outer wide-outer; do
    native_host_build_open_args "$app" "$output" "$bundle" "$filter" "$stage"
    stub_open "${NATIVE_HOST_OPEN_ARGS[@]}"
    {
        printf '%s\n' -W -n -F -a "$app"
        printf '%s\n' --stdout "$output/native-host-stdout.log"
        printf '%s\n' --stderr "$output/native-host-stderr.log"
        printf '%s\n' --env "UMA015_FOREGROUND_ACCEPTANCE_DIR=$output/window"
        printf '%s\n' --env "UMA015_NATIVE_HOST_BUNDLE_PATH=$app"
        printf '%s\n' --env "TZ=UTC"
        if [[ -n "$stage" ]]; then
            printf '%s\n' --env "UMA015_NATIVE_CAPTURE_STAGE=$stage"
        fi
        printf '%s\n' --args --test-bundle-path "$bundle" --testing-library swift-testing --filter "$filter"
    } > "$scratch/expected"
    /usr/bin/cmp "$scratch/expected" "$scratch/actual"
done
for scene in en-light-zero en-dark-full zh-light-unknown zh-dark-loading \
             en-light-longreset zh-dark-overflow; do
    native_host_build_open_args "$app" "$output" "$bundle" "$filter" agents-initial "$scene"
    stub_open "${NATIVE_HOST_OPEN_ARGS[@]}"
    /usr/bin/grep -Fx "UMA015_NATIVE_MATRIX_SCENE=$scene" "$scratch/actual" >/dev/null
done
native_host_build_open_args "$app" "$output" "$bundle" "$filter" agents-initial \
    en-light-normal /Volumes/HE/DEV/TOSUMA/.thread-os-runtime/evidence/UMA-0150-UI-REDOX-THREADOS-01/coder/repair-r9/matched-input-v2
stub_open "${NATIVE_HOST_OPEN_ARGS[@]}"
/usr/bin/grep -Fx 'UMA015_MATCHED_INPUT_DIR=/Volumes/HE/DEV/TOSUMA/.thread-os-runtime/evidence/UMA-0150-UI-REDOX-THREADOS-01/coder/repair-r9/matched-input-v2' "$scratch/actual" >/dev/null
if native_host_build_open_args "$app" "$output" "$bundle" "$filter" '' en-light-normal \
    /Volumes/HE/DEV/TOSUMA/.thread-os-runtime/evidence/UMA-0150-UI-REDOX-THREADOS-01/coder/repair-r15/missing-input-fixture \
    > "$scratch/missing.stdout" 2> "$scratch/missing.stderr"; then
    printf 'Missing matched fixture unexpectedly succeeded.\n' >&2
    exit 1
else
    status=$?
    [[ "$status" -eq 2 ]]
    /usr/bin/grep -Fx 'Matched input files are missing.' "$scratch/missing.stderr" >/dev/null
fi
if native_host_build_open_args "$app" "$output" "$bundle" "$filter" '' en-light-invalid \
    > "$scratch/invalid.stdout" 2> "$scratch/invalid.stderr"; then
    printf 'Invalid matrix state unexpectedly succeeded.\n' >&2
    exit 1
else
    status=$?
    [[ "$status" -eq 2 ]]
    /usr/bin/grep -Fx 'Unsupported native matrix state.' "$scratch/invalid.stderr" >/dev/null
fi
if native_host_build_open_args "$app" "$output" "$bundle" "$filter" unsupported-stage     > "$scratch/invalid.stdout" 2> "$scratch/invalid.stderr"; then
    printf 'Invalid capture stage unexpectedly succeeded.\n' >&2
    exit 1
else
    status=$?
    [[ "$status" -eq 2 ]]
    /usr/bin/grep -Fx 'Unsupported native capture stage.' "$scratch/invalid.stderr" >/dev/null
fi
for probe in disclosure-axpress fullscreen-two-window fullscreen-control-no-delegate fullscreen-timer-entry full-timer-entry; do
    native_host_build_open_args "$app" "$output" "$bundle" "$filter" '' '' '' "$probe"
    stub_open "${NATIVE_HOST_OPEN_ARGS[@]}"
    /usr/bin/grep -Fx "UMA015_NATIVE_PROBE=$probe" "$scratch/actual" >/dev/null
done
if native_host_build_open_args "$app" "$output" "$bundle" "$filter" '' '' '' unsupported-probe \
    > "$scratch/invalid.stdout" 2> "$scratch/invalid.stderr"; then
    printf 'Invalid native probe unexpectedly succeeded.\n' >&2
    exit 1
else
    status=$?
    [[ "$status" -eq 2 ]]
    /usr/bin/grep -Fx 'Unsupported native probe.' "$scratch/invalid.stderr" >/dev/null
fi
printf 'native host launch argv: 20 cases passed; no app launched\n'
