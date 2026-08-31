# UMA 0.14 Claim Arbitration

Status: accepted B0 planning record

Evidence baseline: UMA 0.13.0 commit `f6dd617bb736d49b444dda4945d55e5b4606c915`

## Classification contract

Every post-release technical claim is assigned exactly one of:

- `CONFIRMED_DEFECT`
- `LIKELY_DEFECT_REQUIRES_REPRODUCTION`
- `ACCEPTED_LIMITATION`
- `FUTURE_ENHANCEMENT`
- `OUTDATED`
- `UNSUPPORTED`
- `DO_NOT_CHANGE`

An unverified concern is not promoted to a defect merely because it is plausible. Conversely, deterministic source evidence is sufficient when it proves an architectural contradiction without a live provider operation.

## Post-release claim arbitration

| ID | Candidate claim | Classification | Source-backed decision | 0.14 disposition |
|---|---|---|---|---|
| CA-01 | Production Claude Code `statusLine` path is fully qualified | `LIKELY_DEFECT_REQUIRES_REPRODUCTION` | Production packages and signs the relay, but configuration is hard-bound to `~/.claude/settings.json`; current checks do not prove the effective project/local/managed/custom configuration used by the active Claude surface. | Perform a bounded, content-free effective-scope and installed-path reproduction before changing the integration. Do not claim universal status-line health meanwhile. |
| CA-02 | Claude Code and Claude Desktop should share one status-line contract | `DO_NOT_CHANGE` | Terminal/IDE Claude Code and Claude Desktop expose different supported local surfaces. Current separation preserves truthful exact-versus-estimated semantics and privacy boundaries. | Keep separate source contracts. Never present Desktop estimation as exact per-response status-line evidence. |
| CA-03 | Smart-anchor storage lacks observable rejection reasons | `CONFIRMED_DEFECT` | Unsafe, corrupt, incompatible, or failed-rewrite loads collapse to an empty anchor collection. Diagnostics cannot distinguish “no anchor” from “anchor rejected.” | Add typed, content-free load/repair outcomes before the new health UI claims a reason. |
| CA-04 | Safari consent should enable recurring automatic refresh | `DO_NOT_CHANGE` | Recurring Safari automation is intentionally retired; Accuracy Sync is explicit and one-shot. | Preserve one-shot consent and no continuous Safari polling. |
| CA-05 | Estimation must use robust multi-anchor fitting before 0.14 | `FUTURE_ENHANCEMENT` | The engine retains multiple anchors but calibrates from the latest valid adjacent pair. The visible result is explicitly approximate and conservative. | Do not block the 0.14 UI migration. Requalify separately if pursued. |
| CA-06 | Mixed-model calibration is always stable | `LIKELY_DEFECT_REQUIRES_REPRODUCTION` | The family-set key detects family-set changes, but a changed mixture inside the same composite set can remain admissible with one total-token count. | Reproduce weighting effects. Fail closed or label the limitation until qualified. |
| CA-07 | Estimator shadow validation is mandatory for B0 | `FUTURE_ENHANCEMENT` | No durable exact-versus-estimated error ledger exists; prior same-time comparison remains pending. | Useful for later estimator requalification, not required to define 0.14 surfaces. |
| CA-08 | App Translocation can persist a broken status-line relay path | `LIKELY_DEFECT_REQUIRES_REPRODUCTION` | The installed command embeds `Bundle.main.bundleURL`; no canonical-install/translocation guard exists. The released installed app has not been shown to fail this way. | Reproduce on a quarantined/translocated candidate before repair. |
| CA-09 | Tests can mutate real process preferences | `CONFIRMED_DEFECT` | `UsageStore` accepts injected defaults, but `setLanguage` writes to `UserDefaults.standard`; an isolated-suite test calls it. | Inject one preference authority and add pollution regression coverage. |
| CA-10 | Connector observer lifecycle supports all current and future UI consumers | `CONFIRMED_DEFECT` | `ClaudeCodeUsageConnector` retains one stream continuation. Registry and Claude Settings both subscribe; a later subscription can displace the earlier subscriber. | Implement deterministic multi-subscriber publication before adding more 0.14 surfaces. |
| CA-11 | Fixed `Task.yield` and sleep synchronization is harmless | `CONFIRMED_DEFECT` | The test tree contains many fixed yield/sleep sites, including single-yield publication waits and fixed bridge delays. These are timing assumptions rather than observed-state synchronization. | Replace affected test waits with explicit task-start/state handshakes; do not inflate sleeps. Production deadline sleeps require separate evidence. |
| CA-12 | Privacy allowlists should be generalized for easier diagnostics | `DO_NOT_CHANGE` | Provider descriptors, bounded record projection, ownership/mode checks, and strict persisted-anchor shapes form a layered privacy boundary. | Keep content-free diagnostics and strict allowlists. Do not add broad telemetry. |
| CA-13 | Wake refresh behavior is coherent and complete | `CONFIRMED_DEFECT` | A wake observer claims to bridge wake into refresh but is not production-instantiated; `UsageStore.handleApplicationWake()` is deliberately inert while connectors accept a wake trigger. | Define one privacy-safe wake policy, including which providers may refresh and when. Do not add a second scheduler or unconsented reads. |
| CA-14 | The current split-host Claude handoff is obsolete legacy code | `OUTDATED` | Production builds the immutable Safari Host and App-Group handoff; this is the accepted architecture. The standalone native-host target serves a different compatibility surface. | Do not delete or replace the split-host handoff under a “legacy” cleanup claim. |
| CA-15 | Release version has one source of truth | `CONFIRMED_DEFECT` | `0.13.0` is duplicated across packaging, three signing plist templates, and manifest rewriting. | Introduce one version/build input that populates app, Host, Companion, manifest, and runtime metadata. |
| CA-16 | Commit-exact package retention is uncontrolled clutter | `ACCEPTED_LIMITATION` | Unique output paths and sealed archives intentionally preserve provenance and refuse overwrite. | Keep external retention; do not add automatic deletion during 0.14 UX work. |
| CA-17 | Internal `CodexUsageMonitor` naming must be mass-renamed for UMA 0.14 | `ACCEPTED_LIMITATION` | Public names are UMA; internal target, executable, and support paths are compatibility-sensitive. | Use UMA for new public surfaces. Defer internal migration unless a separately tested data/path migration is justified. |
| CA-18 | Oversized Claude connector ownership is harmless | `CONFIRMED_DEFECT` | The connector owns consent, browser health/actions, event processing, Local Smart readers, status monitoring, anchors, estimation, source selection, retention, diagnostics, and presentation reduction in one large type. | Incrementally extract source adapters, anchor/state reduction, and Accuracy Sync orchestration. Preserve the accepted transport and privacy architecture. |

## UX claim arbitration

| Claim | Decision | Reason |
|---|---|---|
| “The menu panel is sufficient as the whole application.” | `CONFIRMED UX PROBLEM` | It combines glance, detailed dashboard, activity/cost, and configuration inside a transient 370-point surface. |
| “A ground-up SwiftUI rewrite is necessary.” | `NOT ACTUALLY A PROBLEM` | Existing AppKit lifecycle and SwiftUI-hosted content support incremental native windows and commands. |
| “The Assistant needs another Minimalist mode.” | `DO_NOT_CHANGE` | One protected Regular/Minimalist density contract already exists. A second product-wide meaning would be confusing. |
| “Every provider card has a double border.” | `OUTDATED` | Current contour ownership and nested-background suppression address the accepted regression. |
| “The Assistant is not draggable.” | `OUTDATED` | The native drag recognizer and click arbitration are accepted and tested. |
| “Glass/material must be removed.” | `DESIGN PREFERENCE` | The defect is hierarchy and overuse risk, not material itself. Use it at top-level surfaces with accessibility fallbacks. |
| “Serif typography is inherently un-Mac-like.” | `DESIGN PREFERENCE` | Reserve it for branded/display roles; use system semantic text for navigation and dense body copy. |
| “Provider count should remain the main headline.” | `CONFIRMED UX PROBLEM` | It does not answer how much usable quota remains or what may pause work next. |
| “All six candidate state words form one enum.” | `UNSUPPORTED` | Precision, freshness, availability, and health are orthogonal axes. |
| “Large-text preview proves accessibility.” | `UNSUPPORTED` | Preview-only scaling does not prove production semantic text scaling or keyboard/focus behavior. |

## 0.15 concept arbitration

No tracked 0.15 planning or design artifact exists in the frozen repository or canonical UMA workspace. Searches for `UMA 0.15`, `v0.15`, and `0.15.0` produced no planning evidence. Numeric opacity literals are not design documents.

Therefore:

- No purported 0.15 concept is classified as `ADOPT_FOR_0.14`, `REVISE_FOR_0.14`, `DEFER_TO_0.15`, or `REJECT` without an actual artifact.
- The native main window, Settings, commands, quick panel, Assistant parity, provider detail, Activity/history, ThreadOS seam, App Store architecture, and visual language are evaluated directly from 0.13 evidence and the 0.14 goal.
- If Founder later supplies a 0.15 concept artifact, it requires a new evidence-backed arbitration; this B0 record must not be retroactively treated as having reviewed unseen material.

## Binding decisions

1. Preserve shared quota truth and provider semantics while changing presentation architecture.
2. Fix multi-subscriber state publication before additional surfaces depend on it.
3. Make anchor rejection and provider health observable with content-free reasons.
4. Preserve one-shot Safari Accuracy Sync and the privacy allowlist.
5. Keep Claude Code and Desktop source semantics separate.
6. Defer unproven translocation, mixed-model, and status-line repairs until bounded reproduction.
7. Treat version authority and test-state pollution as release/test infrastructure defects, not visual polish.
8. Refactor large ownership incrementally; do not rewrite provider connectors or the immutable Safari architecture.
