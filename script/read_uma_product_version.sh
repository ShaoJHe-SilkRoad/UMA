#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUTHORITY="$ROOT_DIR/Configuration/UMAProductVersion.plist"

[[ -f "$AUTHORITY" && ! -L "$AUTHORITY" ]] || {
  printf '%s\n' "UMA_VERSION_AUTHORITY_UNAVAILABLE" >&2
  exit 2
}
/usr/bin/plutil -lint "$AUTHORITY" >/dev/null
[[ "$(/usr/libexec/PlistBuddy -c 'Print :SchemaVersion' "$AUTHORITY")" == "1" ]] || {
  printf '%s\n' "UMA_VERSION_AUTHORITY_SCHEMA_UNSUPPORTED" >&2
  exit 2
}

case "${1:-}" in
  Development.ApplicationName|Development.BundleIdentifier|Development.DefaultBuildNumber|Development.MarketingVersion|Development.PackageStem|FrozenProduction.MarketingVersion|FrozenProduction.SourceCommit|SafariCompatibility.CompanionMarketingVersion|SafariCompatibility.HostMarketingVersion|SafariCompatibility.ProtocolVersion)
    path=":${1//./:}"
    ;;
  *)
    printf '%s\n' "UMA_VERSION_AUTHORITY_KEY_UNSUPPORTED" >&2
    exit 2
    ;;
esac

value="$(/usr/libexec/PlistBuddy -c "Print $path" "$AUTHORITY")"
[[ -n "$value" && "$value" != *$'\n'* ]] || {
  printf '%s\n' "UMA_VERSION_AUTHORITY_VALUE_INVALID" >&2
  exit 2
}

case "$1" in
  Development.DefaultBuildNumber|SafariCompatibility.ProtocolVersion)
    [[ "$value" =~ ^[1-9][0-9]*$ ]] || exit 2
    ;;
  Development.MarketingVersion|FrozenProduction.MarketingVersion|SafariCompatibility.CompanionMarketingVersion|SafariCompatibility.HostMarketingVersion)
    [[ "$value" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 2
    ;;
  Development.BundleIdentifier)
    [[ "$value" =~ ^[A-Za-z0-9]+([.-][A-Za-z0-9]+)+$ ]] || exit 2
    ;;
  Development.PackageStem)
    [[ "$value" =~ ^[a-z0-9][a-z0-9.-]*$ ]] || exit 2
    ;;
  FrozenProduction.SourceCommit)
    [[ "$value" =~ ^[0-9a-f]{40}$ ]] || exit 2
    ;;
esac
printf '%s\n' "$value"
