# AUV for Windows

Stable **0.16.2**, build **20261010.8**, for **Windows 11 x64**. The portable ZIP is unsigned. Extract the entire archive and run `AUV.exe`; keep its supporting files together. See the [installation guide](../docs/INSTALLATION.md) and [release notes](../docs/releases/0.16.2.md).

## Scope

| Area | Windows 0.16.2 |
| --- | --- |
| AUV / Codex | Supported read-only usage from the installed Codex client's existing login; no inference requests. |
| WorkBuddy | Experimental official-page Credit synchronization in a separate WebView2 session; manual sign-in. |
| Claude / Antigravity | Prepared interfaces only; live transports unavailable. |
| Desktop Wizard / tray | Supported floating quota cards, tray usage popup and read-only CPU/RAM counters. Unknown, disconnected and stale quotas are hidden; verified zero remains visible. |
| ThreadOS | Supported deterministic instruction generation/copy. Receiving-client integration and live Ultra execution are untested. |
| Sectorium | UI only. Windows storage backend unavailable; mutating actions disabled. |

The .NET 10.0.12 desktop runtime is included. The optional WorkBuddy connection needs Microsoft Edge WebView2 Runtime, which is not bundled. No installer, automatic startup or service is installed. Windows and macOS preferences are separate.

Settings remain in `%LOCALAPPDATA%\AUV.Windows.UI.Preview\settings.v1.json` for continuity. WorkBuddy's separate `workbuddy-web-*` profile is beside that file. Preserve this directory during upgrades. Demo settings are separate.

## Build and test

On Windows x64, from this directory:

```powershell
powershell -NoProfile -File .\scripts\bootstrap-sdk.ps1
powershell -NoProfile -File .\scripts\build.ps1 -Publish
```

Bootstrap installs SDK 10.0.401 in this subtree's ignored `.tools` directory without changing the system installation. The build script restores NuGet dependencies, generates the native icon, builds, runs the tests and publishes a self-contained application into `artifacts/AUV-0.16.2-win-x64/`.

`SOURCE-MANIFEST.json` records the 63 exact accepted source inputs. Its SHA-256 identity is `70C65EC0C5496682F13954AB810A374B9267CEA771A28E5E74CB95067D6C50EE`. Public release packaging preserves the tested EXE/DLLs, removes development PDBs and updates distribution documentation; it does not claim a new compilation. The Release's `RELEASE-MANIFEST.json` maps those inputs to the Git commit and final distributed bytes. `scripts/package-product-preview.ps1` retains the earlier candidate packaging modes; stable mode requires a local validation receipt and does not publish automatically.

## Useful controls

- `Alt+A`, `Alt+T`, `Alt+S`: AUV, ThreadOS, Sectorium.
- `Ctrl+,`: settings; `F5`: refresh selected provider.
- `Ctrl+Shift+W`: Wizard; `Ctrl+Shift+U`: tray usage popup.
- `Ctrl+Shift+Q`: quit all application windows and tray.

`AUV.exe --offline` avoids live providers. `--demo --offline --show-widget` uses explicitly labeled sample data and separate preferences. Opt-in verification switches are development tools, not background tests.

## Verification limits

Accepted build evidence: 146/146 automated tests, 138 native product checks, 47 native refinement checks, 48 rendered layout captures and read-only live Codex checks. Performed by the developer in this thread; no independent QA claim. Live WorkBuddy was not repeated for build .8. Render densities are not certification of every Windows scaling configuration. Clean-machine, ARM64, signing/reputation, installer and Windows storage qualification are not claimed.

Third-party notices are in `src/AUV.Windows.App/Assets/Notices` and provider asset provenance is in `Assets/AgentLogos/PROVENANCE.md`. Existing repository licensing remains unchanged.
