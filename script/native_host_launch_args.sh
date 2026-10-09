#!/usr/bin/env bash
# Shared by the real LaunchServices path and its offline argument regression.
# This file only builds argv; it never starts an app.
native_host_build_open_args() {
    local app="$1" output="$2" test_bundle="$3" filter="$4" capture_stage="$5" matrix_scene="${6:-}" matched_input="${7:-}" probe="${8:-}"
    NATIVE_HOST_OPEN_ARGS=(
        -W -n -F -a "$app"
        --stdout "$output/native-host-stdout.log"
        --stderr "$output/native-host-stderr.log"
        --env "UMA015_FOREGROUND_ACCEPTANCE_DIR=$output/window"
        --env "UMA015_NATIVE_HOST_BUNDLE_PATH=$app"
        --env "TZ=UTC"
    )
    if [[ -n "$capture_stage" ]]; then
        case "$capture_stage" in
            agents-initial|minimum-outer|benchmark-outer|wide-outer)
                NATIVE_HOST_OPEN_ARGS+=(--env "UMA015_NATIVE_CAPTURE_STAGE=$capture_stage") ;;
            *) printf 'Unsupported native capture stage.\n' >&2; return 2 ;;
        esac
    fi
    if [[ -n "$matrix_scene" ]]; then
        case "$matrix_scene" in
            en-light-*|en-dark-*|zh-light-*|zh-dark-*) ;;
            *) printf 'Unsupported native matrix scene.\n' >&2; return 2 ;;
        esac
        case "${matrix_scene#*-*-}" in
            zero|full|unknown|loading|longreset|overflow|normal) ;;
            *) printf 'Unsupported native matrix state.\n' >&2; return 2 ;;
        esac
        NATIVE_HOST_OPEN_ARGS+=(--env "UMA015_NATIVE_MATRIX_SCENE=$matrix_scene")
    fi
    if [[ -n "$matched_input" ]]; then
        case "$matched_input" in
            /Volumes/HE/DEV/TOSUMA/.thread-os-runtime/evidence/UMA-0150-UI-REDOX-THREADOS-01/*)
                if [[ ! -f "$matched_input/en.json" || ! -f "$matched_input/zh.json" ]]; then
                    printf 'Matched input files are missing.\n' >&2
                    return 2
                fi
                NATIVE_HOST_OPEN_ARGS+=(--env "UMA015_MATCHED_INPUT_DIR=$matched_input") ;;
            *) printf 'Matched input must stay in the private task evidence root.\n' >&2; return 2 ;;
        esac
    fi
    if [[ -n "$probe" ]]; then
        [[ "$probe" == "disclosure-axpress" || "$probe" == "fullscreen-two-window" || "$probe" == "fullscreen-control-no-delegate" || "$probe" == "fullscreen-timer-entry" || "$probe" == "full-timer-entry" ]] || {
            printf 'Unsupported native probe.\n' >&2; return 2
        }
        NATIVE_HOST_OPEN_ARGS+=(--env "UMA015_NATIVE_PROBE=$probe")
    fi
    NATIVE_HOST_OPEN_ARGS+=(
        --args --test-bundle-path "$test_bundle"
        --testing-library swift-testing --filter "$filter"
    )
}
