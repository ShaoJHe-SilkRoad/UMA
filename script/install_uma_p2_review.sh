#!/usr/bin/env bash
# Atomically replace the local UMA 0.9 review candidate and Finder launcher.
set -euo pipefail

readonly APP_NAME="UMA"
readonly REVIEW_ROOT="$HOME/Desktop/UMA0.9_Review"
readonly REVIEW_APP="$REVIEW_ROOT/$APP_NAME.app"
readonly LAUNCHER_APP="$HOME/Desktop/UMA0.9_Enter.app"

usage() { printf '%s\n' "Usage: $0 --candidate <absolute-path/UMA.app> --commit <40-hex-sha>"; }
candidate=""
commit=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --candidate) candidate="${2:-}"; shift 2 ;;
        --commit) commit="${2:-}"; shift 2 ;;
        *) usage >&2; exit 2 ;;
    esac
done

[[ "$candidate" = /*/"$APP_NAME".app && -d "$candidate" ]] || { usage >&2; exit 2; }
[[ "$commit" =~ ^[0-9a-f]{40}$ ]] || { usage >&2; exit 2; }
/usr/bin/xattr -cr "$candidate"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$candidate"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :UMAReviewCommit' "$candidate/Contents/Info.plist")" == "$commit" ]] || { printf '%s\n' "Candidate commit mismatch." >&2; exit 2; }

staging="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/uma-p2-install.XXXXXX")"
trap '/bin/rm -rf "$staging"' EXIT
/usr/bin/ditto "$candidate" "$staging/$APP_NAME.app"
mkdir -p "$staging/UMA0.9_Enter.app/Contents/MacOS"
{
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>'
    printf '%s\n' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    printf '%s\n' '<plist version="1.0"><dict>'
    printf '%s\n' '<key>CFBundleDisplayName</key><string>UMA0.9_Enter</string>'
    printf '%s\n' '<key>CFBundleExecutable</key><string>UMA0.9_Enter</string>'
    printf '%s\n' '<key>CFBundleIdentifier</key><string>com.kevinchen.CodexUsageMonitor.uma0.9.enter.p2</string>'
    printf '%s\n' '<key>CFBundleName</key><string>UMA0.9_Enter</string>'
    printf '%s\n' '<key>CFBundlePackageType</key><string>APPL</string>'
    printf '%s\n' '<key>CFBundleShortVersionString</key><string>0.9-development-preview</string>'
    printf '%s\n' '<key>CFBundleVersion</key><string>3</string>'
    printf '%s\n' '<key>LSUIElement</key><true/>'
    printf '%s\n' '</dict></plist>'
} > "$staging/UMA0.9_Enter.app/Contents/Info.plist"
launcher_source="$staging/UMA0.9_Enter.swift"
{
    printf '%s\n' 'import AppKit'
    printf '%s\n' 'import Foundation'
    printf '%s\n' ''
    printf '%s\n' '@main'
    printf '%s\n' 'struct UMAEnter {'
    printf '%s\n' '    @MainActor'
    printf '%s\n' '    static func main() {'
    printf '%s\n' '        let application = NSApplication.shared'
    printf '%s\n' '        let candidate = FileManager.default.homeDirectoryForCurrentUser'
    printf '%s\n' '            .appendingPathComponent("Desktop/UMA0.9_Review/UMA.app")'
    printf '%s\n' '        let metadataCleaner = Process()'
    printf '%s\n' '        metadataCleaner.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")'
    printf '%s\n' '        metadataCleaner.arguments = ["-d", "com.apple.FinderInfo", candidate.path]'
    printf '%s\n' '        do {'
    printf '%s\n' '            try metadataCleaner.run()'
    printf '%s\n' '            metadataCleaner.waitUntilExit()'
    printf '%s\n' '        } catch {}'
    printf '%s\n' '        NSWorkspace.shared.openApplication('
    printf '%s\n' '            at: candidate,'
    printf '%s\n' '            configuration: NSWorkspace.OpenConfiguration()'
    printf '%s\n' '        ) { _, error in'
    printf '%s\n' '            if let error {'
    printf '%s\n' '                FileHandle.standardError.write(Data("UMA launcher failed: \(error.localizedDescription)\n".utf8))'
    printf '%s\n' '            }'
    printf '%s\n' '            application.terminate(nil)'
    printf '%s\n' '        }'
    printf '%s\n' '        application.run()'
    printf '%s\n' '    }'
    printf '%s\n' '}'
} > "$launcher_source"
mkdir -p "$staging/module-cache"
/usr/bin/xcrun swiftc \
    -parse-as-library \
    -module-cache-path "$staging/module-cache" \
    "$launcher_source" \
    -o "$staging/UMA0.9_Enter.app/Contents/MacOS/UMA0.9_Enter"
/usr/bin/plutil -lint "$staging/UMA0.9_Enter.app/Contents/Info.plist" >/dev/null
/usr/bin/codesign --force --sign - "$staging/UMA0.9_Enter.app"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$staging/UMA0.9_Enter.app"

mkdir -p "$REVIEW_ROOT"
/bin/rm -rf "$REVIEW_APP.old" "$LAUNCHER_APP.old"
if [[ -e "$REVIEW_APP" || -L "$REVIEW_APP" ]]; then /bin/mv "$REVIEW_APP" "$REVIEW_APP.old"; fi
if [[ -e "$LAUNCHER_APP" || -L "$LAUNCHER_APP" ]]; then /bin/mv "$LAUNCHER_APP" "$LAUNCHER_APP.old"; fi
/bin/mv "$staging/$APP_NAME.app" "$REVIEW_APP"
/bin/mv "$staging/UMA0.9_Enter.app" "$LAUNCHER_APP"
/bin/rm -rf "$REVIEW_APP.old" "$LAUNCHER_APP.old"
printf 'INSTALLED review_app=%s launcher=%s commit=%s\n' "$REVIEW_APP" "$LAUNCHER_APP" "$commit"
