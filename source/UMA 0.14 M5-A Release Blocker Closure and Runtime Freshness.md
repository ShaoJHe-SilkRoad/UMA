# UMA 0.14 M5-A — Release Blocker Closure and Runtime Freshness

Status: M5-A engineering qualification PASS. Independent staged review and final Git readback are recorded separately in the evidence packet. M5-B and release are not authorized by this record.

## Authority and baseline

- Founder Goal: `/Users/juliushe/.codex/attachments/95913a02-a011-41b0-ae59-da25542983c9/goal-objective.md`.
- Worktree: `/Volumes/HE/DEV/UMA/Worktrees/UMA-0.14-Surface-Rebuild`.
- Branch: `codex/uma-0.14-surface-rebuild`.
- Starting HEAD: `9a2d1f6efe3deef372c3c13205d2a7e14f7e6127`.
- Starting tree: `9cdf41dbaef797d72704187801d69247f2233ffe`.
- Starting worktree CLEAN / index EMPTY. Before final qualification, HEAD/index remained unchanged and DEV_APFS was reverified: APFS, `/Volumes/HE/DEV`, writable, ownership enabled.
- Frozen 0.13 rollback HEAD/tree remain `f6dd617bb736d49b444dda4945d55e5b4606c915` / `16223ec6b1e3b3c1bf5a80191c97e9887498d622`.
- Preserve `keepMonitoringWhenWindowsClose`: default ON retains monitoring; explicit OFF may pause when all normal windows close. This is accepted behavior.

## Resulting behavior

1. The production AppDelegate creates one retained wake observer using the workspace notification center. Duplicate launch/wake registration is prevented; queued wake work is cancelled and active work drained during termination. Wake uses the canonical admitted-provider refresh policy. A real Claude connector with a synthetic bridge verifies zero automatic Accuracy Sync requests on wake.
2. Store/scanner/registry generation ownership is reserved before suspension. Stop/pause reject late noncooperative probes and cannot re-admit providers. Pause/resume serialization clears its task ownership before releasing waiters; listener acquisition has one owner and token-safe cleanup.
3. Codex late completions cannot overwrite explicit disconnect or a newer lifecycle. Request slots have owner leases; obsolete requests cannot release a replacement session's slot. Session replacement retires old requests without stopping the new child. Both replacement paths retain an internal typed interruption through the client; terminal cancellation and ordinary unknown errors remain distinct.
4. Codex event consumption stays responsive while one separately owned refresh task runs. Actual recovery notifications coalesce into one pending serial follow-up; errors alone do not retry. A queued event task yields to an existing manual lane without clearing its recovery flag. Stop/reconnect invalidate owners and pending work. Failed transport replacement cannot remain Connected.
5. Claude snapshot publication supports independent subscribers. Retained Desktop estimates are requalified against existing age/future-skew limits without another read. Every explicit one-shot terminal path publishes unchanged safe data so Settings receives diagnostics; failure does not change retained channels or successful-update timestamps.
6. Product last-success presentation uses actual provider success time, not cache republishing time. Missing data, remaining/estimated semantics, accepted quota algorithms and filtered legacy unlimited sentinel behavior remain protected by existing quota tests.

Accepted Quick Panel compositing, UI structure, version authority, Codex/Claude-only active support and inert ThreadOS product destination are outside the edit set. No provider admission, preference-domain wipe, production artifact replacement, or new persistent browser behavior was introduced.

## Failure-first and review evidence

| Evidence | Observed result before its repair |
| --- | --- |
| `reproduction.log` | Two tests / three issues: overlapping scan prepared twice; a second Claude subscriber displaced the first. |
| `reproduction-second.log` | Five tests including argument pairs / 23 issues: late stop/pause scan re-admission; late Codex success/failure overwrote stop; failed replacement remained ready; republishing changed last-success display; retained Desktop estimate outlived its age limit. |
| `focused-green-third.log` | Compiled, but included stale source assertions, overly strong stopped-snapshot assertions, a recovery fixture stuck before initial admission, and a real missing Claude diagnostics notification. The one task-owned helper was terminated; no aggregate PASS is claimed. |
| `affected-fourth.log` | 53 tests / four suites; only active recovery's non-stopped case failed (five issues): lost follow-up, old success time, stale state, admission withdrawal, unexpected disconnect. Shell, DualSource and Claude closure passed. |
| `recovery-order-red.log` | One test / one issue: event-triggered old request interrupted before recovery notification; registry published an empty list. This is actual withdrawal, not an intermediate waiting state. |

Issue counts are not defect counts. Compilation attempts that failed because of cache/toolchain preparation, an unterminated test literal or private fixture type references produced no runtime PASS evidence. The early recovery fixture hang was a fixture defect, not a production recovery reproduction.

Independent review also identified and closed capability-await disconnect, old request-slot release, pause/resume, listener acquisition, event-consumer blocking, queued event/manual ownership and both replacement-branch interleavings. These review findings are source-supported; newly added regression cases are not falsely described as separately executed RED tests. The intermediate pending-recovery-plus-unknown-error heuristic is superseded by the typed replacement cause in the final patch.

## Qualification

All commands use `script/test.sh`, its coherent Xcode-beta/macOS 27 toolchain and task-owned build/module caches at `/Volumes/HE/DEV/UMA/Build/uma014-m5a`. The wrapper disables package Keychain/netrc access. Runners explicitly unset `M1A_G1_LIVE_EVIDENCE`, `M1A_G2_LIVE_EVIDENCE`, `UMA_M6_G3_LIVE` and `UMA_M5RMX_UIFIX_REVIEW`.

Build scratch alone does not isolate preferences. Tests use their injected in-memory stores, unique test suites, synthetic transports, clocks and temporary mailboxes. The owned-child test launches only a task-owned synthetic shell protocol fixture and checks actual PID/termination behavior; it does not launch real Codex.

| Final execution | Result |
| --- | --- |
| `focused-converged` | PASS: 267 product tests / 22 suites; 23 bridge tests / one suite; exit 0. |
| `converged-repeat` | PASS: same source/test bytes and build, parallel execution, five repetitions, stop-on-failure; exit 0. Counts remain unique tests, not multiplied PASS claims. |
| `broad-regression` | PASS: one full run, 1,076 product tests / 103 suites plus 56 bridge tests / three suites, exit 0. Source/test hashes match focused and repeated verification. |
| Final independent staged review | Separate required decision: `final-staged-review.md` in the evidence packet; final Git readback in `post-commit-provenance.json`. |

The original timing inventory contains 18 findings across 17 distinct files. With one shared helper and three new M5-A suites, the scoped implementation audit covers 21 test files. No executable fixed-yield/short-sleep readiness loop remains in that scope. Retained waits are controlled clocks, real monitor cadence with event completion, cancellable timeout guards and bounded failure deadlines. Dormant WorkBuddy/Antigravity tests are outside this rewrite; no global zero-wait claim is made. Static closure and final focused/repeated/broad execution jointly close the scoped timing blocker. Opt-in live test functions return without executing their live bodies; framework PASS counts are not live evidence.

## Evidence location and provenance

Durable task evidence: `/Volumes/HE/DEV/UMA/Build/uma014-m5a/evidence/`.
Working evidence: `/private/tmp/uma014-m5a-evidence/`.

Command JSON files contain exact arguments, return codes and start/end times. Input JSON files bind changed source/tests to SHA-256. `goal-owned-files.json` records the exact 34-file set; `timing-final-audit.md`, `codex-recovery-order-repair.md` and final QA/review reports explain coverage and limits. Final Git HEAD/tree and clean index/worktree are recorded in the separate post-commit provenance artifact, avoiding a self-referential source commit claim.

This qualification does not claim a real Provider account read, physical sleep/wake soak, current review executable whole-tree reproducibility, RC package acceptance or production release. No real Accuracy Sync/Safari, credentials, production preferences/apps/Host, installation, signing, notarization, push, tag or release occurred. M5-B — install/migration/isolation — remains the next separately authorized task.

## Exact Goal-owned files

### Production source (12)

- `Sources/CodexUsageMonitor/App/CodexUsageMonitorApp.swift`
- `Sources/CodexUsageUI/Connectors/AgentConnectorRegistry.swift`
- `Sources/CodexUsageUI/Connectors/AgentUsageRuntime.swift`
- `Sources/CodexUsageUI/Connectors/ClaudeCodeUsageConnector.swift`
- `Sources/CodexUsageUI/Connectors/CodexUsageConnector.swift`
- `Sources/CodexUsageUI/Connectors/LocalProviderEligibilityScanner.swift`
- `Sources/CodexUsageUI/Models/ProviderProductState.swift`
- `Sources/CodexUsageUI/Services/CodexAppServerClient.swift`
- `Sources/CodexUsageUI/Services/CodexAppServerSession.swift`
- `Sources/CodexUsageUI/Services/CodexRefreshCoordinator.swift`
- `Sources/CodexUsageUI/Services/CodexWakeRefreshObserver.swift`
- `Sources/CodexUsageUI/Stores/UsageStore.swift`

### Tests (21)

- `Tests/ClaudeBrowserBridgeCoreTests/ClaudeSafariHostIPCTests.swift`
- `Tests/CodexUsageUITests/LocalActivityObserverTests.swift`
- `Tests/CodexUsageUITests/M1AG1DualSourceConnectorTests.swift`
- `Tests/CodexUsageUITests/M1AG1ProtocolContractTests.swift`
- `Tests/CodexUsageUITests/M1AG2ConnectorCoreTests.swift`
- `Tests/CodexUsageUITests/M1AG2DBGP1FunctionalRepairTests.swift`
- `Tests/CodexUsageUITests/M1AG2RefreshCoordinatorTests.swift`
- `Tests/CodexUsageUITests/M2WADBGLocalLiveAdmissionTests.swift`
- `Tests/CodexUsageUITests/M5ADBGG1BrowserSyncClosureTests.swift`
- `Tests/CodexUsageUITests/M5ATestSynchronization.swift`
- `Tests/CodexUsageUITests/M5AUTOG1ClaudeAutomaticRefreshTests.swift`
- `Tests/CodexUsageUITests/M5DBGN1ClaudeSnapshotTests.swift`
- `Tests/CodexUsageUITests/M5G2ClaudeConnectorSettingsTests.swift`
- `Tests/CodexUsageUITests/M5RMXClaudeSmartModeTests.swift`
- `Tests/CodexUsageUITests/M5RMXCloseSecurityTests.swift`
- `Tests/CodexUsageUITests/M5RMXConsentHandshakeDecouplingTests.swift`
- `Tests/CodexUsageUITests/M5RMXProductShellIsolationTests.swift`
- `Tests/CodexUsageUITests/UMA011G1AutoSearchTests.swift`
- `Tests/CodexUsageUITests/UMA014M5ACodexRuntimeFreshnessTests.swift`
- `Tests/CodexUsageUITests/UMA014M5ARegistryConcurrencyTests.swift`
- `Tests/CodexUsageUITests/UMA014M5AWakeLifecycleTests.swift`

### Closeout (1)

- `source/UMA 0.14 M5-A Release Blocker Closure and Runtime Freshness.md`
