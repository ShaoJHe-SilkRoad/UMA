# AUV Windows

**AUV_Win_0.18.4 · stable · build 20261107.1 · Windows 11 x64 · portable ZIP · unsigned**

[Download](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.18.4-win/AUV_Win_0.18.4.zip) · [Installation](../docs/INSTALLATION.md#windows-installation-guide) · [Release notes](../docs/releases/AUV_Win_0.18.4.md)

Extract the complete package and run `AUV.exe`. The .NET 10 desktop runtime is included.
Optional WorkBuddy connections require Microsoft Edge WebView2 Runtime.

0.18.4 aligns Windows with AUV for Mac 0.18.4 where Windows can support it:
- Refresh All, and automatic refresh every 5/10/15/30/60 minutes;
- the most recently changed quota window, with a spent window shown first;
- a saved agent order that the tray panel, tray tooltip and Desktop Wizard follow;
- a redesigned main window and a six-pane Settings window;
- ThreadOS opened from Codex settings;
- an English/Chinese interface;
- an optional Codex Local Cost Estimate, off by default.

Codex uses read-only installed-client usage. WorkBuddy official-page Credit sync remains experimental. Claude and Antigravity live readings, the Safari-based Mac features, and Sectorium Windows storage operations are unavailable. ThreadOS generates and copies instructions; it does not dispatch them.

Keep `%LOCALAPPDATA%\AUV.Windows.UI.Preview` when upgrading. The preview-era preference path is intentionally retained, and 0.16.x settings are read unchanged. `Ctrl+Shift+Q` exits completely; Wizard right-click also offers Exit AUV.

Build and test: `scripts/build.ps1 -Publish`. Stable packaging (`scripts/package-product-preview.ps1 -Stable -Version 0.18.4 -Build 20261107.1 -PublishName AUV_Win_0.18.4 -ValidationPath <receipt>`) accepts a validation receipt with tested binary and evidence hashes. Opt-in native checks run from the built app: `--demo --offline --settings-path <isolated file>` with `--product-check-dir`, `--refinement-check-dir`, `--desktop-check-dir`, `--layout-check-dir` and `--feature-check-dir`. Live checks run in normal mode: `--provider-check-dir`, `--refresh-check-dir`, and `--live-check-dir` with `--live-stage reorder|verify`. Build outputs, preferences and account sessions are excluded from source.
