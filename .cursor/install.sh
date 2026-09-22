#!/usr/bin/env bash
# Cloud Agent bootstrap for the UMA (Codex Usage Monitor) repository.
#
# UMA is a native macOS application, so the SwiftUI/AppKit app itself cannot be
# built or run on a Linux Cloud Agent. What is portable is the repository's
# packaging-guard verification: pure-Python suites plus the version-authority
# shell scripts. Those shell scripts shell out to the macOS tools `plutil` and
# `PlistBuddy`, which do not exist on Linux. This script installs small,
# standard-library-only shims for those two tools at the absolute paths the
# repository scripts hard-code, so the portable verification runs green.
#
# The script is idempotent: it can run repeatedly and only refreshes the shims.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHIM_DIR="$ROOT_DIR/.cursor/bin"

command -v python3 >/dev/null 2>&1 || {
  echo "python3 is required but was not found on PATH" >&2
  exit 1
}

install_shim() {
  local source="$1" target="$2"
  sudo install -D -m 0755 "$source" "$target"
}

install_shim "$SHIM_DIR/plutil" /usr/bin/plutil
install_shim "$SHIM_DIR/PlistBuddy" /usr/libexec/PlistBuddy

echo "Installed plist tool shims:"
/usr/bin/plutil -lint "$ROOT_DIR/Configuration/UMAProductVersion.plist"
echo "  version authority ReleaseCandidate.BuildNumber = $("$ROOT_DIR/script/read_uma_product_version.sh" ReleaseCandidate.BuildNumber)"
echo "Cloud Agent environment ready."
