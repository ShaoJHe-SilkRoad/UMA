# AUV Windows

**AUV_Win_0.18.5 · stable · build 20261108.1 · Windows 11 x64 · portable ZIP · unsigned**

[Download](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.18.5-win/AUV_Win_0.18.5.zip) · [Installation](../docs/INSTALLATION.md#windows-installation-guide) · [Release notes](../docs/releases/AUV_Win_0.18.5.md) · [Claude browser companion](docs/claude-browser-companion.md)

Extract the complete package and run `AUV.exe`. The .NET 10 desktop runtime is included.
Optional WorkBuddy connections require Microsoft Edge WebView2 Runtime.

0.18.5 adds exact Claude readings through the AUV Browser Companion for Chrome or Edge (`browser-extension/`, helper `src/AUV.Windows.BrowserHost/`). It is off until you turn it on in Claude settings and choose Set Up. It reads only Claude's 5-hour and weekly used percentages and reset times from claude.ai's official Usage page, in English or Chinese; the sign-in stays in the browser. Plan and decisions: [docs/chrome-extension-plan.md](docs/chrome-extension-plan.md).

Everything from 0.18.4 stays: Refresh All and automatic refresh every 5/10/15/30/60 minutes; the most recently changed quota window, with a spent window first; a saved agent order; the six-pane Settings window; ThreadOS from Codex settings; English/Chinese; the optional Codex Local Cost Estimate.

Codex uses read-only installed-client usage. WorkBuddy official-page Credit sync remains experimental. Claude Code's local estimate, Antigravity live readings and Sectorium Windows storage operations are unavailable. ThreadOS generates and copies instructions; it does not dispatch them.

Keep `%LOCALAPPDATA%\AUV.Windows.UI.Preview` when upgrading. The preview-era preference path is intentionally retained; 0.16.x and 0.18.4 settings are read unchanged, and the companion's files go in its `browser-companion` folder. `Ctrl+Shift+Q` exits completely; Wizard right-click also offers Exit AUV.

Build and test: `scripts/build.ps1 -Publish` (also stages `BrowserCompanion\` beside `AUV.exe` with `scripts/stage-browser-companion.ps1`). Stable packaging (`scripts/package-product-preview.ps1 -Stable -Version 0.18.5 -Build 20261108.1 -PublishName AUV_Win_0.18.5 -ValidationPath <receipt>`) accepts a validation receipt with tested binary and evidence hashes. Opt-in native checks run from the built app: `--demo --offline --settings-path <isolated file>` with `--product-check-dir`, `--refinement-check-dir`, `--desktop-check-dir`, `--layout-check-dir` and `--feature-check-dir`; `--companion-check-dir` runs the companion's page-reader and background checks in WebView2 (from a build inside the repository). Live checks run in normal mode: `--provider-check-dir`, `--refresh-check-dir`, and `--live-check-dir` with `--live-stage reorder|verify`. Build outputs, preferences and account sessions are excluded from source.
