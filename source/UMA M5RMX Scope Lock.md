# UMA M5RMX Scope Lock

**Version:** 1.0

**Date:** 2026-08-17

**Program:** UMA M5RMX — Claude completion and 0.12 delivery

**Current task:** `M5RMX-B0`

**Status:** Active

**Sole next task after accepted B0 PASS:** `M5RMX-G1`

## 1. Exact lineage

```text
Accepted parent workspace: /Users/juliushe/Developer/UMA-M8-Kimi
Accepted parent branch: codex/uma-m8-kimi
Exact parent HEAD: 01b190260da857f55fa5fa9b14da9715cafbc221
Exact parent tree: 49f2af499c86b9b8757da0e9406a0d9e5c24495b
Parent worktree/index at handoff: clean / empty

M5RMX workspace: /Users/juliushe/Developer/UMA-M5RMX-Claude
M5RMX branch: codex/uma-m5rmx-claude
M5RMX starting HEAD: 01b190260da857f55fa5fa9b14da9715cafbc221
M5RMX starting tree: 49f2af499c86b9b8757da0e9406a0d9e5c24495b
```

The M5RMX branch is based on the latest accepted local M8 lineage, not remote
main and not a historical M5-only branch. The accepted predecessor baseline is
`683/683 PASS`, with focused M8 evidence `32/32 PASS`; B0 still requires its own
fresh baseline verification before it may report PASS.

## 2. Current product boundary

Current providers, in stable order:

```text
1. Codex
2. Claude Code
3. WorkBuddy
4. Google Antigravity
```

All four are supported in the Main Panel and Desktop Assistant. Cursor and Kimi
are unsupported/hidden. M5RMX does not add a fifth provider, reopen M7 or M8,
or change provider ordering.

Protected mechanisms:

- Codex local app-server ownership, authentication, cadence, and semantics;
- WorkBuddy provider-owned account-web Credits ownership, cadence, and
  semantics;
- Google Antigravity official structured CLI ownership, cadence, pool identity,
  and remaining-value semantics;
- shared provider-neutral ordering, admission, Maximum Decrement, and density
  behavior except for the smallest additive change explicitly required by an
  active M5RMX Goal.

## 3. Current Claude truth

Claude Browser Sync is current through Safari and the status-line quota route is
retired. Chromium resources are packaged for a manual companion, but no current
live Chromium Browser Sync acceptance exists; Chromium is unverified and is not
the accepted current Claude source owner.

Current accepted ownership:

- Safari Browser Companion reads only the official Claude Usage surface;
- the browser layer validates the exact route before bounded semantic DOM
  inspection;
- only versioned, normalized quota observations cross the browser/native
  boundary;
- `ClaudeBrowserNativeHost` and the file-handoff bridge validate and deliver the
  bounded packet;
- `ClaudeCodeUsageConnector` owns one completion-relative five-minute
  scheduler, one in-flight read, current-session admission, freshness, and
  coalescing;
- the extension owns at most one inactive Usage tab and never adopts or closes
  a user-owned tab;
- `ClaudeBrowserSanitizedCacheStore` stores only validated sanitized data using
  owner-only filesystem rules;
- Main Panel and Desktop Assistant consume shared presentation truth;
- local Claude activity and API-equivalent cost are a separate this-Mac estimate
  channel and never account quota;
- Package.swift has no status-line target, active production source has no
  status-line runtime, and packaging rejects `ClaudeStatusLine` residue.

Accepted current statuses:

```text
Browser Sync quota source: ACCEPTED CURRENT
Provider-controlled Safari authentication: ACCEPTED CURRENT
Five-hour and weekly/7-day account windows: ACCEPTED CURRENT
Completion-relative five-minute automatic refresh: ACCEPTED CURRENT
Main Panel / Desktop Assistant shared truth: ACCEPTED CURRENT
Local activity and API-equivalent cost: ACCEPTED CURRENT, SEPARATE ESTIMATE
Status-line quota route: HISTORICAL / RETIRED
Final 0.12 extension distribution and notarized delivery: UNPROVEN / FUTURE
```

## 4. Privacy and credential boundary

Current policy:

`Credential existence is not the problem; credential crossing into UMA is the problem.`

Claude and Safari may own and use their own provider-controlled login, session,
and credentials. UMA must not receive, inspect, copy, retain, log, package, or
export passwords, passkeys, verification codes, OAuth/access/refresh tokens,
cookies, browser profiles, Keychain secrets, account identity, chats, projects,
prompts, responses, billing data, raw HTML, or broad DOM content.

The allowed browser-native packet is closed and versioned. It may contain only
the approved source/route/browser classifications, observation time, explicit
used percentages for accepted account windows, optional reset timestamps, and
approved bounded model-family classification. Used percentage is converted to
remaining exactly once in shared production logic. Unknown routes, layouts,
semantics, account modes, or ownership fail closed.

No broad process argv or environment inspection is allowed. Process evidence is
limited to exact task-owned executable path, captured PID, required ownership,
count, bounded resources, and exit/absence.

## 5. Editable and protected zones

### 5.1 Claude/M5RMX editable zone

Only an active M5RMX Goal may authorize edits in these classes:

```text
BrowserExtension/**
Sources/ClaudeBrowserBridgeProtocol/**
Sources/ClaudeBrowserNativeHost/**
Sources/ClaudeBrowserNativeHostCore/**
Sources/CodexUsageUI/Connectors/ClaudeBrowser*.swift
Sources/CodexUsageUI/Connectors/ClaudeCodeUsageConnector.swift
Sources/CodexUsageUI/Services/ClaudeLocalActivityReader.swift
Sources/CodexUsageUI/Stores/ClaudeBrowserSettingsModel.swift
Sources/CodexUsageUI/Models/AppLanguage+Claude.swift
Claude-specific Settings/Main Panel/Assistant source
Claude-specific tests and fixtures
M5/M5RMX current governance and QA records
M5RMX package/signing/delivery tooling
```

### 5.2 Shared additive-only zone

Shared files such as `Package.swift`, connector registry/runtime/snapshot
owners, `UsageStore`, `SharedUsagePresentation`, `UsagePanelView`,
`DesktopAssistantView`, Settings routing, and application/status-bar ownership
may change only when the active Goal requires a minimal Claude completion
change. Every edit must preserve Codex, WorkBuddy, and Antigravity contracts and
must be backed by focused plus cross-provider regression evidence.

### 5.3 Immutable and out-of-scope zones

- `source/reference/**` is checksum-locked historical/reference material and is
  read-only throughout M5RMX unless a later explicit Founder task says
  otherwise.
- Accepted historical records remain evidence of their own stage; M5RMX adds
  current truth rather than rewriting history.
- Cursor, Kimi, TRAE, Qoder, and every new provider are out of scope.
- Provider account mutation, purchase, intentional spend, prompt/task creation,
  private endpoint replay, API-key input, token import, Keychain export, cookie
  import, OCR, Accessibility scraping, and broad browser permission are out of
  scope.
- Remote push, PR, merge, tag, release, publication, App Store submission, and
  production deployment require their separately named later Goal.

## 6. Extension, native-host, and package boundary

The current Safari extension identity is
`com.silkrd.uma.ClaudeBrowserCompanion`; extension point
`com.apple.Safari.web-extension`. The current native-message identity is
`com.silkrd.uma.claude_browser`. The containing app identity is
`com.silkrd.uma`.

The current Safari manifest is version `1.2.3`, uses Manifest V2 persistent
background scripts, and requests exactly `nativeMessaging`, `storage`, and
`https://claude.ai/new*`. Because a URL fragment cannot be expressed in static
host permissions, production code must revalidate the exact
`https://claude.ai/new#settings/usage` route before every DOM query. There are no
static content scripts or broad host permissions.

The current Safari appex is sandboxed and carries one home-relative temporary
read/write exception limited to
`/Library/Application Support/CodexUsageMonitor/ClaudeBrowserCompanion/`; it has
no network-client entitlement. Whether Apple accepts this temporary exception
for final distribution remains an explicit M5RMX-SAFARI/H1 gate.

The current package helper embeds the app executable, native host, real Safari
`.appex`, shared extractor/control resources, unverified Chromium manual companion,
native-host manifest, app icon, and provenance plist. It supports ad-hoc builds
by default and optional Developer ID Hardened Runtime, secure timestamp,
notarytool, stapling, and Gatekeeper assessment when explicitly supplied the
accepted identity/profile. Its current marketing version is `0.11`; M5RMX must
not represent it as a final `0.12` package until a later authorized Goal repairs
and verifies that delivery contract.

## 7. Apple parallel record — no B0 action

```text
APPLE-G0: PASS
Apple Team: C6TUZVJ6SJ
Developer ID Application: READY
Matching private key: READY
Developer ID signing / Hardened Runtime / secure timestamp: PASS
notarytool: READY
Keychain profile: UMA-notary
Historical submission: bced6fed-8c8b-469e-924b-9b8a98395b6d
Status: APPLE-G1 BLOCKED — APPLE NOTARY BACKEND / SUPPORT INVESTIGATION
Apple Feedback: FB24386147
Apple Developer Support Case: 20000140194585
Protected smoke app: /private/tmp/uma-apple-g1-smoke-01b1902/UMAAppleG1Smoke.app
Protected smoke zip: /private/tmp/uma-apple-g1-smoke-01b1902/UMAAppleG1Smoke.zip
```

The two exact protected local smoke paths were confirmed present during B0
filesystem inventory without querying Apple. A bounded local integrity check
found that both the retained app and an isolated extraction of the retained
archive currently fail strict signature verification as code modified; their
executables have the same SHA-256. The scratch extraction was removed. Current
evidence therefore must not repeat the historical signature-valid claim. B0
performed no repair, re-signing, stapling, deletion, credential access, profile
mutation, or protected-artifact mutation. Apple infrastructure readiness does
not prove the current UMA package or Safari extension is distribution-signed,
notarized, stapled, or Gatekeeper-accepted. The preserved-state discrepancy
remains in the external Apple support workstream and does not block B0.

## 8. Desktop and repository boundary

Protected rollback app:

```text
/Users/juliushe/Desktop/UMA_0.11.app
Bundle ID: com.kevinchen.CodexUsageMonitor
Version/build: 0.11 / 202607270003
Executable SHA-256: 88ffbb48de43253f7289fe038dff9d0b195e61398f969439ff5c8729ecbef91a
```

A pre-existing `/Users/juliushe/Desktop/UMA_0.12.app` was inventoried at B0.
It reports bundle ID `com.silkrd.uma`, version/build `0.12 / 202608170001`,
source revision `67520d5af0d5530ccd32483165f5e2255b36d08a`, and executable SHA-256
`e95e2dac12383016f179564de2cc7e0db2fcccd3d7758a95129f18aa8e8145df`.
It is not the future M5RMX final deliverable and B0 does not create, replace,
launch, move, or delete it.

`/Users/juliushe/Desktop/CodexUsageMonitor` is a separate dirty historical
development checkout at `f1da999cf518433d108867d14ea1476678911ebf`, branch
`main`, behind its origin by five commits, with tracked and untracked Human
work. It is protected and must not be cleaned, reset, synchronized, or used as
the writable M5RMX workspace. `/Users/juliushe/Desktop/UMA_GitHub_Upload` is a
separate non-Git upload snapshot and is also protected.

Live remotes for the M5RMX repository:

```text
origin   https://github.com/ShaoJHe-SilkRoad/UMA.git
upstream https://github.com/ower93/CodexUsageMonitor.git
origin/main 469be4d6cf411a89401c2341807a57aef176d852
M5RMX HEAD is 43 commits ahead and 0 behind origin/main at B0 inventory time.
```

The Founder plan references
`https://github.com/ShaoJHe-SilkRoad/CodexUsageMonitor`; this does not match the
live `origin`. The discrepancy is recorded and must be resolved in the future
M5RMX-SYNC-G1 remote gate. No B0 remote URL mutation or remote action is
allowed.

## 9. B0 authority and completion lock

B0 may edit only its five records plus the focused B0 test owned by QA, run
deterministic local verification, stage exact B0 files, and create the one
authorized local documentation commit. It performs no production/provider/
Apple/Desktop actions.

After B0 PASS, the sole next task is `M5RMX-G1`. No later M5RMX Goal, Apple
action, Desktop delivery, or remote synchronization starts automatically.
