#!/usr/bin/env bash
# Build the commit-exact, Developer-ID-signed M5RMX Safari preflight.
set -euo pipefail

readonly ROOT="$(cd "$(dirname "$0")/.." && pwd)"
commit=""
output=""
identity=""
build="202608170001"

usage() {
    printf '%s\n' \
        "Usage: $0 --commit <40-hex-sha> --output <exact-path> --signing-identity <Developer ID Application identity> [--build <12-digit-number>]"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --commit) commit="${2:-}"; shift 2 ;;
        --output) output="${2:-}"; shift 2 ;;
        --signing-identity) identity="${2:-}"; shift 2 ;;
        --build) build="${2:-}"; shift 2 ;;
        *) usage >&2; exit 2 ;;
    esac
done

[[ "$commit" =~ ^[0-9a-f]{40}$ \
    && "$build" =~ ^[0-9]{12}$ \
    && -n "$output" \
    && -n "$identity" \
    && "$identity" != "-" ]] || { usage >&2; exit 2; }

exec "$ROOT/script/package_uma_m5_g2.sh" \
    --commit "$commit" \
    --build "$build" \
    --phase m5rmx-safari-preflight \
    --output "$output" \
    --signing-identity "$identity"
