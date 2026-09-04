# UMA 0.14 edge-fix closeout and M5 readiness

Status: Founder-accepted; pending exact Git closeout

Date: 2026-09-04

## Quick Panel compositing acceptance

The Founder physically accepted the unique review build with these results:

- white background + Light appearance: `PASS`;
- white background + Dark appearance: `PASS`;
- rectangular backing haze: `ABSENT`;
- ghost ring: `ABSENT`.

The accepted implementation replaces the Quick Panel's outer
`NSGlassEffectView` with one layer-backed, rounded, clipped AppKit surface. The
panel remains clear, nonopaque, and shadowless; its one exact-bounds
`NSHostingView` owns content but no second outer material, contour, or shadow.
The binary-isolation matrix first reproduced the exterior pixel effect when
native glass was added at Test D. The accepted UI content, dimensions, colors,
typography, actions, provider state, Settings, and Desktop Wizard were not
changed by this repair.

### Accepted review artifact

- App: `/Volumes/HE/DEV/UMA/Packages/uma-0.14-edge-final-review-20260904/UMA 0.14 Edge Final Review.app`
- Bundle identifier: `com.silkrd.uma.dev.uma014.edge-final-review`
- Marketing version: `0.14.0`
- Build: `202609040003`
- Main executable SHA-256:
  `8739728cd4fb9b66a1ce254464e7def3d5fea47848393cd219faeb78bf6d4fb8`
- Build parent at the start of the repair:
  `6b17af4902f654bbe0cebcb9367ad4ae86ecfcae`
- Accepted product-source patch SHA-256:
  `ae0c44c15520db4dec2742a9627ed5ce57c5225b863095abfe07af5b47de37eb`
- Accepted six-file repair patch SHA-256 before this closeout document:
  `20a3302627c46560eec34bb341973a2eded14c0cc12f48c2734c28e9f56e8e36`

The reviewed app is preserved unchanged. The build predates the final
test-wording correction and this documentation, neither of which enters the
application executable. The build did not embed a Git commit or a complete
source manifest, so executable bytes alone cannot prove whole-tree provenance.
The defensible binding is narrower: the reviewed executable hash is tied to
the unchanged product-source files below, while the final Git closeout report
must record the corrective commit and tree that contain those same product
sources plus their accepted tests and this document. This document does not
embed the hash of its own containing commit because that identity is recursive.

### Accepted repair manifest

| Path | SHA-256 after acceptance | Role |
|---|---|---|
| `Sources/CodexUsageMonitor/App/AdaptivePanelMaterialHostView.swift` | `b2d57241239418eb0e405f1184fedd5d75526c6dda14793127dcf30e870e9947` | one clipped layer-backed surface |
| `Sources/CodexUsageMonitor/App/QuickPanelPopoverController.swift` | `0a10643effc3bcf9b94afc9efdfe2f210668f723e5e171d6bebbf13a3c9e898b` | clear, nonopaque, shadowless panel host |
| `Tests/CodexUsageUITests/M1AG2DBGNativeGlassContractTests.swift` | `5a3c987ac6afa5c9672817f19a3113c712abc9e2177808aa927d84b4858a1830` | single-host and 100-replacement contracts |
| `Tests/CodexUsageUITests/STABG1StabilityContractTests.swift` | `3d3f21d0d3c38f0d64826512cf830c7b35438127f246246cb1a7781cd8b338ab` | stable surface regression contract |
| `Tests/CodexUsageUITests/UMA011G2VisualSystemTests.swift` | `c77eb42241e47e778e610ba98e8d0cb757dbfaf28b42d8018aa840047cb1c46e` | appearance-refresh source contract |
| `Tests/CodexUsageUITests/UMA014M3RQuickPanelHostTests.swift` | `e95bb884ef41add3d98e9367269856c7253bd1cddb85e5da2612a95cfd83577d` | Quick Panel geometry/ownership contract |

## M5 readiness ledger

This ledger reconciles the accepted B0 findings with the current source. It is
readiness classification, not authorization to implement M5 or to exercise a
platform permission.

| Area | Classification | Current evidence | M5 close condition |
|---|---|---|---|
| Typed application preferences and test-domain isolation | `ALREADY CLOSED` | `ApplicationPreferences` supplies production, in-memory, and isolated-suite stores; `UsageStore.setLanguage` writes through its injected preference authority; INFRA/M4 tests cover round-trip, legacy keys, and isolated construction. | Preserve the boundary and rerun focused pollution/migration tests in the RC environment. |
| Non-destructive 0.13 to 0.14 preference migration and rollback compatibility | `ALREADY CLOSED` | The application-foundation contract preserves persisted keys, uses additive defaults, blocks unreadable/future envelopes, and requires no schema reset. | Verify a copied, sanitized legacy preference fixture through first launch and rollback; never use the real user domain as a test fixture. |
| Single development version/build authority | `ALREADY CLOSED` | `Configuration/UMAProductVersion.plist` and its strict reader drive the current 0.14 development package and record Safari protocol compatibility. | Preserve strict mismatch rejection when extending the authority to the exact RC package. |
| Quick Panel backing/edge compositing | `ALREADY CLOSED` | Real A-E isolation, zero outside-mask differential pixels, physical Founder Light/Dark acceptance, lifecycle tests, and independent examination. | Regression-only; do not reopen unless new contradictory physical evidence appears. |
| Application wake/freshness ownership | `REPRODUCED RELEASE BLOCKER` | `UsageStore.handleApplicationWake()` has a bounded admitted-provider policy, but production source does not construct `CodexWakeRefreshObserver`; the only construction found is in a test. The visible refresh-on-wake preference therefore lacks a proven production notification owner. | Establish one application-owned observer, prove one wake produces at most one admitted-provider refresh, and prove no discovery, consent bypass, duplicate scheduler, or refresh burst. |
| Timing-sensitive test synchronization | `REPRODUCED RELEASE BLOCKER` | Fixed `Task.yield` and short `Task.sleep` synchronization remains in affected provider, bridge, and UI tests identified by B0. Presence is directly reproducible; stability under parallel/load execution is not yet established. | Replace affected synchronization with observable state/task-start handshakes; pass individual, parallel, and load runs without longer sleeps or global serialization. |
| Genuine Codex freshness, recovery, and lifecycle | `VERIFY` | One application-owned runtime and connector coordination are implemented; accepted UI cycles did not regress Codex. Synthetic and prior bounded runtime evidence is not an exact-source RC soak. | With a task-owned RC build, prove first real snapshot, freshness transitions, refresh, window/panel churn, bounded transport recovery, explicit disconnect, and no duplicate session/process. |
| Genuine Claude freshness, recovery, and lifecycle | `VERIFY` | Local Smart and one-shot Accuracy Sync architecture remain protected; no Claude source changed in the edge repair. B0 still identifies active status-line scope and translocated relay-path questions. | Run content-free scope/path qualification first; use no provider read unless separately authorized; prove exact/estimated/stale ordering, recovery, and one-shot Browser behavior without raw content. |
| Privacy boundary and retained-state handling | `VERIFY` | Typed preferences and existing privacy allowlists are present, and the edge repair changes no provider/privacy source. RC package and migration have not yet received a final secret/raw-content audit. | Test sanitized migration fixtures, unsafe/corrupt retained-state outcomes, production-domain nonpollution, and package/log exclusion. |
| Stable install paths and translocation behavior | `VERIFY` | B0 marked ephemeral relay persistence under translocated launch as reproduction-required. No signed 0.14 RC has yet proved canonical versus translocated behavior. | Qualify canonical install, translocation, helper resolution, relaunch, and rollback without persisting ephemeral paths. |
| Immutable Safari Host/helper compatibility and development isolation | `VERIFY` | Production 0.13 Host/Companion are protected and the 0.14 development identity is separate. The current review build does not qualify an RC Host/helper package. | Prove protocol/version/App Group/generation compatibility from signed package metadata, absence of test identities in production payloads, and no mutation of installed 0.13 artifacts. |
| Exact-source RC packaging and provenance | `VERIFY` | Current review provenance is deliberately limited to executable hash plus product-source manifest; no exact-source RC package has been produced. | Build once from a clean named commit/tree, record app/nested executable/archive hashes, reject source/package drift, and preserve the frozen bytes through signing and qualification. |
| Rollback readiness | `VERIFY` | The product contract preserves existing 0.13 data and protected artifacts, but an exact 0.14 RC rollback transaction has not run. | Record rollback app/package hashes and paths; test install, launch, data compatibility, and byte-preserving rollback without deleting the known-good 0.13 artifacts. |
| Broad Claude connector decomposition | `DEFER` | B0 identifies excessive ownership in `ClaudeCodeUsageConnector`; no current evidence requires a rewrite to ship safely. | Defer structural extraction unless a reproduced M5 blocker cannot be repaired within existing boundaries; require parity tests before any extraction. |
| Claude mixed-model estimator requalification | `DEFER` | B0 requires separate evidence for changed family weighting; it is not an RC packaging prerequisite absent a behavior change. | Keep fail-closed behavior and schedule a separately governed estimator task. |
| Dormant or rejected providers and optional features | `DEFER` | Current accepted product hides unsupported/dormant providers and M5 has no authority to re-admit them. | Do not reintroduce WorkBuddy manual Credit, absent Antigravity, Cursor, Kimi, or new features. |

### Proposed M5 scope

M5 should close only release-critical debt: the real wake/freshness owner,
observable test synchronization, exact-source Codex/Claude lifecycle evidence,
preference/privacy migration qualification, stable install/helper/Host identity,
commit-exact RC packaging, and rollback readiness. It must preserve current UI,
provider semantics, Maximum Decrement, one-shot Claude Accuracy Sync, privacy
allowlists, dormant-provider exclusion, and the accepted Quick Panel surface.

### M5 action-authorization table

This table describes expected gates. It grants no authority and never
overrides macOS, sandbox, Keychain, Safari, provider, signing, or network
permission requirements.

| Action | M5 need | Authorization state after this closeout |
|---|---|---|
| Read-only source, Git, package, and local diagnostic inspection | Required | Not started; permitted only under the future explicit M5 scope and active platform policy. |
| Edit release-critical source/tests in the canonical 0.14 worktree | Required for reproduced blockers only | Not authorized by this closeout; requires explicit M5 start. |
| Focused tests, parallel/load determinism, local unsigned development builds | Required | Not authorized by this closeout; future M5 authorization does not waive filesystem or execution guards. |
| Content-free Codex/Claude lifecycle probes | Required | Requires explicit bounded M5 live-test authority and must retain only reason/stage metadata. |
| Provider/account reads, Claude Accuracy Sync, credential or Keychain access | Not assumed | Separate visible Founder authorization and any platform permission are required; no implicit authorization. |
| Install/replace a 0.14 RC or reconcile helpers/Host | Required near RC | Separate exact-path mutation authority and any OS security interaction are required; protect 0.13 and Safari Bridge. |
| Developer ID signing or provisioning-profile use | Release gate | Separate signing authorization; no fallback identity or entitlement change. |
| Notarization, production replacement, push, tag, or release | Outside M5 readiness | Prohibited until separately and explicitly authorized; platform prompts remain controlling. |

## Protected artifacts

This closeout does not modify, rebuild, sign, replace, or delete:

- `/Users/juliushe/Desktop/UMA_0.13.0.app`;
- `/Users/juliushe/Applications/UMA Safari Bridge.app`;
- `/Users/juliushe/Desktop/UMA_0.11.app`;
- the accepted Edge Final Review app and its live artifact package.
