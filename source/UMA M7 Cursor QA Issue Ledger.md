# UMA M7 Cursor QA Issue Ledger

**Goal:** M7-G1
**Date:** 2026-08-10
**Decision:** `CONDITIONAL GO — FALLBACK ARCHITECTURE REQUIRES FOUNDER DECISION`
**Only next task:** `Founder provider-controlled browser fallback architecture decision`

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

## Exact authorized edit set

```text
Tests/CodexUsageUITests/M7G1CursorSourceAdmissionTests.swift
source/UMA M7 Cursor Local Source Dossier.md
source/UMA M7 Cursor Admission Decision.md
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
Authenticated quota reads: 0/3
Cursor login/browser actions: 0
Provider prompts/tasks: 0
Intentional quota spend: 0
Credential/private-state reads: 0
Automatic retries: 0
```

Rejected routes remain: API key, copied token, cookie, Keychain, private endpoint,
browser-profile import, manual quota and inferred quota.

## Verification ledger

| Check | Result |
|---|---|
| Source/protocol examiner | PASS — direct local/CLI quota source not admitted; live probe gate remained closed |
| Privacy/authentication examiner | PASS — allowlist, rejected routes and safe process contract established |
| QA/admission runner | PASS — five-file additive edit set and deterministic decision matrix locked |
| Focused M7-G1 tests | PASS — 18/18 |
| Complete deterministic test suite | PASS — 599 UI plus 18 bridge tests; 617/617 across 64 suites |
| Debug/Release/strict builds | Proportionally not rerun — no production/package code changed; the full suite rebuilt Debug products and the accepted B0 build evidence remains applicable |
| `git diff --check` | PASS |
| Privacy/identity/secret scan | PASS — only explicit policy vocabulary and synthetic `.invalid` sentinels; no private value or raw provider payload |
| Protected M5/M6 and accepted-provider audit | PASS — no diff in protected runtime, browser extension, package, script, reference, M5 or M6 paths; accepted M5 52-file manifest unchanged |
| Protected Desktop UMA | PASS — executable SHA-256 unchanged at `88ffbb48de43253f7289fe038dff9d0b195e61398f969439ff5c8729ecbef91a` |
| Independent staged-index review | PASS — source/protocol, privacy/authentication and QA/admission examiners accepted the exact five-file cache with no actionable defect |
| Post-commit clean worktree/index | Pending final run |

## Completion contract

All four current M7-G1 records must agree:

```text
Primary decision: CONDITIONAL GO — FALLBACK ARCHITECTURE REQUIRES FOUNDER DECISION
Direct local/CLI source: NO-GO
Authenticated quota reads: 0/3
Provider prompts/tasks/spend: 0/0/0
Cursor remains unsupported and hidden
M7-G2 remains locked
Only next task: Founder provider-controlled browser fallback architecture decision
```
