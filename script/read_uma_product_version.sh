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
  ReleaseCandidate.HostTeamIdentifier|ReleaseCandidate.ApplicationName|ReleaseCandidate.BundleIdentifier|ReleaseCandidate.BuildNumber|ReleaseCandidate.PackageStem|ReleaseCandidate.MinimumSystemVersion|ReleaseCandidate.FrozenHostBuild|ReleaseCandidate.FrozenHostExtensionVersion|ReleaseCandidate.FrozenHostRuntimeGenerationID|ReleaseCandidate.HostBundleIdentifier|ReleaseCandidate.HostExtensionBundleIdentifier|ReleaseCandidate.HostAppGroupIdentifier|Development.ApplicationName|Development.BundleIdentifier|Development.DefaultBuildNumber|Development.MarketingVersion|Development.PackageStem|FrozenProduction.MarketingVersion|FrozenProduction.SourceCommit|SafariCompatibility.CompanionMarketingVersion|SafariCompatibility.HostMarketingVersion|SafariCompatibility.ProtocolVersion)
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
  ReleaseCandidate.BuildNumber|ReleaseCandidate.FrozenHostBuild|Development.DefaultBuildNumber|SafariCompatibility.ProtocolVersion)
    [[ "$value" =~ ^[1-9][0-9]*$ ]] || exit 2
    ;;
  ReleaseCandidate.FrozenHostExtensionVersion|Development.MarketingVersion|FrozenProduction.MarketingVersion|SafariCompatibility.CompanionMarketingVersion|SafariCompatibility.HostMarketingVersion)
    [[ "$value" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 2
    ;;
  ReleaseCandidate.BundleIdentifier|ReleaseCandidate.HostBundleIdentifier|ReleaseCandidate.HostExtensionBundleIdentifier|ReleaseCandidate.HostAppGroupIdentifier|Development.BundleIdentifier)
    [[ "$value" =~ ^[A-Za-z0-9]+([.-][A-Za-z0-9]+)+$ ]] || exit 2
    ;;
  ReleaseCandidate.PackageStem|Development.PackageStem)
    [[ "$value" =~ ^[a-z0-9][a-z0-9.-]*$ ]] || exit 2
    ;;
  ReleaseCandidate.MinimumSystemVersion)
    [[ "$value" =~ ^[0-9]+\.[0-9]+$ ]] || exit 2
    ;;
  ReleaseCandidate.FrozenHostRuntimeGenerationID)
    [[ "$value" =~ ^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$ ]] || exit 2
    ;;
  ReleaseCandidate.HostTeamIdentifier)
    [[ "$value" =~ ^[A-Z0-9]{10}$ ]] || exit 2
    ;;
  FrozenProduction.SourceCommit)
    [[ "$value" =~ ^[0-9a-f]{40}$ ]] || exit 2
    ;;
esac
printf '%s\n' "$value"
