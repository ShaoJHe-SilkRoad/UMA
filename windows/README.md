# AUV Windows

**AUV_Win_0.16.3 · stable · Windows 11 x64 · portable ZIP · unsigned**

[Download](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.16.3/AUV_Win_0.16.3.zip) · [Installation](../docs/INSTALLATION.md#windows-installation-guide) · [Release notes](../docs/releases/0.16.3.md)

Extract the complete package and run `AUV.exe`. The .NET 10 desktop runtime is included.
Optional WorkBuddy connections require Microsoft Edge WebView2 Runtime.

0.16.3 unifies the main window header with the application, refines the Regular and Minimalist Wizard, and adds a persistent Hide tray icon setting. Windows controls whether a visible tray icon appears in the notification area or overflow; use Windows taskbar settings to pin it.

Codex uses read-only installed-client usage. WorkBuddy official-page Credit sync remains experimental. Claude/Antigravity live transports and Sectorium Windows storage operations remain unavailable. ThreadOS generates and copies instructions; it does not dispatch them.

Keep `%LOCALAPPDATA%\AUV.Windows.UI.Preview` when upgrading. The preview-era preference path is intentionally retained. `Ctrl+Shift+Q` exits completely; Wizard right-click also offers Exit AUV.

Build and test: `scripts/build.ps1 -Publish`. Stable packaging accepts a validation receipt with tested binary and evidence hashes. Build outputs, preferences and account sessions are excluded from source.
