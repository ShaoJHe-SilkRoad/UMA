# AUV Windows

**AUV_Win_0.18.7 · stable · build 20261116.1 · Windows 11 x64 · portable ZIP · unsigned**

[Download](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.18.7-win/AUV_Win_0.18.7.zip) · [Installation](../docs/INSTALLATION.md#windows-installation-guide) · [Release notes](../docs/releases/AUV_Win_0.18.7.md) · [Claude browser companion](docs/claude-browser-companion.md)

Extract the complete package and run `AUV.exe`. The .NET 10 desktop runtime is included.
Optional WorkBuddy connections require Microsoft Edge WebView2 Runtime.

0.18.7 fixes three things and brings the new icon:
- showing the Desktop Wizard now also turns it on (before, it stayed hidden when "Enable Desktop Wizard" was off);
- clicking the tray icon while the Usage panel is open closes it instead of reopening it, and a double click keeps it open;
- a maximized window comes back maximized after minimizing, after saving settings while minimized, and from Open AUV in the tray; the first hide to the tray shows a one-time "AUV is still running" notice (setting `Desktop.TrayHintShown`, default off in older files);
- the new "B3" AUV icon, the same as AUV for Mac, for the app and the browser extension.

0.18.6 brought one **Connect** button for Claude with a three-step checklist, Claude's bars in Codex's colours, the companion in `BrowserCompanion\` inside the AUV folder, and a cleaner look with restrained motion.

The companion (`browser-extension/`, helper `src/AUV.Windows.BrowserHost/`) reads only Claude's 5-hour and weekly used percentages and reset times from claude.ai's official Usage page, in English or Chinese; the sign-in stays in the browser. Plan and decisions: [docs/chrome-extension-plan.md](docs/chrome-extension-plan.md).

Codex uses read-only installed-client usage. WorkBuddy official-page Credit sync remains experimental. Claude Code's local estimate, Antigravity live readings and Sectorium Windows storage operations are unavailable. ThreadOS generates and copies instructions; it does not dispatch them.

Keep `%LOCALAPPDATA%\AUV.Windows.UI.Preview` when upgrading. The preview-era preference path is intentionally retained; 0.16.x and 0.18.x settings are read unchanged. Put AUV in a folder you can write to (not Program Files): Connect writes the helper's registration files next to it. `Ctrl+Shift+Q` exits completely; Wizard right-click also offers Exit AUV.

Build and test: `scripts/build.ps1 -Publish` (also stages `BrowserCompanion\` beside `AUV.exe` with `scripts/stage-browser-companion.ps1`). Stable packaging (`scripts/package-product-preview.ps1 -Stable -Version 0.18.7 -Build 20261116.1 -PublishName AUV_Win_0.18.7 -ValidationPath <receipt>`) accepts a validation receipt with tested binary and evidence hashes. Opt-in native checks run from the built app: `--demo --offline --settings-path <isolated file>` with `--product-check-dir`, `--refinement-check-dir`, `--desktop-check-dir`, `--layout-check-dir`, `--feature-check-dir`, `--ui-check-dir` and `--tray-check-dir`; `--companion-check-dir` and `--claude-check-dir` run the companion checks (from a build inside the repository); `--no-animations` turns motion off. Live checks run in normal mode: `--provider-check-dir`, `--refresh-check-dir`, and `--live-check-dir` with `--live-stage reorder|verify`. Build outputs, preferences and account sessions are excluded from source.
