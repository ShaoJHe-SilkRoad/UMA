# UMA 0.14 M5-B — Install, Migration and Isolation

Status: M5-B engineering qualification PASS. Independent staged review and final commit/tree readback are recorded in the evidence packet. This record does not authorize M5-C or production release.

## Authority and baseline

- Founder instruction: `Start M5-B`.
- Canonical worktree: `/Volumes/HE/DEV/UMA/Worktrees/UMA-0.14-Surface-Rebuild`.
- Branch: `codex/uma-0.14-surface-rebuild`.
- Starting commit: `b89cc2d23468f867bc15902c50bfae940a4c4d51`; tree: `ebb1fbb008b187349b2744612ee3e1d3216a62fe`; worktree clean/index empty.
- DEV_APFS: APFS, `/Volumes/HE/DEV`, writable, Owners Enabled, verified before development.
- Frozen 0.13: `f6dd617bb736d49b444dda4945d55e5b4606c915`; tree `16223ec6b1e3b3c1bf5a80191c97e9887498d622`, unchanged.
- Milestone authority: `/Users/juliushe/Downloads/UMA_0.14_Astra_Shift_Change_Report.md`, modified `2026-09-04T17:45:47.004083-03:00`, SHA-256 `aa56a02ca8432d9d0a89db6ee8b0df1fa689cc18352ea7630bc7b25eafcfd8dc`.
- Newer Downloads ThreadOS Astra/Factorium documents describe a separate integration initiative. Their embedded model, product activation and publication instructions were not imported into this bounded UMA M5-B task.

## Resulting behavior

1. `ApplicationDataPaths` supplies runtime and Settings with the same file boundary. Exact production identity keeps the released `CodexUsageMonitor` application-support root. Development/unknown identities use separate validated roots, including snapshots, Codex cost ledger, Claude cache/anchors and statusLine state. No production preferences, consent or cache is copied into development. Settings clears its runtime's three allowlisted caches; existing cost-ledger retention remains unchanged.
2. A disabled-provider runtime no longer constructs Host integration, discovers provider surfaces, restores connector state or performs the implicit registry launch scan. It retains injected preferences and the disconnected settings model.
3. Snapshot routine writes preserve unsupported future main/backup bytes and rotate only fully valid supported data. Corrupt-main recovery retains a valid backup. Reads, mutations and clear reject leaf/ancestor symlinks. Schema-zero lazy migration, schema-one rollback shape, stale restoration and original timestamps remain intact.
4. Snapshot and ledger first writers create new directories with owner-only permissions. A runtime-only opt-in also handles an existing 0.13 directory with wider permissions: the anchor store verifies ownership, directory type, symlink exclusion and descriptor/path identity before tightening the opened directory to `0700`. Generic injected stores retain strict refusal. Data bytes and same-owner rollback readability are preserved; no real production directory was changed during qualification.
5. A persistent Claude Code hook requires a stable installed app and its regular executable bundled relay. Translocation/build/worktree paths and escaping/missing helpers are refused. Code-only unavailable setup/repair reports a reason without granting consent or pretending a refresh installed the hook. Desktop Local Smart and independent one-shot Accuracy Sync remain separate. A moved installed app needs explicit ownership-checked repair; prior settings and unrelated human edits survive repair and restore.
6. The development packager refuses production/test identities, unsafe output paths, app-directory destinations, symlink ancestors and existing artifacts before output writes. It reserves a unique app directory and disables SwiftPM credential lookup. The accepted review/production apps cannot be used as an overwrite destination through this script.

## Evidence and qualification

Evidence root: `/Volumes/HE/DEV/UMA/Build/uma014-m5b/evidence`.

| Verification | Final result |
| --- | --- |
| Focused Swift qualification | 223 test definitions / 19 suites, PASS (`focused-final.log`) |
| Complete post-convergence regression | 1,094 UI definitions / 106 suites + 56 bridge definitions / 3 suites = 1,150, PASS (`broad-final.log`) |
| Development package refusal | 14 isolated cases, PASS (`package-guards-final.log`) |
| Frozen-shape migration / rollback | Independent 0.13 preference/position decoders; current/obsolete consent, future bytes, snapshot recovery, legacy directory and sentinel fixtures, PASS |
| Actual Settings clear | Injected development files cleared; production-shaped fixture files and consent unchanged, PASS |
| Installed helper path | Fixture move, explicit repair, prior-settings restore and shell quoting, PASS |
| Immutable Host compatibility | Mutable 0.14 / immutable 0.13 public-metadata fixtures, identity/group/generation refusal, PASS; no live Host request |
| Moved development payload | Bundled relay executed with synthetic quota input after original staging app was removed by relocation, PASS |
| Protected artifacts | All 32 files/links across four protected bundles retain identical hashes, modes and link targets (`protected-before.json` / `protected-after.json`) |

Live opt-ins were absent. Test definitions that return behind live guards do not count as live acceptance. Earlier failed runs are retained: one throwing test-expression compile error; unsafe temporary-path fixtures and stale source-string assertions; the newly identified first-writer/legacy-directory condition. Final counts above come only from the final successful runs. The directory migration also received independent review after the initial review identified the existing-0755 upgrade gap.

Development qualification app:
`/Volumes/HE/DEV/UMA/Packages/uma-0.14-m5b-qualification-20260904T233600Z/Isolated User's Applications/UMA 0.14 M5-B Qualification.app`

- Identity: `com.silkrd.uma.dev.uma014.m5b-qualification`; canonical development version `0.14.0`; explicit qualification build `2026090402`.
- Main executable SHA-256: `d352b94f174303b0418326951caa87dde0ed3044ae41f5f21a7aea54252ce43b`.
- Relay SHA-256: `ea0fc16e165f6dfb891e38dd19e42d43cc25762cd4098cd8a43b2ad1b4d117ef`.
- `package-qualification.json` records product source-file hashes, base commit, diff digest, package files and Mach-O linkage. Both executables load only absolute system dependencies; the debug build's unused PackageFrameworks/Xcode search paths are recorded separately in `package-rpath-reconciliation.md`. No build-engine change, binary rewriting or signing was used to hide those paths.
- The main app was not launched. Only the bundled relay consumed content-free synthetic input and wrote a task-owned `0600` state file. This dirty-tree debug qualification is not a clean commit-exact RC or minimum-OS acceptance proof.

Protected applications: Desktop UMA 0.13.0, Desktop UMA 0.11, production UMA Safari Bridge, and the accepted Edge Final Review app. The accepted review executable still hashes to `8739728cd4fb9b66a1ce254464e7def3d5fea47848393cd219faeb78bf6d4fb8`.

## Remaining independent release gates

M5-C must produce a fresh clean commit/tree-bound RC, complete final package provenance and appropriate release linkage qualification, then obtain real installed-app/upgrade/rollback, OS translocation, provider/Host and soak evidence under explicit authorization. Static fixtures and moved relay execution do not replace those live gates. Developer ID signing, hardened runtime, secure timestamp, notarization, stapling, Gatekeeper/offline validation, production delivery and GitHub synchronization remain separately authorized release work.

No real provider/Safari/private-data access, production preference/consent migration, installed app/Host replacement, Keychain access, release signing/notarization, push/tag/merge/release or M5-C execution occurred. Active product support remains Codex/Claude; ThreadOS product activity remains zero. Accepted Quick Panel compositing, remaining-usage semantics and production rollback source are preserved.

## Exact Goal-owned files

Production source (13):
- `Sources/CodexUsageMonitor/App/AppShellCoordinator.swift`
- `Sources/CodexUsageMonitor/App/NativeShellViews.swift`
- `Sources/CodexUsageMonitor/App/NativeWindowControllers.swift`
- `Sources/CodexUsageUI/Connectors/AgentConnectorSnapshotStore.swift`
- `Sources/CodexUsageUI/Connectors/AgentUsageRuntime.swift`
- `Sources/CodexUsageUI/Connectors/BundledClaudeRelay.swift`
- `Sources/CodexUsageUI/Connectors/ClaudeBrowserSanitizedCacheStore.swift`
- `Sources/CodexUsageUI/Preferences/ApplicationDataPaths.swift`
- `Sources/CodexUsageUI/Services/APICostLedger.swift`
- `Sources/CodexUsageUI/Services/ClaudeSmartUsageEngine.swift`
- `Sources/CodexUsageUI/Services/SettingsDataActions.swift`
- `Sources/CodexUsageUI/Stores/ClaudeBrowserSettingsModel.swift`
- `Sources/CodexUsageUI/Views/AgentSurfaceViews.swift`

Tests (6):
- `Tests/CodexUsageUITests/M5RMXClaudeDesktopSupportTests.swift`
- `Tests/CodexUsageUITests/M5RMXSafariHostProductStateTests.swift`
- `Tests/CodexUsageUITests/UMA014M1NativeShellTests.swift`
- `Tests/CodexUsageUITests/UMA014M5BInstallCompatibilityTests.swift`
- `Tests/CodexUsageUITests/UMA014M5BMigrationIsolationTests.swift`
- `Tests/CodexUsageUITests/UMA014M5BSnapshotMigrationTests.swift`

Packaging (2): `script/package_uma014_m1_dev.sh`, `script/test_uma014_dev_package_guards.py`.

Closeout (1): this document.
