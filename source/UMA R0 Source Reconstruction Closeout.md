# UMA R0 Source Reconstruction Closeout

## Provenance

- Historical accepted binary revision: `a8c5ff23fdfb4652481b8b4d2447bcfb2d152cbd`
- Historical source status: not recovered; no claim of restoring or reproducing its tree is made.
- Reconstructed source parent: `f1da999cf518433d108867d14ea1476678911ebf`
- Donor repository: `/Users/juliushe/Desktop/CodexUsageMonitor`
- Reconstruction workspace: `/Users/juliushe/Developer/UMA-Reconstructed`
- Reconstruction branch: `codex/uma-source-reconstruction`
- Reconstruction commit: the local commit containing this closeout record, recorded by exact hash in the external thread-sync packet.
- Delivery description: behaviorally revalidated successor and new canonical development baseline.

## Reconstructed architecture

The source now implements the required single-owner path:

```text
Codex official/local source
→ AgentConnectorRegistry
→ one serialized UsageStore
→ SharedUsagePresentationPolicy
→ immutable shared presentation models
├── detailed main panel
└── Desktop Assistant
```

The Assistant is presentation-only. It has no connector, provider process, provider observer, polling timer, refresh path, selected-window calculation, usage conversion, scanner, private production usage cache, status item, or application lifecycle.

## Reconstructed behavior

- Finite remaining usage, unlimited usage, unavailable usage, stale last-valid usage, and failure states remain distinct.
- Five-hour and seven-day selection is shared across surfaces and uses refill-aware Maximum Decrement semantics with deterministic critical/depleted overrides.
- Connection state is independent from quota severity.
- The main panel retains shared Refresh, detailed windows, freshness, English and Simplified Chinese, adaptive appearance, accessibility, and bounded native settings scrolling.
- Desktop Assistant Regular geometry is `210 × 60 pt`.
- Desktop Assistant Minimalist geometry is `58.333333 × 30 pt` with a `15 pt` corner radius.
- Minimalist visible content is only the connection-status `C` mark and a full remaining percentage in 13 pt Medium system-rounded tabular typography.
- Selected-window information remains in the shared model, Tooltip, VoiceOver, Regular mode, and the main panel.
- The capsule itself is the full-width proportional quota indicator with one exterior contour and no internal usage bar.
- Assistant density, enablement, Always on Top, and display-relative position are persisted without adding a second provider path.

## Verification

- Donor baseline: `66 tests / 10 suites` passed before reconstruction.
- Reconstructed baseline: `92 tests / 13 suites` passed.
- Debug build: passed.
- Release build: passed.
- Strict-concurrency warnings-as-errors Release build: passed.
- Renderer matrix: Light, Dark, low quota, `100%`, Reduce Transparency, Increase Contrast, stale, unlimited, unavailable, English, and Simplified Chinese passed visual inspection.
- Runtime candidate: one app, one status item, one Assistant when enabled, zero Assistants when disabled, one shared connector, and no more than one app-owned app-server child.
- Owned-child termination: last-valid `35%` remained visible and exactly one child recovered.
- Repeated candidate relaunch and clean child shutdown: passed.
- Provisional package: arm64, readable plist, strict deep ad-hoc signature, system-only dependencies, scoped contents, privacy scan, and fixture isolation passed.
- A launch-time UserDefaults reentrancy defect found during black-box validation was repaired and covered by a focused empty-card regression test.

## Accepted binary oracle

The accepted Desktop bundle remained at:

`/Users/juliushe/Desktop/UMA_0.10.1.app`

Its verified identity remained:

- marketing version `0.10.1`
- build `202607231819`
- bundle identifier `com.kevinchen.CodexUsageMonitor`
- executable SHA-256 `71ba0032f8a17fb49abdd691069d46d053f8d684cba0d46b247efbfc5fa75622`

The accepted public Assistant displayed the same `C → percentage` hierarchy and the same live `35%` value. Its observed installed-binary window was `70 × 30 pt`; this reconstructed successor intentionally uses the current Founder-governed `58.333333 × 30 pt` contract. The accepted bundle, its attributes, and its preferences were not modified.

## Delivery boundary

The commit-exact `UMA_0.10.1.app`, source-archive hash, executable hash, exact reconstruction commit, and final clean-state proof are recorded in the external thread-sync packet. M3 remains paused. Claude Code, WorkBuddy, Manus, OneDrive content, and other providers were not inspected. No push, tag, release, notarization, deployment, or publication is part of this closeout.
