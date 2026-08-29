#!/usr/bin/env bash
# Seals already Accepted+stapled split artifacts; it never submits to Apple.
set -euo pipefail; umask 077
readonly ROOT="/Volumes/HE/DEV/UMA/Packages" APP_ID="com.silkrd.uma" HOST_ID="com.silkrd.uma.safarihost" EXTENSION_ID="com.silkrd.uma.ClaudeBrowserCompanion" TEAM="C6TUZVJ6SJ"
package= submission= status=
while [[ $# -gt 0 ]]; do case "$1" in --package) package="${2:-}"; shift 2;; --submission-id) submission="${2:-}"; shift 2;; --notary-status) status="${2:-}"; shift 2;; *) exit 2;; esac; done
[[ "$package" == "$ROOT"/uma-0.13-production-* && -d "$package" && ! -L "$package" && "$submission" =~ ^[0-9a-fA-F-]{36}$ && "$status" == Accepted ]] || exit 2
app="$package/UMA_0.13.0.app"; host="$package/UMA Safari Bridge.app"; appex="$host/Contents/PlugIns/ClaudeBrowserCompanion.appex"; pre="$package/UMA-0.13.0-pre-notary-provenance.plist"
[[ -d "$app" && -d "$host" && -d "$appex" && -f "$pre" ]] || exit 1
[[ "$(shasum -a 256 "$package/UMA-0.13.0-split-notary.zip"|awk '{print $1}')" == "$(/usr/libexec/PlistBuddy -c 'Print :notaryArchiveSHA256' "$pre")" ]] || { echo SUBMITTED_ARCHIVE_PROVENANCE_MISMATCH >&2; exit 1; }
codesign --verify --deep --strict --verbose=4 "$app"; codesign --verify --deep --strict --verbose=4 "$host"; xcrun stapler validate "$app"; xcrun stapler validate "$host"
app_gatekeeper="$(spctl --assess --type execute --verbose=4 "$app" 2>&1)"; host_gatekeeper="$(spctl --assess --type execute --verbose=4 "$host" 2>&1)"
printf '%s\n' "$app_gatekeeper" | grep -Fq 'source=Notarized Developer ID'; printf '%s\n' "$host_gatekeeper" | grep -Fq 'source=Notarized Developer ID'
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" == "$APP_ID" && "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$host/Contents/Info.plist")" == "$HOST_ID" && "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$appex/Contents/Info.plist")" == "$EXTENSION_ID" ]] || exit 1
bundle_hash(){ (cd "$1"; find . -mindepth 1 -print0 | LC_ALL=C sort -z | while IFS= read -r -d '' e; do [[ ! -L "$e" ]] || exit 1; [[ -d "$e" ]] && printf 'D\0%s\0%s\0' "$e" "$(stat -f %Lp "$e")" || printf 'F\0%s\0%s\0%s\0' "$e" "$(stat -f %Lp "$e")" "$(shasum -a 256 "$e"|awk '{print $1}')"; done) | shasum -a 256 | awk '{print $1}'; }
appzip="$package/UMA_0.13.0.zip"; hostzip="$package/UMA-Safari-Bridge.zip"; final="$package/UMA-0.13.0-production-provenance.plist"; [[ ! -e "$appzip" && ! -e "$hostzip" && ! -e "$final" ]] || exit 1
ditto -c -k --keepParent "$app" "$appzip"; ditto -c -k --keepParent "$host" "$hostzip"; cp "$pre" "$final"; plutil -replace schemaVersion -integer 2 "$final"; plutil -replace classification -string PRODUCTION_SPLIT_FINAL "$final"; plutil -insert appleSubmissionID -string "$submission" "$final"; plutil -insert notarizationStatus -string Accepted "$final"; plutil -insert finalAppBundleSHA256 -string "$(bundle_hash "$app")" "$final"; plutil -insert finalHostBundleSHA256 -string "$(bundle_hash "$host")" "$final"; plutil -insert finalExtensionBundleSHA256 -string "$(bundle_hash "$appex")" "$final"; plutil -insert appArchiveSHA256 -string "$(shasum -a 256 "$appzip"|awk '{print $1}')" "$final"; plutil -insert hostArchiveSHA256 -string "$(shasum -a 256 "$hostzip"|awk '{print $1}')" "$final"; printf 'PRODUCTION_SPLIT_SEALED path=%s\n' "$package"
