# AUV Windows

**AUV_Win_0.18.6 · stable · build 20261111.1 · Windows 11 x64 · portable ZIP · unsigned**

[Download](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.18.6-win/AUV_Win_0.18.6.zip) · [Installation](../docs/INSTALLATION.md#windows-installation-guide) · [Release notes](../docs/releases/AUV_Win_0.18.6.md) · [Claude browser companion](docs/claude-browser-companion.md)

Extract the complete package and run `AUV.exe`. The .NET 10 desktop runtime is included.
Optional WorkBuddy connections require Microsoft Edge WebView2 Runtime.

0.18.6 makes Claude easier to connect and the app nicer to use:
- one **Connect** button on the Claude page and a three-step checklist that ticks itself (registered, extension loaded, signed in), with Load in Chrome/Edge and Open claude.ai buttons; browser and placement options under Advanced;
- Claude's bars use Codex's green/red colours (20% when the Claude plan is unknown);
- the browser companion is used where it ships, in `BrowserCompanion\` inside the AUV folder (decision D6a). Load `BrowserCompanion\extension` once per AUV folder; coming from 0.18.5, AUV offers to delete its old copy in `%LOCALAPPDATA%`;
- a cleaner look (cards, navigation, focus ring) and restrained motion that switches off with Windows "Show animations". Quota bars and the Desktop Wizard look the same.

The companion (`browser-extension/`, helper `src/AUV.Windows.BrowserHost/`) reads only Claude's 5-hour and weekly used percentages and reset times from claude.ai's official Usage page, in English or Chinese; the sign-in stays in the browser. Plan and decisions: [docs/chrome-extension-plan.md](docs/chrome-extension-plan.md).

Codex uses read-only installed-client usage. WorkBuddy official-page Credit sync remains experimental. Claude Code's local estimate, Antigravity live readings and Sectorium Windows storage operations are unavailable. ThreadOS generates and copies instructions; it does not dispatch them.

Keep `%LOCALAPPDATA%\AUV.Windows.UI.Preview` when upgrading. The preview-era preference path is intentionally retained; 0.16.x, 0.18.4 and 0.18.5 settings are read unchanged. Put AUV in a folder you can write to (not Program Files): Connect writes the helper's registration files next to it. `Ctrl+Shift+Q` exits completely; Wizard right-click also offers Exit AUV.

Build and test: `scripts/build.ps1 -Publish` (also stages `BrowserCompanion\` beside `AUV.exe` with `scripts/stage-browser-companion.ps1`). Stable packaging (`scripts/package-product-preview.ps1 -Stable -Version 0.18.6 -Build 20261111.1 -PublishName AUV_Win_0.18.6 -ValidationPath <receipt>`) accepts a validation receipt with tested binary and evidence hashes. Opt-in native checks run from the built app: `--demo --offline --settings-path <isolated file>` with `--product-check-dir`, `--refinement-check-dir`, `--desktop-check-dir`, `--layout-check-dir`, `--feature-check-dir` and `--ui-check-dir`; `--companion-check-dir` and `--claude-check-dir` run the companion checks (from a build inside the repository); `--no-animations` turns motion off. Live checks run in normal mode: `--provider-check-dir`, `--refresh-check-dir`, and `--live-check-dir` with `--live-stage reorder|verify`. Build outputs, preferences and account sessions are excluded from source.
