# UMA M7 Cursor QA Issue Ledger

**Goal:** M7-G1B
**Date:** 2026-08-10
**Decision:** `NO-GO`
**Only next task:** Founder source-direction decision

## Issue ledger

| ID | Severity | Discovery | Evidence / risk | Disposition | Verification | Status |
|---|---:|---|---|---|---|---|
| M7G1-001 | Gate | Current-device inventory | Cursor app and CLI are absent; installed identity/help cannot be verified | Record unavailable, not failed; do not install because no admissible quota contract is documented | Exact standard paths, PATH and registrations checked without private discovery | Closed |
| M7G1-002 | Blocking | Official CLI review | `/usage` is documented as activity streaks/stats, while JSON output belongs to agent execution with tools | Reject as plan-quota source; no prompt or CLI execution | Official docs/changelog cross-check; deterministic admission test | Closed |
| M7G1-003 | Blocking | Schema review | No official individual current quota schema, unit, stable pool identity, reset/freshness or repeated-read contract | Fail closed; no invented decoder or denominator | Durable records and decision tests require UNAVAILABLE fields | Closed |
| M7G1-004 | Blocking | Authentication/privacy review | Team Admin API requires an API key and exposes identity/event/spend data | Reject credential and wrong-scope route | Privacy contract plus deterministic route test | Closed |
| M7G1-005 | Architecture | Source-priority review | Official dashboard has a human-visible Usage surface, but no admitted structured bridge | Classify conditional fallback; require Founder architecture decision before new browser/privacy work | Direct implementation remains locked in tests and records | Closed |
| M7G1-006 | Privacy | Process/evidence review | Broad process argv/environment inspection could expose provider-owned metadata | Adopt exact executable/PID/count/resource/exit contract; prohibit broad argv/environment reads | Independent privacy examination | Closed |
| M7G1-007 | Regression | Existing-provider review | Cursor admission work could accidentally register runtime or alter four accepted mechanisms | Limit edit set to docs plus isolated test harness | Protected-zone diff PASS; full suite 617/617 PASS | Closed |
| M7G1B-001 | Gate | Current official semantics | Cursor documents two paid-plan pools and remaining allowance, while the live Free account exposes one differently labelled percentage | Treat account mode as authoritative; do not transfer paid-plan semantics to the Free percentage | Current Cursor-owned documentation plus live three-route classification | Closed |
| M7G1B-002 | Privacy | Isolated probe design | A shared/default browser store or login-page script could expose unrelated session or page data | Dedicated persistent store, sandbox plus outbound network only, no login-page DOM or page-content output | Entitlement, source and bundle audit before launch | Closed |
| M7G1B-003 | Gate | Provider authentication | One Human-controlled attempt reached a provider-side embedded-auth compatibility failure; normal reopen/reload returned to login | Reject isolated architecture; do not retry or bypass; activate Safari fallback | Sanitized route classification only; authenticated Spending reads remain 0 | Closed |
| M7G1B-004 | Blocking | Live schema | One stable `Free Plan usage` percentage was repeatedly observed, but neither bounded UI/accessibility semantics nor current Free-plan documentation defines used versus remaining; no same-pool denominator was present | Return `NO-GO`; do not infer from value, progress direction or paid-plan docs | Eight sanitized observations across the three official route classes; ambiguity reproduced | Closed |
| M7G1B-005 | Regression | Existing mechanisms | A source-admission study could alter production provider/browser code | Five documentation/test files only; temporary probes removed at closeout | Protected-zone and final diff audit PASS | Closed |
| M7G1B-006 | Privacy | Human-supplied screenshot | Account-identity metadata appeared unexpectedly in transient context | Do not reproduce, inspect further, copy, hash or retain; exact task-path containment scan; resume only with narrower sanitized Safari contract | No incident identity/page text in five M7 files or probe source; no task-owned screenshot/log/evidence/payload | Closed |
| M7G1B-007 | Gate | Safari fallback | Safari restart reset v2 enablement and exact-site access required a separate Human grant | Re-enable only v2, retain old companion disabled, grant only `cursor.com`, then resume without another login | Post-restart authentication continuity, v2 enablement, exact-site permission and native handoff PASS | Closed |
| M7G1B-008 | Privacy | Safari accessibility inspection | Two filtered state reads transiently exposed the same exact-quota data class: the first admitted dashboard text and a later cleanup-readiness filter matched the provider origin | Do not reproduce or retain it; remove dashboard accessibility reads entirely; use settings-window-only UI evidence and sanitized v2 receipts | Retained exact-value/DOM/URL copies: 0; exact probes/containers removed; no page-state read after final repair | Closed |
| M7G1B-009 | Admission | Final browser decision | Browser lifecycle and privacy gates passed, but mandatory numeric direction did not | `NO-GO`; Cursor remains unsupported; M7-G2 locked | Final records and deterministic decision tests | Closed |

## Exact authorized edit set

```text
Tests/CodexUsageUITests/M7G1CursorSourceAdmissionTests.swift
source/UMA M7 Cursor Browser Source Dossier.md
source/UMA M7 Cursor Browser Admission Decision.md
source/UMA M7 Cursor Privacy Contract.md
source/UMA M7 Cursor QA Issue Ledger.md
```

```text
Production source files changed: NO
Browser extension files changed: NO
Package scripts changed: NO
M5/M6 records changed: NO
Codex mechanism changed: NO
Claude mechanism changed: NO
WorkBuddy mechanism changed: NO
Antigravity mechanism changed: NO
Cursor runtime implemented: NO
```

## Operation accounting

```text
Task-owned isolated probe launches: 3
Provider-controlled login sessions opened: 1
Human login completions: 1
Authenticated dashboard route navigations: 4
Successful sanitized observations: 8
Safari fallback containing-app launches: 3
Provider prompts/tasks: 0
Intentional quota spend: 0
Credential/private-state reads: 0
Unexpected Human-supplied identity exposures: 1 transient
Unexpected exact-quota accessibility exposures: 2 transient
Retained incident identity/screenshot/log/payload copies: 0
Retained exact-quota/DOM/URL copies: 0
Automatic retries: 0
```

Rejected routes remain: API key, copied token, cookie, Keychain, private endpoint,
browser-profile import, manual quota and inferred quota.

## Verification ledger

| Check | Result |
|---|---|
| Source/protocol examiner | PASS — available/loading route separation, setup-only outcome and evidence-backed `NO-GO` are coherent |
| Privacy/authentication examiner | PASS — cleanup, zero-retention incident containment and prohibited credential boundaries are coherent |
| QA/admission runner | PASS — exact five-file cached scope, test accounting and protected-path boundary are coherent |
| Focused M7-G1B tests | PASS — 27/27 |
| Complete deterministic test suite | PASS — explicit `--no-parallel`; 608 UI + 18 bridge = 626/626 across 64 suites. Two earlier unrelated lifecycle timeout flakes passed in isolation and the final serial run passed. |
| Debug/Release/strict builds | Proportionally not rerun — no production/package code changed; the full suite rebuilt Debug products and the accepted B0 build evidence remains applicable |
| `git diff --check` | PASS |
| Privacy/identity/secret scan | PASS — incident containment scan found no supplied identity/page text in the five M7 files or probe source and no task-owned screenshot/log/evidence/payload; only policy vocabulary and synthetic `.invalid` sentinels remain |
| Protected M5/M6 and accepted-provider audit | PASS — no diff in protected runtime, browser extension, package, script, reference, M5 or M6 paths; accepted M5 52-file manifest unchanged |
| Protected Desktop UMA | PASS — executable SHA-256 unchanged at `88ffbb48de43253f7289fe038dff9d0b195e61398f969439ff5c8729ecbef91a` |
| Browser cleanup | PASS — both companions disabled/unregistered; Safari unsigned mode `Off`; exact probe roots and three task-owned container records absent; no task-owned process remains |
| Independent staged-index review | PASS — exact five-file cached scope; no unstaged changes; no blocking or actionable issue |
| Post-commit clean worktree/index | Delivery gate — verified after this commit and reported in the final M7-G1B handoff |

## Completion contract

The four active M7-G1B records/tests must agree after the live gate:

```text
Primary decision: NO-GO
Direct local/CLI source: NO-GO
Successful sanitized observations: 8
Provider prompts/tasks/spend: 0/0/0
Cursor remains unsupported and hidden
M7-G2 remains locked
Only next task: Founder source-direction decision
```
