#!/bin/bash
# Turn an unsigned AUV release candidate into the notarized DMG (the main
# download: open it, drag AUV onto Applications) and ZIP that are published.
#
# It adds what the release candidate does not carry and every Mac needs:
#   - Contents/embedded.provisionprofile: the app's entitlements name its app ID
#     and team, which macOS allows only with this profile. Without it, any Mac
#     that has not installed the profile some other way refuses to launch AUV
#     ("cannot be opened"), while codesign, spctl and notarization all pass.
#   - Contents/Library/SafariBridge/UMA Safari Bridge.app: the notarized Bridge
#     build this AUV is pinned to, which AUV installs for Claude's exact sync.
#
# Usage:
#   script/sign_auv_mac_release.sh --rc <uma-0.18-rc-… folder> --version 0.18.6 --build 2026111501 \
#       --bridge <uma-safari-host-…-production-… folder> --profile ~/Downloads/UMA_Developer_ID.provisionprofile \
#       --entitlements <signing-entitlements.plist>
set -euo pipefail

IDENTITY="Developer ID Application: SHAOTING HE (C6TUZVJ6SJ)"
NOTARY_PROFILE="UMA-notary"
PACKAGES="/Volumes/HE/DEV/UMA/Packages"
rc= version= build= bridge_dir= profile= entitlements=
while [[ $# -gt 0 ]]; do
  case "$1" in
    --rc) rc="$2"; shift 2;;
    --version) version="$2"; shift 2;;
    --build) build="$2"; shift 2;;
    --bridge) bridge_dir="$2"; shift 2;;
    --profile) profile="$2"; shift 2;;
    --entitlements) entitlements="$2"; shift 2;;
    *) echo "unknown argument $1" >&2; exit 2;;
  esac
done
[[ -d "$rc/UMA.app" && -n "$version" && -n "$build" && -d "$bridge_dir/UMA Safari Bridge.app" && -f "$profile" && -f "$entitlements" ]] \
  || { echo "usage: see the top of this script" >&2; exit 2; }

repo="$(cd "$(dirname "$0")/.." && pwd)"
dmg_background="$repo/Configuration/DMG/background.tiff"
[[ -f "$dmg_background" ]] || { echo "missing $dmg_background (script/make_dmg_background.swift)" >&2; exit 2; }
plist() { /usr/libexec/PlistBuddy -c "Print :$2" "$1"; }
out="$PACKAGES/auv-mac-$version-$build-signed"
[[ ! -e "$out" ]] || { echo "$out already exists" >&2; exit 1; }
app="$out/UMA.app"
bridge_src="$bridge_dir/UMA Safari Bridge.app"

# The candidate must be the version and build asked for.
[[ "$(plist "$rc/UMA.app/Contents/Info.plist" CFBundleShortVersionString)" == "$version" ]] || { echo "RC is not $version" >&2; exit 1; }
[[ "$(plist "$rc/UMA.app/Contents/Info.plist" CFBundleVersion)" == "$build" ]] || { echo "RC is not build $build" >&2; exit 1; }

# The Bridge must be exactly the build and generation AUV is pinned to, notarized.
want_build="$(plist "$rc/UMA.app/Contents/Info.plist" UMASafariHostExtensionBuild)"
want_generation="$(plist "$rc/UMA.app/Contents/Info.plist" UMASafariHostRuntimeGenerationID)"
[[ "$(plist "$bridge_src/Contents/Info.plist" CFBundleVersion)" == "$want_build" ]] || { echo "Bridge build is not $want_build" >&2; exit 1; }
[[ "$(plist "$bridge_src/Contents/Info.plist" UMARuntimeGenerationID)" == "$want_generation" ]] || { echo "Bridge generation is not $want_generation" >&2; exit 1; }
xcrun stapler validate "$bridge_src" >/dev/null || { echo "Bridge is not notarized and stapled" >&2; exit 1; }

# The profile must be the one for this app ID.
want_app_id="$(codesign -d --entitlements - --xml "$rc/UMA.app" 2>/dev/null | plutil -extract 'com\.apple\.application-identifier' raw - 2>/dev/null \
  || plutil -extract 'com\.apple\.application-identifier' raw "$entitlements")"
profile_app_id="$(security cms -D -i "$profile" | plutil -extract 'Entitlements.com\.apple\.application-identifier' raw -)"
[[ "$profile_app_id" == "$want_app_id" ]] || { echo "profile is for $profile_app_id, not $want_app_id" >&2; exit 1; }

mkdir -p "$out"
ditto "$rc/UMA.app" "$app"
cp "$entitlements" "$out/signing-entitlements.plist"
xattr -cr "$app"
cp "$profile" "$app/Contents/embedded.provisionprofile"
chmod 644 "$app/Contents/embedded.provisionprofile"
mkdir -p "$app/Contents/Library/SafariBridge"
ditto "$bridge_src" "$app/Contents/Library/SafariBridge/UMA Safari Bridge.app"
codesign --verify --deep --strict "$app/Contents/Library/SafariBridge/UMA Safari Bridge.app"

for helper in ClaudeStatusLineRelay HESectoriumControl; do
  codesign --force --options runtime --timestamp --sign "$IDENTITY" --identifier "$helper" "$app/Contents/Helpers/$helper"
done
codesign --force --options runtime --timestamp --sign "$IDENTITY" --identifier com.silkrd.uma \
  --entitlements "$out/signing-entitlements.plist" "$app"
codesign --verify --deep --strict "$app"
echo "signed $app"

cd "$out"
ditto -c -k --keepParent UMA.app notary.zip
xcrun notarytool submit notary.zip --keychain-profile "$NOTARY_PROFILE" --wait | tee notarization.txt
grep -q "status: Accepted" notarization.txt || { echo "notarization was not accepted" >&2; exit 1; }
xcrun stapler staple UMA.app
rm notary.zip
zip_name="AUV_Mac_${version}_Universal.zip"
ditto -c -k --keepParent UMA.app "$zip_name"

check="$(mktemp -d)"
ditto -x -k "$zip_name" "$check"
xattr -w com.apple.quarantine "0081;$(printf %x "$(date +%s)");Safari;" "$check/UMA.app"
spctl -a -vv -t exec "$check/UMA.app"
test -f "$check/UMA.app/Contents/embedded.provisionprofile"
spctl -a -vv -t exec "$check/UMA.app/Contents/Library/SafariBridge/UMA Safari Bridge.app"
rm -rf "$check"

# The DMG holds the stapled app and a shortcut to Applications. It is signed,
# notarized and stapled itself, so it opens without a warning even offline.
# Its window shows UMA.app on the left and Applications on the right, with an
# arrow and a hint drawn on the background: Finder lays that out on a writable
# copy, which is then compressed.
dmg_name="AUV_Mac_${version}_Universal.dmg"
volume="AUV $version"
[[ ! -e "/Volumes/$volume" ]] || { echo "/Volumes/$volume is already mounted; eject it first" >&2; exit 1; }
stage="$(mktemp -d)"
ditto UMA.app "$stage/UMA.app"
ln -s /Applications "$stage/Applications"
mkdir "$stage/.background"
cp "$dmg_background" "$stage/.background/background.tiff"
app_mb=$(( $(du -sm "$stage" | cut -f1) + 20 ))
hdiutil create -volname "$volume" -srcfolder "$stage" -fs HFS+ -format UDRW -size "${app_mb}m" -ov layout.dmg >/dev/null
rm -rf "$stage"
hdiutil attach -readwrite -noverify -noautoopen layout.dmg >/dev/null
osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$volume"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 860, 548}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 128
    set text size of viewOptions to 13
    set background picture of viewOptions to file ".background:background.tiff"
    set position of item "UMA.app" of container window to {165, 185}
    set position of item "Applications" of container window to {495, 185}
    close
    open
    update without registering applications
    delay 2
    close
  end tell
end tell
APPLESCRIPT
sync
test -f "/Volumes/$volume/.DS_Store" || { echo "Finder did not save the window layout" >&2; exit 1; }
hdiutil detach "/Volumes/$volume" >/dev/null
hdiutil convert layout.dmg -format UDZO -imagekey zlib-level=9 -ov -o "$dmg_name" >/dev/null
rm -f layout.dmg
codesign --force --timestamp --sign "$IDENTITY" "$dmg_name"
xcrun notarytool submit "$dmg_name" --keychain-profile "$NOTARY_PROFILE" --wait | tee dmg-notarization.txt
grep -q "status: Accepted" dmg-notarization.txt || { echo "DMG notarization was not accepted" >&2; exit 1; }
xcrun stapler staple "$dmg_name"

check="$(mktemp -d)"
cp "$dmg_name" "$check/"
xattr -w com.apple.quarantine "0081;$(printf %x "$(date +%s)");Safari;" "$check/$dmg_name"
spctl -a -vv -t open --context context:primary-signature "$check/$dmg_name"
mnt="$(mktemp -d)"
hdiutil attach -nobrowse -readonly -mountpoint "$mnt" "$check/$dmg_name" >/dev/null
spctl -a -vv -t exec "$mnt/UMA.app"
test -f "$mnt/UMA.app/Contents/embedded.provisionprofile"
[[ "$(readlink "$mnt/Applications")" == "/Applications" ]]
hdiutil detach "$mnt" >/dev/null
rm -rf "$check" "$mnt"

echo "notarization id (app): $(awk '/^  id:/{print $2; exit}' notarization.txt)"
echo "notarization id (dmg): $(awk '/^  id:/{print $2; exit}' dmg-notarization.txt)"
for f in "$dmg_name" "$zip_name"; do echo "$f bytes: $(stat -f %z "$f")"; shasum -a 256 "$f"; done
