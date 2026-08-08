# UMA M6 Antigravity Scope Lock

**Version:** 1.0
**Date:** 2026-08-08
**Goal:** M6-B0
**Status:** Active M6 coordination and source-admission boundary

## 1. Exact lineage and delivery boundary

M6 starts from the local-only Claude handover lineage:

```text
Parent workspace: /Users/juliushe/Developer/UMA-M5-Claude
Parent branch: codex/uma-m5-claude
Parent commit: c6245f9cc745b3d45f53e115843b3152e84e8c46
Parent tree: e3ac2df1d135dad4c85af06611dc05943e8089dd
M6 branch: codex/uma-m6-antigravity
M6 worktree: /Users/juliushe/Developer/UMA-M6-Antigravity
```

The M6 branch is local-only. M6 must not be reconstructed from `origin/main`.
Push, PR, merge, tag, release, notarization, deployment, and publication are not
authorized. M6-B0 changes documentation only and does not begin source probing
or implementation.

## 2. M5 frozen zone

Claude M5 is frozen pending Apple Developer Program activation. M6 must not
modify:

```text
Sources/ClaudeBrowserBridgeProtocol/ClaudeBrowserBridgeProtocol.swift
Sources/ClaudeBrowserNativeHost/main.swift
Sources/ClaudeBrowserNativeHostCore/**
Sources/CodexUsageUI/Connectors/ClaudeCodeUsageConnector.swift
Sources/CodexUsageUI/Connectors/ClaudeBrowserProductionIntegration.swift
Sources/CodexUsageUI/Connectors/ClaudeBrowserSanitizedCacheStore.swift
Sources/CodexUsageUI/Services/ClaudeLocalActivityReader.swift
Sources/CodexUsageUI/Stores/ClaudeBrowserSettingsModel.swift
Sources/CodexUsageUI/Models/AppLanguage+Claude.swift
BrowserExtension/**
Tests/ClaudeBrowserBridgeCoreTests/**
Tests/CodexUsageUITests/M5*.swift
script/package_uma_m5_g2.sh
script/test.sh
source/UMA M5 *.md
```

The retired Claude status-line and credential-broker routes remain guarded and
must not be reintroduced. Claude account quota remains Browser Sync data; Claude
local activity remains a separate locally estimated channel and never becomes
account quota.

## 3. Shared additive-only zone

The following provider-neutral surfaces may be extended only when a later M6
Goal explicitly requires it, and only additively without changing existing
Codex, Claude Code, or WorkBuddy behavior:

```text
Package.swift
Sources/CodexUsageUI/Connectors/AgentUsageConnector.swift
Sources/CodexUsageUI/Connectors/AgentConnectorRegistry.swift
Sources/CodexUsageUI/Connectors/AgentConnectorSnapshotStore.swift
Sources/CodexUsageUI/Connectors/AgentUsageRuntime.swift
Sources/CodexUsageUI/Stores/UsageStore.swift
Sources/CodexUsageUI/Models/UsageSnapshot.swift
Sources/CodexUsageUI/Models/SharedUsagePresentation.swift
Sources/CodexUsageUI/Views/UsagePanelView.swift
Sources/CodexUsageUI/Views/DesktopAssistantView.swift
```

Every later shared edit must explicitly report:

```text
Codex mechanism changed: NO
Claude mechanism changed: NO
WorkBuddy mechanism changed: NO
```

## 4. M6 free zone

After source admission and a separate authorized Goal, M6 may add new
Antigravity-specific connectors, services, models, stores, localization, views,
non-M5 tests, non-M5 governance records, and a non-M5 package helper. M6-B0
does not authorize any of those runtime changes.

## 5. Binding product and build contracts

- Active bundle identifier: `com.silkrd.uma`.
- Supported test entry point on this machine: `script/test.sh`; bare
  `swift test` is not accepted baseline evidence.
- Final packages belong under `$HOME/Developer/UMA-Packages`; only scratch
  intermediates may use `/private/tmp`.
- A provider may publish at most two channels.
- The persisted local-activity payload remains exactly six aggregate scalars.
- `sourceVersion` must match `^[A-Za-z0-9 ._-]+$` and must be no longer than 32
  characters.
- Provider order is Codex -> Claude Code -> WorkBuddy -> Google Antigravity.
- Four visible providers do not force Minimalist. More than four visible
  providers force Desktop Assistant Minimalist while preserving the stored
  manual preference.
- Views consume shared immutable presentation and own no provider process,
  timer, decoder, cache, source scanner, or selected-window policy.
- The protected Desktop application remains
  `/Users/juliushe/Desktop/UMA_0.11.app`; M6-B0 does not modify or replace it.

## 6. Antigravity source-admission boundary

The active research direction is the official Antigravity CLI read-only
structured `/usage` or `/quota` output. The older status-line-first assumption
is superseded. Installed status alone never admits the provider. Visibility
requires a current accepted observation with explicit quota semantics and a
completed source dossier.

M6 may not use or request:

- a user-entered API key, copied OAuth token, setup token, or credential;
- a Keychain credential read, cookie import, or browser-profile import;
- an undocumented private endpoint or third-party quota proxy;
- a manual quota, manual deduction, or locally inferred account balance;
- a quota-consuming prompt, task, conversation, or refresh operation;
- raw identity, workspace, conversation, prompt, response, or provider payload
  persistence.

The official provider CLI may manage its own authentication internally; UMA
must never receive that authentication material. M6-G1 alone may decide GO,
CONDITIONAL GO, SETUP REQUIRED, or NO-GO from current documented and live-safe
evidence.

## 7. Sequence lock

M6-B0 ends after the documentation commit, baseline verification, clean
worktree, and empty index. M6-G1 is the only permitted next task and does not
start automatically. Cursor source admission is next after M6; no Cursor code
or five-provider transition belongs in M6.
