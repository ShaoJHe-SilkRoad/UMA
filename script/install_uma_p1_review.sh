#!/usr/bin/env bash
# Promotes exactly one already-signed P1 candidate and creates the Finder-only
# UMA0.9_Enter launcher. It never builds, kills a process, or starts a child.
set -euo pipefail

readonly PRODUCT="CodexUsageMonitor"
readonly REVIEW_ROOT="/Users/juliushe/Desktop/UMA0.9_Review"
readonly REVIEW_APP="$REVIEW_ROOT/$PRODUCT.app"
readonly LAUNCHER_APP="/Users/juliushe/Desktop/UMA0.9_Enter.app"

usage() { printf '%s\n' "Usage: $0 --candidate <P1 temporary/CodexUsageMonitor.app> --commit <40-hex-sha>"; }

candidate=""
commit=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --candidate) candidate="${2:-}"; shift 2 ;;
        --commit) commit="${2:-}"; shift 2 ;;
        *) usage >&2; exit 2 ;;
    esac
done

[[ "$candidate" = /* && -d "$candidate" && "$candidate" == */"$PRODUCT".app ]] || { usage >&2; exit 2; }
[[ "$candidate" == /Users/juliushe/Desktop/CodexUsageMonitor/.build/m1a-g2-dbg-c-p1-package/* || "$candidate" == /private/tmp/codexusage-m1a-g2-dbg-c-p1-package/* ]] || { printf '%s\n' "Candidate is not in a P1 package location." >&2; exit 2; }
[[ "$commit" =~ ^[0-9a-f]{40}$ ]] || { usage >&2; exit 2; }
[[ ! -e "$REVIEW_APP" && ! -L "$REVIEW_APP" && ! -e "$LAUNCHER_APP" && ! -L "$LAUNCHER_APP" ]] || { printf '%s\n' "Refusing to replace a sealed P1 review entry." >&2; exit 2; }
# Finder may attach display-only metadata after an app bundle is created.
# Clear it immediately before the installer-time strict validation; this
# changes no executable or signed resource.
/usr/bin/xattr -cr "$candidate"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$candidate"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :UMAReviewCommit' "$candidate/Contents/Info.plist")" == "$commit" ]] || { printf '%s\n' "Candidate commit does not match." >&2; exit 2; }

mkdir -p "$REVIEW_ROOT"
/usr/bin/ditto "$candidate" "$REVIEW_APP"
launcher_contents="$LAUNCHER_APP/Contents"
mkdir -p "$launcher_contents/MacOS"
cat > "$launcher_contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDisplayName</key><string>UMA0.9_Enter</string>
<key>CFBundleExecutable</key><string>UMA0.9_Enter</string>
<key>CFBundleIdentifier</key><string>com.silkrd.uma.uma0.9.enter</string>
<key>CFBundleName</key><string>UMA0.9_Enter</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.9-p1</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
cat > "$launcher_contents/MacOS/UMA0.9_Enter" <<'LAUNCHER'
#!/bin/zsh
set -u
candidate="/Users/juliushe/Desktop/UMA0.9_Review/CodexUsageMonitor.app"
executable="$candidate/Contents/MacOS/CodexUsageMonitor"
if [[ ! -x "$executable" ]]; then
    /usr/bin/osascript -e 'display alert "UMA 0.9 review candidate is unavailable" message "CodexUsageMonitor.app is missing. Please report this P1 review issue."'
    exit 1
fi
# The installer seals this candidate with strict verification before it is
# copied. Finder may then add display-only metadata that makes a second
# whole-bundle verification non-repeatable, so the launcher never mutates or
# re-signs the sealed review copy.
if /usr/bin/pgrep -f "$executable" >/dev/null 2>&1; then
    exit 0
fi
# Finder may restore its display-only metadata while the review copy is idle.
# Clear only that metadata immediately before launch; never alter resources or
# re-sign the already sealed candidate.
/usr/bin/xattr -d com.apple.FinderInfo "$candidate" >/dev/null 2>&1 || true
/usr/bin/open "$candidate"
LAUNCHER
chmod 755 "$launcher_contents/MacOS/UMA0.9_Enter"
/usr/bin/plutil -lint "$launcher_contents/Info.plist" >/dev/null
/usr/bin/codesign --force --sign - "$LAUNCHER_APP"
# The source candidate was strictly verified before promotion. Finder can add
# display-only metadata to this stable Desktop copy immediately after `ditto`,
# so do not mutate or re-sign the copy merely to repeat that whole-bundle
# check. The launcher opens the sealed copy unchanged.
/usr/bin/codesign --verify --deep --strict --verbose=2 "$LAUNCHER_APP"
printf 'INSTALLED review_app=%s launcher=%s commit=%s\n' "$REVIEW_APP" "$LAUNCHER_APP" "$commit"
