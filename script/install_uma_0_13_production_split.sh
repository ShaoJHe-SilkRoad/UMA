#!/usr/bin/env bash
# Installs only a sealed, notarized split release and preserves UMA 0.11 rollback.
set -euo pipefail; umask 077
readonly APP_ID="com.silkrd.uma" HOST_ID="com.silkrd.uma.safarihost" EXTENSION_ID="com.silkrd.uma.ClaudeBrowserCompanion" TEAM="C6TUZVJ6SJ" APP_GROUP="group.com.silkrd.uma.bridge"
readonly MUTABLE="/Users/juliushe/Desktop/UMA_0.13.0.app" HOST="$HOME/Applications/UMA Safari Bridge.app" ROLLBACK="/Users/juliushe/Desktop/UMA_0.11.app" ROLLBACK_SHA="88ffbb48de43253f7289fe038dff9d0b195e61398f969439ff5c8729ecbef91a"
readonly SWAP_SOURCE="$(cd "$(dirname "$0")/.." && pwd)/ProductionSigning/AtomicBundleSwap.swift" LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"
readonly CANONICAL_APPEX="$HOST/Contents/PlugIns/ClaudeBrowserCompanion.appex" OLD_COMBINED="$MUTABLE/Contents/PlugIns/ClaudeBrowserCompanion.appex"
package=
while [[ $# -gt 0 ]]; do case "$1" in --package) package="${2:-}"; shift 2;; *) exit 2;; esac; done
receipt="$package/UMA-0.13.0-production-provenance.plist"; [[ "$package" == /Volumes/HE/DEV/UMA/Packages/uma-0.13-production-* && -f "$receipt" && ! -L "$receipt" ]] || exit 2
plist(){ /usr/libexec/PlistBuddy -c "Print :$2" "$1"; }; [[ "$(plist "$receipt" classification)" == PRODUCTION_SPLIT_FINAL && "$(plist "$receipt" appBundleIdentifier)" == "$APP_ID" && "$(plist "$receipt" hostBundleIdentifier)" == "$HOST_ID" && "$(plist "$receipt" extensionBundleIdentifier)" == "$EXTENSION_ID" && "$(plist "$receipt" appGroupIdentifier)" == "$APP_GROUP" && "$(plist "$receipt" teamIdentifier)" == "$TEAM" ]] || exit 1
registered_paths(){ pluginkit -m -A -D -v -i "$EXTENSION_ID" | /usr/bin/awk -F '\t' -v id="$EXTENSION_ID" 'index($1, id "(") > 0 && NF >= 4 { print $4 }'; }
preexisting_registrations="$(registered_paths)"
while IFS= read -r registered; do
  [[ -z "$registered" || "$registered" == "$CANONICAL_APPEX" || "$registered" == "$OLD_COMBINED" ]] || { echo NONCANONICAL_PRODUCTION_COMPANION_REGISTRATION >&2; exit 1; }
done <<< "$preexisting_registrations"
[[ -d "$ROLLBACK" && ! -L "$ROLLBACK" ]]; rollback_exe="$(plist "$ROLLBACK/Contents/Info.plist" CFBundleExecutable)"; [[ "$(shasum -a 256 "$ROLLBACK/Contents/MacOS/$rollback_exe"|awk '{print $1}')" == "$ROLLBACK_SHA" ]] || { echo PROTECTED_ROLLBACK_MISMATCH >&2; exit 1; }
! pgrep -x CodexUsageMonitor >/dev/null && ! pgrep -x UMASafariBridgeHost >/dev/null || { echo PRODUCTION_INSTALL_REQUIRES_APPS_CLOSED >&2; exit 1; }
scratch="$(mktemp -d /private/tmp/uma-production-install.XXXXXX)"; trap 'rm -rf -- "$scratch"' EXIT HUP INT TERM
[[ "$(shasum -a 256 "$package/UMA_0.13.0.zip"|awk '{print $1}')" == "$(plist "$receipt" appArchiveSHA256)" && "$(shasum -a 256 "$package/UMA-Safari-Bridge.zip"|awk '{print $1}')" == "$(plist "$receipt" hostArchiveSHA256)" ]] || exit 1
ditto -x -k "$package/UMA_0.13.0.zip" "$scratch/app"; ditto -x -k "$package/UMA-Safari-Bridge.zip" "$scratch/host"; app="$scratch/app/UMA_0.13.0.app"; host="$scratch/host/UMA Safari Bridge.app"; appex="$host/Contents/PlugIns/ClaudeBrowserCompanion.appex"
[[ -d "$app" && ! -e "$app/Contents/PlugIns" && -d "$appex" && "$(plist "$app/Contents/Info.plist" CFBundleIdentifier)" == "$APP_ID" && "$(plist "$host/Contents/Info.plist" CFBundleIdentifier)" == "$HOST_ID" && "$(plist "$appex/Contents/Info.plist" CFBundleIdentifier)" == "$EXTENSION_ID" && "$(plist "$app/Contents/Info.plist" UMASafariHostRuntimeGenerationID)" == "$(plist "$host/Contents/Info.plist" UMARuntimeGenerationID)" && "$(plist "$host/Contents/Info.plist" UMARuntimeGenerationID)" == "$(plist "$appex/Contents/Info.plist" UMARuntimeGenerationID)" ]] || exit 1
bundle_hash(){ (cd "$1"; find . -mindepth 1 -print0 | LC_ALL=C sort -z | while IFS= read -r -d '' e; do [[ ! -L "$e" ]] || exit 1; [[ -d "$e" ]] && printf 'D\0%s\0%s\0' "$e" "$(stat -f %Lp "$e")" || printf 'F\0%s\0%s\0%s\0' "$e" "$(stat -f %Lp "$e")" "$(shasum -a 256 "$e"|awk '{print $1}')"; done) | shasum -a 256 | awk '{print $1}'; }
[[ "$(bundle_hash "$app")" == "$(plist "$receipt" finalAppBundleSHA256)" && "$(bundle_hash "$host")" == "$(plist "$receipt" finalHostBundleSHA256)" && "$(bundle_hash "$appex")" == "$(plist "$receipt" finalExtensionBundleSHA256)" ]] || { echo SEALED_BUNDLE_PROVENANCE_MISMATCH >&2; exit 1; }
codesign --verify --deep --strict --verbose=4 "$app"; codesign --verify --deep --strict --verbose=4 "$host"; xcrun stapler validate "$app"; xcrun stapler validate "$host"
app_gatekeeper="$(spctl --assess --type execute --verbose=4 "$app" 2>&1)"; host_gatekeeper="$(spctl --assess --type execute --verbose=4 "$host" 2>&1)"
printf '%s\n' "$app_gatekeeper" | grep -Fq 'source=Notarized Developer ID'; printf '%s\n' "$host_gatekeeper" | grep -Fq 'source=Notarized Developer ID'
mkdir -p "$HOME/Applications"; app_stage="$(mktemp -d /Users/juliushe/Desktop/.UMA-0.13.install.XXXXXX)"; host_stage="$(mktemp -d "$HOME/Applications/.UMA-Safari-Bridge.install.XXXXXX")"; ditto "$app" "$app_stage"; ditto "$host" "$host_stage"; swap="$scratch/ProductionAtomicBundleSwap"; xcrun swiftc "$SWAP_SOURCE" -o "$swap"
for pair in "$MUTABLE:$APP_ID" "$HOST:$HOST_ID"; do target="${pair%%:*}"; id="${pair#*:}"; [[ ! -L "$target" ]] || exit 1; [[ ! -e "$target" || "$(plist "$target/Contents/Info.plist" CFBundleIdentifier)" == "$id" ]] || exit 1; done
[[ ! -d "$OLD_COMBINED" || "$(plist "$OLD_COMBINED/Contents/Info.plist" CFBundleIdentifier)" == "$EXTENSION_ID" ]] || exit 1
[[ ! -d "$OLD_COMBINED" ]] || pluginkit -r "$OLD_COMBINED" >/dev/null 2>&1 || true
"$swap" "$host_stage" "$HOST"; "$swap" "$app_stage" "$MUTABLE"; "$LSREGISTER" -f "$HOST"; pluginkit -a "$HOST/Contents/PlugIns/ClaudeBrowserCompanion.appex"
postinstall_registrations="$(registered_paths)"
[[ "$postinstall_registrations" == "$CANONICAL_APPEX" ]] || { echo SINGLE_CANONICAL_COMPANION_REGISTRATION_NOT_PROVEN >&2; exit 1; }
codesign --verify --deep --strict --verbose=4 "$MUTABLE"; codesign --verify --deep --strict --verbose=4 "$HOST"; [[ "$(shasum -a 256 "$ROLLBACK/Contents/MacOS/$rollback_exe"|awk '{print $1}')" == "$ROLLBACK_SHA" ]] || { echo PROTECTED_ROLLBACK_MUTATED >&2; exit 1; }
rm -rf -- "$app_stage" "$host_stage"; printf 'PRODUCTION_SPLIT_INSTALLED mutable=%s host=%s human_extension_enablement_may_be_required=true\n' "$MUTABLE" "$HOST"
