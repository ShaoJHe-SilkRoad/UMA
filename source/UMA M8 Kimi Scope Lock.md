# UMA M8 Kimi Scope Lock

**Version:** 1.0
**Date:** 2026-08-11
**Goal:** M8-B0
**Status:** Active M8 planning and source-admission boundary

## 1. Exact lineage

M8 starts from the accepted terminal M7 closeout, not from remote main and not
from the earlier M7-G1C predecessor:

```text
Parent workspace: /Users/juliushe/Developer/UMA-M7-Cursor
Parent branch: codex/uma-m7-cursor
Parent commit: e47f7de3e71f80d45a5561dad40e37f37ff11fd1
Parent tree: d836312beb29005e7b5abe882f9919d05a9b49f4
Parent verdict: M7 CLOSED — CURSOR UNSUPPORTED — SOURCE NOT ADMITTED
M8 branch: codex/uma-m8-kimi
M8 worktree: /Users/juliushe/Developer/UMA-M8-Kimi
```

Historical evidence is preserved explicitly:

```text
M7-G1C predecessor commit: fcb51ab48bb076704431742b7b0300c235975f8e
M7-G1C predecessor tree: 43dac9a01be51c3f19b3e510d3ff6923ca4bae57
Classification: historical source-decision predecessor; not the M8 branch point
```

The branch is local-only. Push, PR, merge, tag, release, notarization,
deployment, publication, App Store submission, and protected Desktop
replacement are not authorized.

## 2. Accepted runtime and package baseline

The supported production matrix remains exactly:

1. Codex
2. Claude Code
3. WorkBuddy
4. Google Antigravity

Cursor remains unsupported and hidden. Kimi is not installed, probed,
registered, presented, scheduled, cached, or authenticated by M8-B0.

The accepted runtime evidence remains:

```text
Runtime commit: e72bd92c476e05152b95ccb9ba95c22be78efef1
Runtime tree: c1358c5b4176383021e87605afc45ca3e347ab89
Package: /Users/juliushe/Developer/UMA-Packages/uma-m6adbg-final-e72bd92c476e05152b95ccb9ba95c22be78efef1/UMA.app
Package source archive SHA-256: 18046642208106125d2a69120bd2a88931c5af6d7a4dd55620fa9306d3828e97
Protected Desktop app: /Users/juliushe/Desktop/UMA_0.11.app
Protected Desktop executable SHA-256: 88ffbb48de43253f7289fe038dff9d0b195e61398f969439ff5c8729ecbef91a
```

The accepted package is local verification evidence only. The protected
Desktop application remains untouched.

## 3. Frozen and immutable zones

M8 must not modify the accepted M5 52-file protected set. Its sorted path/blob
manifest remains SHA-256:

```text
cd8cd9623b59cbf03d96b6d92e99b50d833dc4bc1b6bf7479148c4f63df83294
```

The protected set includes these exact path families and files:

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

The checksum-locked historical source set is immutable:

```text
source/reference/**
```

Existing Codex, Claude Code, WorkBuddy, and Google Antigravity source,
authentication, refresh, scheduler, cache, selection, presentation, and privacy
mechanisms are protected. M8-B0 changes none of them.

## 4. Shared additive-only zone

Later M8 implementation Goals may extend these provider-neutral surfaces only
when explicitly authorized, and only additively without changing an existing
provider mechanism:

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

Every later shared edit must report:

```text
Codex mechanism changed: NO
Claude mechanism changed: NO
WorkBuddy mechanism changed: NO
Google Antigravity mechanism changed: NO
```

## 5. Kimi free zone and provider model

M8-B0 creates planning records and tests only. Kimi production source files do
not yet exist. Later implementation may begin only after source admission.

The product model is one provider, stable ID `kimi`, with at most two truthful
channels:

1. shared Kimi membership usage — mandatory for any production admission;
2. Kimi Code-specific limits — separate, only when independently admitted.

Kimi Code consumption must not be double-counted as a second copy of shared
membership usage. Extra Usage must remain a native continuation state. If it is
enabled but its exact continuation truth is unreadable, UMA must not claim that
`0%` necessarily means work stops.

Kimi Open Platform API balance, API keys, copied tokens, credential files,
private endpoints, manual quota, task/activity estimates, and source-created
provider work are rejected.

## 6. Ordering, density, and Assistant ownership

The reserved provider order is:

```text
Codex → Claude Code → WorkBuddy → Google Antigravity → Kimi
```

The provider-neutral density rule remains:

```text
0–4 visible providers → Regular allowed
>4 visible providers → forced Minimalist
```

M8A owns the first live five-provider Desktop Assistant transition, shared
truth parity, forced-Minimalist behavior, and restoration when the visible
count returns to four or fewer. M8-B0 does not implement or simulate that
transition in production.

## 7. Test, package, and privacy boundaries

The deterministic repository test entry point remains:

```text
script/test.sh --no-parallel
```

The accepted full baseline must be measured from the corrected M7 closeout
parent; the historical 628 count is not a current acceptance target.

Future local verification packages belong under:

```text
$HOME/Developer/UMA-Packages/
```

No package or app is built or installed by M8-B0. No provider operation occurs:

```text
Kimi quota/source observations: 0
Kimi prompts/tasks: 0
Intentional Kimi spend: 0
Kimi login/browser actions: 0
Credential, cookie, Keychain, profile, or private database access: 0
```

Safe process evidence is limited to exact executable path/name, exact PID,
owned parent/child relation, process count, bounded resource counters, and
exit/absence state. Broad argv or environment inspection is forbidden.

## 8. Installed governing set and sole next task

M8-B0 installs these mutable current-truth records:

```text
source/Scroll_3.md
source/M8_Plan.md
source/M8_Goal.md
source/UMA M8 Kimi Scope Lock.md
```

The installed Founder-corrected source documents preserve their corrected
content with Git-clean line endings and these SHA-256 values:

```text
source/Scroll_3.md: d8979fa346b8ab05863bd10518223425381ab3fbf22297b6ee40caf76b57c81f
source/M8_Plan.md: 86f6c278c350c1d0b1413b9d64e1ee717084aab8b22728a174bda2c66730fad0
source/M8_Goal.md: 9ca570a11b2e494690c64fe4d4be51d9e2d8e8a885de25ec70d0eb75096f850c
```

The corrected parent measures 619 UI tests plus 18 bridge tests, 637 total.
M8-B0 adds six focused planning tests, so its full deterministic result is 625
UI tests plus 18 bridge tests, 643 total. Counts are measured results, not a
historical acceptance target.

Final M8-B0 verification is claim-matched:

| Gate | Result |
|---|---|
| Focused M8-B0 contract | PASS — 6/6 tests |
| Full deterministic serial suite | PASS — 625 UI + 18 bridge = 643/643 |
| Debug build | PASS |
| Release build | PASS |
| Strict-concurrency Release, warnings as errors | PASS |
| Cached whitespace check | PASS after the mechanical metadata repair |
| Runtime, package-helper and `source/reference/**` diff | PASS — unchanged from the corrected parent |
| M5 52-file protected manifest | PASS — unchanged |
| Existing provider mechanisms | PASS — Codex, Claude Code, WorkBuddy and Google Antigravity unchanged |
| Cursor/Kimi production registration | PASS — Cursor unsupported; Kimi absent |
| Privacy, identity and secret scan | PASS — no retained sensitive value |
| Accepted package provenance/signature | PASS — commit-exact `e72bd92c...`; strict deep signature |
| Protected Desktop executable | PASS — unchanged SHA-256 `88ffbb48...` |
| Independent staged-index review | PASS — exact five-file cached scope; no blocking or actionable issue |

The source-supplied introductory metadata hard breaks were normalized because
the M8-B0 delivery contract requires a clean cached whitespace check. No prose,
strategy, privacy rule, provider order, source-admission rule, or Goal scope was
changed by that mechanical formatting repair. The installed files contain no
tabs or trailing whitespace.

The corrected current-parent references in those three Founder documents are
intentional; historical M7-G1C references remain labeled as history. The
downloaded Founder source pack is not a checksum-locked `source/reference/**`
set and no historical record is rewritten.

After an accepted M8-B0 commit, the only next task is:

```text
M8-G1 — Kimi unified source admission
```

M8-G1 must not start automatically. Installation, login, quota reads, source
probing, web admission, runtime work, UI work, packaging, or another provider
remain locked until the appropriate direct Founder authorization.

## Completion Lock

Stop after the M8-B0 report and local commit. Do not begin M8-G1.
